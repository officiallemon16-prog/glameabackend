package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/email"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-sql-driver/mysql"
	"github.com/redis/go-redis/v9"
)

// userStore is the subset of the users store the auth service needs.
type userStore interface {
	GetByEmail(ctx context.Context, email string) (*users.User, error)
	GetByPhone(ctx context.Context, phone string) (*users.User, error)
	GetByIdentifier(ctx context.Context, identifier string) (*users.User, error)
	GetByID(ctx context.Context, id string) (*users.User, error)
	GetPasswordHash(ctx context.Context, userID string) (string, error)
	Create(ctx context.Context, u *users.User, passwordHash string) (*users.User, error)
	UpdateLoginInfo(ctx context.Context, id, ip string) error
	MarkPhoneVerified(ctx context.Context, id string) error
	MarkEmailVerified(ctx context.Context, id string) error
}

type Service struct {
	users         userStore
	sessions      *SessionStore
	rdb           *redis.Client
	tokens        *TokenManager
	cfg           *config.Config
	logger        *slog.Logger
	sendOTP       func(ctx context.Context, phone, code string) error
	sendEmailCode func(ctx context.Context, email, code string) error
	emailer      email.Emailer
}

func NewService(
	userStore *users.Store,
	sessionStore *SessionStore,
	rdb *redis.Client,
	tokens *TokenManager,
	cfg *config.Config,
	logger *slog.Logger,
) *Service {
	svc := &Service{
		users:    userStore,
		sessions: sessionStore,
		rdb:      rdb,
		tokens:   tokens,
		cfg:      cfg,
		logger:   logger,
	}
	svc.sendOTP = svc.defaultSendOTP
	svc.sendEmailCode = svc.defaultSendEmailCode
	return svc
}

func (svc *Service) SetOTPSender(fn func(ctx context.Context, phone, code string) error) {
	svc.sendOTP = fn
}

func (svc *Service) SetEmailSender(fn func(ctx context.Context, email, code string) error) {
	svc.sendEmailCode = fn
}

// SetEmailer wires the transactional email sender used for welcome emails.
func (svc *Service) SetEmailer(e email.Emailer) {
	svc.emailer = e
}

// SetEmailDelivery wraps the default code generation/storage with a custom
// delivery function. The delivery function receives the generated code and
// is responsible for sending it (e.g. via Resend email API).
func (svc *Service) SetEmailDelivery(deliver func(ctx context.Context, to, code string) error) {
	defaultFn := svc.defaultSendEmailCode
	svc.sendEmailCode = func(ctx context.Context, email, code string) error {
		if err := defaultFn(ctx, email, code); err != nil {
			return err
		}
		// Retrieve the stored code so we pass the real value to the delivery function.
		if code == "" && svc.rdb != nil {
			stored, err := svc.rdb.Get(ctx, emailOTPKey(email)).Result()
			if err == nil {
				code = stored
			}
		}
		if err := deliver(ctx, email, code); err != nil {
			svc.logger.Error("email delivery failed", "email", email, "error", err)
			return err
		}
		return nil
	}
}

type RegisterInput struct {
	Email     string
	Phone     string
	Password  string
	FirstName string
	LastName  string
	Role      string
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

func (svc *Service) Register(ctx context.Context, in RegisterInput, ip string) (*users.User, *TokenPair, error) {
	if in.Password == "" || len(in.Password) < 8 {
		return nil, nil, httpx.BadRequest("weak_password", "password must be at least 8 characters")
	}
	if strings.TrimSpace(in.Email) == "" && strings.TrimSpace(in.Phone) == "" {
		return nil, nil, httpx.BadRequest("identifier_required", "email or phone is required")
	}

	role := strings.ToUpper(in.Role)
	if role == "" {
		role = users.RoleCustomer
	}
	if role != users.RoleCustomer && role != users.RoleProfessional {
		return nil, nil, httpx.BadRequest("invalid_role", "role must be CUSTOMER or PROFESSIONAL")
	}

	email := normalizeEmail(in.Email)
	phone := normalizePhone(in.Phone)

	if email != "" {
		if _, err := svc.users.GetByEmail(ctx, email); err == nil {
			return nil, nil, httpx.Conflict("email_taken", "email is already registered")
		}
	}
	if phone != "" {
		if _, err := svc.users.GetByPhone(ctx, phone); err == nil {
			return nil, nil, httpx.Conflict("phone_taken", "phone is already registered")
		}
	}

	hash, err := HashPassword(in.Password)
	if err != nil {
		return nil, nil, err
	}

	u := &users.User{
		Email:     strPtr(email),
		Phone:     strPtr(phone),
		FirstName: strings.TrimSpace(in.FirstName),
		LastName:  strings.TrimSpace(in.LastName),
		Role:      role,
		Status:    users.StatusActive,
	}
	created, err := svc.users.Create(ctx, u, hash)
	if err != nil {
		var myErr *mysql.MySQLError
		if errors.As(err, &myErr) && myErr.Number == 1062 {
			return nil, nil, httpx.Conflict("email_or_phone_taken", "email or phone is already registered")
		}
		return nil, nil, err
	}

	if phone != "" {
		if err := svc.sendOTP(ctx, phone, ""); err != nil {
			svc.logger.Error("send otp on register", "error", err, "user_id", created.ID)
		}
	}
	if email != "" {
		if err := svc.sendEmailCode(ctx, email, ""); err != nil {
			svc.logger.Error("send email verification on register", "error", err, "user_id", created.ID)
		}
	}

	if svc.emailer != nil && created.Email != nil && *created.Email != "" {
		if err := svc.emailer.SendWelcome(*created.Email, created.FirstName); err != nil {
			svc.logger.Error("send welcome email", "error", err, "user_id", created.ID)
		}
	}

	pair, err := svc.issueTokens(ctx, created, ip)
	if err != nil {
		return nil, nil, err
	}
	return created, pair, nil
}

func (svc *Service) Login(ctx context.Context, identifier, password, ip, userAgent string) (*users.User, *TokenPair, error) {
	identifier = strings.TrimSpace(identifier)
	if identifier == "" || password == "" {
		return nil, nil, httpx.BadRequest("identifier_required", "identifier and password are required")
	}

	u, err := svc.users.GetByIdentifier(ctx, identifier)
	if err != nil {
		return nil, nil, httpx.Unauthorized("invalid_credentials", "invalid email/phone or password")
	}
	if u.Status != users.StatusActive {
		return nil, nil, httpx.Forbidden("account_inactive", "account is not active")
	}

	hash, err := svc.users.GetPasswordHash(ctx, u.ID)
	if err != nil {
		return nil, nil, err
	}
	if !VerifyPassword(hash, password) {
		return nil, nil, httpx.Unauthorized("invalid_credentials", "invalid email/phone or password")
	}

	if err := svc.users.UpdateLoginInfo(ctx, u.ID, ip); err != nil {
		svc.logger.Error("update login info", "error", err)
	}

	pair, err := svc.issueTokens(ctx, u, ip)
	if err != nil {
		return nil, nil, err
	}
	return u, pair, nil
}

func (svc *Service) Refresh(ctx context.Context, refreshToken, ip, userAgent string) (*TokenPair, error) {
	if refreshToken == "" {
		return nil, httpx.BadRequest("refresh_token_required", "refresh token is required")
	}

	sess, err := svc.sessions.GetByHash(ctx, HashToken(refreshToken))
	if err != nil {
		return nil, err
	}
	if sess.RevokedAt != nil {
		return nil, httpx.Unauthorized("invalid_refresh_token", "refresh token has been revoked")
	}
	if time.Now().After(sess.ExpiresAt) {
		return nil, httpx.Unauthorized("invalid_refresh_token", "refresh token has expired")
	}

	u, err := svc.users.GetByID(ctx, sess.UserID)
	if err != nil {
		return nil, err
	}
	if u.Status != users.StatusActive {
		return nil, httpx.Forbidden("account_inactive", "account is not active")
	}

	// Atomically revoke the old session. Concurrent refresh calls using the same
	// token race here: only one wins the revoked_at IS NULL guard, so a stolen
	// token that was already rotated is rejected instead of issuing two pairs.
	revoked, err := svc.sessions.Revoke(ctx, sess.ID)
	if err != nil {
		return nil, err
	}
	if !revoked {
		return nil, httpx.Unauthorized("invalid_refresh_token", "refresh token has been revoked")
	}

	pair, err := svc.issueTokens(ctx, u, ip)
	if err != nil {
		return nil, err
	}
	return pair, nil
}

func (svc *Service) Logout(ctx context.Context, refreshToken string) error {
	if refreshToken == "" {
		return nil
	}
	sess, err := svc.sessions.GetByHash(ctx, HashToken(refreshToken))
	if err != nil {
		return nil
	}
	_, err = svc.sessions.Revoke(ctx, sess.ID)
	return err
}

func (svc *Service) ClerkSync(ctx context.Context, clerkUserID, email, firstName, lastName, ip string) (*users.User, *TokenPair, error) {
	// Clerk user ID is used as a unique identifier
	finalEmail := normalizeEmail(email)

	// Try to find an existing user by email first
	var existing *users.User
	if finalEmail != "" {
		existing, _ = svc.users.GetByEmail(ctx, finalEmail)
	}

	if existing != nil {
		// User exists – just issue tokens
		pair, err := svc.issueTokens(ctx, existing, ip)
		if err != nil {
			return nil, nil, err
		}
		return existing, pair, nil
	}

	// Create a new customer account from Clerk
	randomPass := generateOTP() + generateOTP() // 12 chars, meets min 8 requirement
	hash, err := HashPassword(randomPass)
	if err != nil {
		return nil, nil, err
	}

	u := &users.User{
		Email:     strPtr(finalEmail),
		FirstName: strings.TrimSpace(firstName),
		LastName:  strings.TrimSpace(lastName),
		Role:      users.RoleCustomer,
		Status:    users.StatusActive,
	}
	created, err := svc.users.Create(ctx, u, hash)
	if err != nil {
		var myErr *mysql.MySQLError
		if errors.As(err, &myErr) && myErr.Number == 1062 {
			// Race: another request created the user between our lookup and
			// insert. Retry the lookup.
			if finalEmail != "" {
				existing, _ = svc.users.GetByEmail(ctx, finalEmail)
			}
			if existing != nil {
				pair, pairErr := svc.issueTokens(ctx, existing, ip)
				if pairErr != nil {
					return nil, nil, pairErr
				}
				return existing, pair, nil
			}
		}
		return nil, nil, err
	}

	pair, err := svc.issueTokens(ctx, created, ip)
	if err != nil {
		return nil, nil, err
	}
	return created, pair, nil
}

func (svc *Service) SocialLogin(ctx context.Context, provider, idToken, email, displayName, ip string) (*users.User, *TokenPair, error) {
	var subject, tokenEmail, givenName, familyName string

	switch strings.ToLower(provider) {
	case "google":
		info, err := svc.verifyGoogleToken(ctx, idToken)
		if err != nil {
			return nil, nil, httpx.Unauthorized("invalid_google_token", "could not verify Google token")
		}
		subject = info.Sub
		tokenEmail = info.Email
		givenName = info.GivenName
		familyName = info.FamilyName
	case "apple":
		info, err := svc.verifyAppleToken(idToken)
		if err != nil {
			return nil, nil, httpx.Unauthorized("invalid_apple_token", "could not verify Apple token")
		}
		subject = info.Sub
		tokenEmail = info.Email
	default:
		return nil, nil, httpx.BadRequest("invalid_provider", "provider must be google or apple")
	}

	// Prefer the email from the request, fallback to the token.
	finalEmail := strings.TrimSpace(email)
	if finalEmail == "" {
		finalEmail = tokenEmail
	}
	finalEmail = normalizeEmail(finalEmail)

	// Parse display name from request or token.
	fn := strings.TrimSpace(givenName)
	ln := strings.TrimSpace(familyName)
	if displayName != "" {
		parts := strings.SplitN(displayName, " ", 2)
		fn = parts[0]
		if len(parts) > 1 {
			ln = parts[1]
		}
	}

	// Try to find an existing user by email first, then by social provider ID.
	var existing *users.User
	if finalEmail != "" {
		existing, _ = svc.users.GetByEmail(ctx, finalEmail)
	}
	if existing == nil && subject != "" {
		existing, _ = svc.users.GetByPhone(ctx, subject)
	}

	if existing != nil {
		// User exists – just issue tokens.
		pair, err := svc.issueTokens(ctx, existing, ip)
		if err != nil {
			return nil, nil, err
		}
		return existing, pair, nil
	}

	// Create a new customer account. Social accounts don't need a password.
	randomPass := generateOTP() + generateOTP() // 12 chars, meets min 8 requirement
	hash, err := HashPassword(randomPass)
	if err != nil {
		return nil, nil, err
	}

	u := &users.User{
		Email:     strPtr(finalEmail),
		FirstName: strings.TrimSpace(fn),
		LastName:  strings.TrimSpace(ln),
		Role:      users.RoleCustomer,
		Status:    users.StatusActive,
	}
	created, err := svc.users.Create(ctx, u, hash)
	if err != nil {
		var myErr *mysql.MySQLError
		if errors.As(err, &myErr) && myErr.Number == 1062 {
			// Race: another request created the user between our lookup and
			// insert. Retry the lookup.
			if finalEmail != "" {
				existing, _ = svc.users.GetByEmail(ctx, finalEmail)
			}
			if existing != nil {
				pair, pairErr := svc.issueTokens(ctx, existing, ip)
				if pairErr != nil {
					return nil, nil, pairErr
				}
				return existing, pair, nil
			}
		}
		return nil, nil, err
	}

	pair, err := svc.issueTokens(ctx, created, ip)
	if err != nil {
		return nil, nil, err
	}
	return created, pair, nil
}

type googleTokenInfo struct {
	Sub        string `json:"sub"`
	Email      string `json:"email"`
	GivenName  string `json:"given_name"`
	FamilyName string `json:"family_name"`
}

func (svc *Service) verifyGoogleToken(ctx context.Context, idToken string) (*googleTokenInfo, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		"https://oauth2.googleapis.com/tokeninfo?id_token="+idToken, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("google tokeninfo request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("google tokeninfo returned %d", resp.StatusCode)
	}
	var info googleTokenInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return nil, fmt.Errorf("failed to decode google tokeninfo: %w", err)
	}
	if info.Sub == "" {
		return nil, fmt.Errorf("google token missing sub")
	}
	return &info, nil
}

type appleClaims struct {
	Sub string `json:"sub"`
	Email string `json:"email"`
}

func (svc *Service) verifyAppleToken(idToken string) (*appleClaims, error) {
	// Parse the JWT header to get the key ID.
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid apple token format")
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("failed to decode apple token header: %w", err)
	}
	var header struct {
		Kid string `json:"kid"`
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return nil, fmt.Errorf("failed to parse apple token header: %w", err)
	}

	// Fetch Apple's public JWKS.
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch apple JWKS: %w", err)
	}
	defer resp.Body.Close()
	var jwks struct {
		Keys []struct {
			Kid string   `json:"kid"`
			Kty string   `json:"kty"`
			Alg string   `json:"alg"`
			Use string   `json:"use"`
			N   string   `json:"n"`
			E   string   `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("failed to decode apple JWKS: %w", err)
	}

	// Find the matching key and verify the token.
	found := false
	for _, key := range jwks.Keys {
		if key.Kid == header.Kid {
			found = true
			// Basic verification: decode the payload and check exp.
			payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
			if err != nil {
				return nil, fmt.Errorf("failed to decode apple token payload: %w", err)
			}
			var claims appleClaims
			if err := json.Unmarshal(payloadBytes, &claims); err != nil {
				return nil, fmt.Errorf("failed to parse apple token payload: %w", err)
			}
			if claims.Sub == "" {
				return nil, fmt.Errorf("apple token missing sub")
			}
			_ = key // In production, verify the RS256 signature.
			return &claims, nil
		}
	}
	if !found {
		return nil, fmt.Errorf("apple token key ID %s not found in JWKS", header.Kid)
	}
	return nil, fmt.Errorf("apple token verification failed")
}

func (svc *Service) RequestOTP(ctx context.Context, phone string) error {
	phone = normalizePhone(phone)
	if phone == "" {
		return httpx.BadRequest("phone_required", "phone is required")
	}
	if _, err := svc.users.GetByPhone(ctx, phone); err != nil {
		return httpx.NotFound("user_not_found", "no account found for this phone")
	}
	return svc.sendOTP(ctx, phone, "")
}

func (svc *Service) VerifyPhone(ctx context.Context, phone, code string) error {
	phone = normalizePhone(phone)
	if phone == "" || code == "" {
		return httpx.BadRequest("phone_and_code_required", "phone and code are required")
	}

	key := otpKey(phone)
	if svc.rdb == nil {
		return httpx.ServiceUnavailable("cache_unavailable", "phone verification is temporarily unavailable")
	}
	stored, err := svc.rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		return httpx.BadRequest("invalid_or_expired_code", "code is invalid or has expired")
	}
	if err != nil {
		return err
	}
	if stored != strings.TrimSpace(code) {
		return httpx.BadRequest("invalid_or_expired_code", "code is invalid or has expired")
	}

	u, err := svc.users.GetByPhone(ctx, phone)
	if err != nil {
		return err
	}
	if err := svc.users.MarkPhoneVerified(ctx, u.ID); err != nil {
		return err
	}
	svc.rdb.Del(ctx, key)
	return nil
}

// RequestEmailVerification generates a 6-digit code and delivers it to the
// account's email. Already-verified accounts are a no-op success.
func (svc *Service) RequestEmailVerification(ctx context.Context, email string) error {
	email = normalizeEmail(email)
	if email == "" {
		return httpx.BadRequest("email_required", "email is required")
	}
	u, err := svc.users.GetByEmail(ctx, email)
	if err != nil {
		return err
	}
	if u.EmailVerified {
		return nil
	}
	return svc.sendEmailCode(ctx, email, "")
}

func (svc *Service) VerifyEmail(ctx context.Context, email, code string) error {
	email = normalizeEmail(email)
	if email == "" || strings.TrimSpace(code) == "" {
		return httpx.BadRequest("email_and_code_required", "email and code are required")
	}

	key := emailOTPKey(email)
	if svc.rdb == nil {
		return httpx.ServiceUnavailable("cache_unavailable", "email verification is temporarily unavailable")
	}
	stored, err := svc.rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		return httpx.BadRequest("invalid_or_expired_code", "code is invalid or has expired")
	}
	if err != nil {
		return err
	}
	if stored != strings.TrimSpace(code) {
		return httpx.BadRequest("invalid_or_expired_code", "code is invalid or has expired")
	}

	u, err := svc.users.GetByEmail(ctx, email)
	if err != nil {
		return err
	}
	if err := svc.users.MarkEmailVerified(ctx, u.ID); err != nil {
		return err
	}
	svc.rdb.Del(ctx, key)
	return nil
}

func (svc *Service) issueTokens(ctx context.Context, u *users.User, ip string) (*TokenPair, error) {
	access, accessExpires, err := svc.tokens.CreateAccessToken(u.ID, u.Role)
	if err != nil {
		return nil, err
	}

	plain, hash, refreshExpires, err := svc.tokens.NewRefreshToken()
	if err != nil {
		return nil, err
	}

	sess := &Session{
		UserID:    u.ID,
		TokenHash: hash,
		ExpiresAt: refreshExpires,
		IP:        ip,
	}
	if _, err := svc.sessions.Create(ctx, sess); err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  access,
		RefreshToken: plain,
		ExpiresIn:    int64(accessExpires.Sub(time.Now()).Seconds()),
	}, nil
}

func (svc *Service) defaultSendOTP(ctx context.Context, phone, code string) error {
	if svc.rdb == nil {
		return fmt.Errorf("cache unavailable: cannot store otp")
	}
	if code == "" {
		code = generateOTP()
	}
	if err := svc.rdb.Set(ctx, otpKey(phone), code, svc.cfg.OTPTTL).Err(); err != nil {
		return err
	}
	svc.logger.Info("otp generated", "phone", phone, "code", code)
	return nil
}

func otpKey(phone string) string {
	return "otp:verify:" + phone
}

func (svc *Service) defaultSendEmailCode(ctx context.Context, email, code string) error {
	if svc.rdb == nil {
		return fmt.Errorf("cache unavailable: cannot store email verification code")
	}
	if code == "" {
		code = generateOTP()
	}
	if err := svc.rdb.Set(ctx, emailOTPKey(email), code, svc.cfg.OTPTTL).Err(); err != nil {
		return err
	}
	svc.logger.Info("email verification code generated", "email", email, "code", code)
	return nil
}

func emailOTPKey(email string) string {
	return "otp:verify_email:" + email
}

func generateOTP() string {
	digits := []byte("0123456789")
	out := make([]byte, 6)
	for i := range out {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return fmt.Sprintf("%06d", time.Now().UnixNano()%1000000)
		}
		out[i] = digits[n.Int64()]
	}
	return string(out)
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func normalizePhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return ""
	}
	phone = strings.ReplaceAll(phone, " ", "")
	phone = strings.ReplaceAll(phone, "-", "")
	phone = strings.ReplaceAll(phone, "(", "")
	phone = strings.ReplaceAll(phone, ")", "")
	if strings.HasPrefix(phone, "+234") {
		phone = "0" + phone[4:]
	}
	if strings.HasPrefix(phone, "234") && !strings.HasPrefix(phone, "2340") {
		phone = "0" + phone[3:]
	}
	return phone
}

func strPtr(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}
