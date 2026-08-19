package payments

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/internal/bookings"
	"github.com/glamea/glamea-backend/internal/notifications"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Service struct {
	store        *Store
	bookingStore *bookings.Store
	userStore    *users.Store
	proStore     *professionals.Store
	notifier     *notifications.Service
	cfg          *config.Config
}

func NewService(store *Store, bookingStore *bookings.Store, userStore *users.Store, proStore *professionals.Store, notifier *notifications.Service, cfg *config.Config) *Service {
	return &Service{
		store:        store,
		bookingStore: bookingStore,
		userStore:    userStore,
		proStore:     proStore,
		notifier:     notifier,
		cfg:          cfg,
	}
}

type CreateIntentInput struct {
	BookingID  string
	AmountType string
}

func (s *Service) CreateIntent(ctx context.Context, customerID string, in CreateIntentInput) (*PaymentIntent, error) {
	if in.BookingID == "" {
		return nil, httpx.BadRequest("booking_required", "booking_id is required")
	}
	if in.AmountType == "" {
		in.AmountType = IntentDeposit
	}
	switch in.AmountType {
	case IntentDeposit, IntentBalance, IntentFull:
	default:
		return nil, httpx.BadRequest("invalid_amount_type", "amount_type must be DEPOSIT, BALANCE or FULL")
	}

	booking, err := s.bookingStore.GetByID(ctx, in.BookingID)
	if err != nil {
		return nil, err
	}
	if booking.CustomerID != customerID {
		return nil, httpx.Forbidden("not_your_booking", "you are not the customer for this booking")
	}

	amount := 0.0
	switch in.AmountType {
	case IntentDeposit:
		amount = booking.DepositAmount
	case IntentBalance:
		amount = booking.TotalAmount - booking.DepositAmount
		if amount < 0 {
			amount = 0
		}
	case IntentFull:
		amount = booking.TotalAmount
	}
	if amount <= 0 {
		return nil, httpx.Conflict("nothing_to_pay", "no outstanding amount for this booking")
	}

	existing, err := s.store.GetIntentForBooking(ctx, in.BookingID, in.AmountType)
	if err != nil {
		return nil, err
	}
	if existing != nil && existing.Status == IntentSucceed {
		return existing, nil
	}
	if existing != nil {
		if existing.Gateway != nil && *existing.Gateway == "mock" &&
			existing.Status != IntentSucceed && existing.Status != IntentRefunded && existing.Status != IntentCancel {
			if err := s.confirmPayment(ctx, existing); err != nil {
				return nil, err
			}
			return s.store.GetIntent(ctx, existing.ID)
		}
		return existing, nil
	}

	currency := booking.Currency
	if currency == "" {
		currency = s.cfg.DefaultCurrency
	}
	platformFee := roundMoney(amount * s.cfg.PlatformFeePercent / 100)

	intent := PaymentIntent{
		BookingID:   booking.ID,
		CustomerID:  customerID,
		AmountType:  in.AmountType,
		Amount:      amount,
		Currency:    currency,
		Status:      IntentPending,
		PlatformFee: platformFee,
	}

	// Live gateways are initialized server-side so the secret key never reaches
	// the client. Prefer SeerBit when configured, then Paystack, and fall back
	// to the mock gateway for local development without live credentials.
	email, err := s.customerEmail(ctx, customerID)
	if err != nil {
		return nil, err
	}
	fullName, err := s.customerFullName(ctx, customerID)
	if err != nil {
		return nil, err
	}

	switch {
	case s.cfg.SeerbitPublicKey != "" && s.cfg.SeerbitSecretKey != "":
		gateway := "seerbit"
		ref := "SEER_" + uuid.NewString()
		intent.Gateway = &gateway
		intent.GatewayReference = &ref

		authURL, err := s.initializeSeerbit(ctx, email, fullName, amount, currency, ref)
		if err != nil {
			return nil, err
		}
		intent.AuthorizationURL = &authURL

		created, err := s.store.CreateIntent(ctx, intent)
		if err != nil {
			return nil, err
		}
		return created, nil

	case s.cfg.PaystackSecretKey != "" && !isTestKey(s.cfg.PaystackSecretKey):
		gateway := "paystack"
		ref := "PS_" + uuid.NewString()
		intent.Gateway = &gateway
		intent.GatewayReference = &ref

		// Paystack requires the transaction to be initialized server-side so the
		// secret key never reaches the client. The returned authorization_url is
		// where the customer completes payment.
		authURL, err := s.initializePaystack(ctx, email, amount, currency, ref)
		if err != nil {
			return nil, err
		}
		intent.AuthorizationURL = &authURL

		created, err := s.store.CreateIntent(ctx, intent)
		if err != nil {
			return nil, err
		}
		return created, nil

	default:
		// Test keys or no gateway configured: simulate an immediate successful payment.
		gateway := "mock"
		if s.cfg.SeerbitPublicKey != "" {
			gateway = "seerbit_test"
		}
		ref := "MOCK_" + uuid.NewString()
		intent.Gateway = &gateway
		intent.GatewayReference = &ref
		created, err := s.store.CreateIntent(ctx, intent)
		if err != nil {
			return nil, err
		}
		// Simulate an immediate successful settlement for the test/mock gateway.
		// Skip wallet credit/debit for mock — just mark the intent SUCCEEDED.
		if err := s.store.MarkIntentSucceeded(ctx, created.ID); err != nil {
			return nil, err
		}
		return s.store.GetIntent(ctx, created.ID)
	}
}

func (s *Service) confirmPayment(ctx context.Context, intent *PaymentIntent) error {
	// Record the gateway receipt so the wallet has the funds to be debited.
	receiptRef := "receipt_" + intent.ID
	credited, err := s.store.TransactionExists(ctx, receiptRef)
	if err != nil {
		return err
	}
	if !credited {
		if _, err := s.store.Credit(ctx, intent.CustomerID, CatAdjustment, intent.Amount, intent.Currency,
			receiptRef, &intent.BookingID, &intent.ID); err != nil {
			return err
		}
	}

	ref := "ledger_" + intent.ID
	charged, err := s.store.TransactionExists(ctx, ref)
	if err != nil {
		return err
	}
	if !charged {
		_, ledgerErr := s.store.Debit(ctx, intent.CustomerID, categoryFor(intent.AmountType),
			intent.Amount, intent.Currency, ref, &intent.BookingID, &intent.ID)
		if ledgerErr != nil {
			if apiErr, ok := ledgerErr.(*httpx.APIError); ok && apiErr.Code == "insufficient_balance" {
				_ = s.store.MarkIntentFailed(ctx, intent.ID)
				return apiErr
			}
			return ledgerErr
		}
	}
	if err := s.store.MarkIntentSucceeded(ctx, intent.ID); err != nil {
		return err
	}
	_ = s.notifier.Notify(ctx, intent.CustomerID, "payment", "Payment successful",
		fmt.Sprintf("Your payment of %.2f %s for the booking was received.", intent.Amount, intent.Currency),
		map[string]any{"booking_id": intent.BookingID, "intent_id": intent.ID})
	return nil
}

func (s *Service) GetIntent(ctx context.Context, userID, id string) (*PaymentIntent, error) {
	p, err := s.store.GetIntent(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.CustomerID != userID {
		return nil, httpx.Forbidden("not_your_intent", "you do not have access to this payment intent")
	}
	// The customer completes SeerBit payments on its hosted checkout, then the
	// app returns and polls this endpoint. Reconcile a pending SeerBit intent
	// against the gateway's status API server-side so the result is definitive
	// even if the webhook is late or lost. Best effort: a provider hiccup must
	// not break the poll, the next poll simply retries.
	if p.Gateway != nil && *p.Gateway == "seerbit" && p.Status == IntentPending {
		if err := s.refreshSeerbitIntent(ctx, p); err == nil {
			if updated, getErr := s.store.GetIntent(ctx, id); getErr == nil {
				p = updated
			}
		}
	}
	// Legacy test SeerBit intents that are still PENDING should be auto-confirmed.
	if p.Gateway != nil && *p.Gateway == "seerbit_test" && p.Status == IntentPending {
		if err := s.store.MarkIntentSucceeded(ctx, p.ID); err == nil {
			if updated, getErr := s.store.GetIntent(ctx, id); getErr == nil {
				p = updated
			}
		}
	}
	return p, nil
}

// IntentForBooking returns the existing DEPOSIT intent for a booking the user owns,
// or nil when the deposit has not been created yet. Used by the client to show the
// deposit status without side effects.
func (s *Service) IntentForBooking(ctx context.Context, userID, bookingID string) (*PaymentIntent, error) {
	booking, err := s.bookingStore.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if booking.CustomerID != userID {
		return nil, httpx.Forbidden("not_your_booking", "you are not the customer for this booking")
	}
	return s.store.GetIntentForBooking(ctx, bookingID, IntentDeposit)
}

// customerEmail resolves the customer's email for the payment gateway. Phone-only
// accounts (email never registered) get a deterministic placeholder that keeps
// Paystack validation happy without blocking checkout.
func (s *Service) customerEmail(ctx context.Context, userID string) (string, error) {
	u, err := s.userStore.GetByID(ctx, userID)
	if err != nil {
		return "", err
	}
	if u.Email != nil && strings.TrimSpace(*u.Email) != "" {
		return *u.Email, nil
	}
	return "customer_" + userID + "@glamea.local", nil
}

// customerFullName resolves the customer's display name for the payment
// gateway. Phone-only accounts fall back to a generic name.
func (s *Service) customerFullName(ctx context.Context, userID string) (string, error) {
	u, err := s.userStore.GetByID(ctx, userID)
	if err != nil {
		return "", err
	}
	name := strings.TrimSpace(u.FirstName + " " + u.LastName)
	if name == "" {
		return "Glamea Customer", nil
	}
	return name, nil
}

// initializeSeerbit starts a SeerBit Standard Checkout and returns the hosted
// redirectLink where the customer completes payment.
func (s *Service) initializeSeerbit(ctx context.Context, email, fullName string, amount float64, currency, reference string) (string, error) {
	client := newSeerbitClient(s.cfg.SeerbitBaseURL, s.cfg.SeerbitPublicKey, s.cfg.SeerbitSecretKey)
	return client.initialize(ctx, seerbitInitializeInput{
		amount:      amount,
		currency:    currency,
		reference:   reference,
		email:       email,
		fullName:    fullName,
		callbackURL: strings.TrimRight(s.cfg.AppURL, "/") + "/api/v1/payments/callback",
	})
}

// initializePaystack calls Paystack /transaction/initialize and returns the
// checkout URL. The amount is converted to the minor unit (kobo) as required.
func (s *Service) initializePaystack(ctx context.Context, email string, amount float64, currency, reference string) (string, error) {
	payload, err := json.Marshal(map[string]any{
		"email":        email,
		"amount":       int(math.Round(amount * 100)),
		"reference":    reference,
		"currency":     currency,
		"callback_url": strings.TrimRight(s.cfg.AppURL, "/") + "/api/v1/payments/callback",
	})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimRight(s.cfg.PaystackBaseURL, "/")+"/transaction/initialize", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+s.cfg.PaystackSecretKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not reach the payment provider")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not read the payment provider response")
	}
	var out struct {
		Status  bool   `json:"status"`
		Message string `json:"message"`
		Data    struct {
			AuthorizationURL string `json:"authorization_url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "invalid payment provider response")
	}
	if resp.StatusCode != http.StatusOK || !out.Status || out.Data.AuthorizationURL == "" {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "payment provider could not initialize the payment")
	}
	return out.Data.AuthorizationURL, nil
}

func (s *Service) ConfirmByReference(ctx context.Context, gateway, reference string) (*PaymentIntent, error) {
	intent, err := s.store.GetIntentByReference(ctx, gateway, reference)
	if err != nil {
		return nil, err
	}
	if intent.Status != IntentPending {
		return intent, nil
	}
	if gateway == "seerbit" {
		// SeerBit webhooks are not signed, so trust is established by verifying
		// the transaction status against the gateway before crediting anything.
		if err := s.refreshSeerbitIntent(ctx, intent); err != nil {
			return nil, err
		}
		return s.store.GetIntent(ctx, intent.ID)
	}
	if err := s.confirmPayment(ctx, intent); err != nil {
		return nil, err
	}
	return s.store.GetIntent(ctx, intent.ID)
}

// refreshSeerbitIntent reconciles a pending SeerBit intent against the gateway
// status endpoint: it confirms the payment on success, marks it failed on an
// explicit decline, and leaves it pending otherwise.
func (s *Service) refreshSeerbitIntent(ctx context.Context, intent *PaymentIntent) error {
	if intent.GatewayReference == nil {
		return nil
	}
	client := newSeerbitClient(s.cfg.SeerbitBaseURL, s.cfg.SeerbitPublicKey, s.cfg.SeerbitSecretKey)
	succeeded, failed, _, err := client.verifyStatus(ctx, *intent.GatewayReference)
	if err != nil {
		return err
	}
	if succeeded {
		return s.confirmPayment(ctx, intent)
	}
	if failed {
		return s.store.MarkIntentFailed(ctx, intent.ID)
	}
	return nil
}

// VerifyWebhookSignature validates a gateway webhook signature against the raw
// request body. When no live secret is configured the mock gateway is active and
// verification is skipped so local development keeps working.
func (s *Service) VerifyWebhookSignature(gateway string, rawBody []byte, signature string) error {
	switch gateway {
	case "paystack":
		if s.cfg.PaystackSecretKey == "" {
			return nil
		}
		if signature == "" {
			return httpx.Unauthorized("missing_signature", "missing webhook signature")
		}
		mac := hmac.New(sha512.New, []byte(s.cfg.PaystackSecretKey))
		mac.Write(rawBody)
		expected := hex.EncodeToString(mac.Sum(nil))
		if subtle.ConstantTimeCompare([]byte(strings.ToLower(signature)), []byte(expected)) != 1 {
			return httpx.Unauthorized("invalid_signature", "webhook signature is invalid")
		}
		return nil
	case "flutterwave":
		if s.cfg.FlutterwaveSecretKey == "" {
			return nil
		}
		if signature == "" {
			return httpx.Unauthorized("missing_signature", "missing webhook signature")
		}
		// Flutterwave signs webhooks with the VERIF-HASH value configured in the
		// dashboard (their "secret hash"), which may differ from the API secret key.
		expected := s.cfg.FlutterwaveSecretHash
		if expected == "" {
			expected = s.cfg.FlutterwaveSecretKey
		}
		if !strings.EqualFold(signature, expected) {
			return httpx.Unauthorized("invalid_signature", "webhook signature is invalid")
		}
		return nil
	case "seerbit":
		// SeerBit does not sign webhooks. Authenticity is established by
		// reconciling the transaction against SeerBit's status endpoint
		// (see refreshSeerbitIntent) before any funds are credited.
		return nil
	default:
		return httpx.BadRequest("unknown_gateway", "unsupported payment gateway")
	}
}

// RecordWebhookEvent dedupes gateway callbacks. It returns false when the event
// has already been processed.
func (s *Service) RecordWebhookEvent(ctx context.Context, gateway, eventID, reference string, payload []byte) (bool, error) {
	if eventID == "" {
		eventID = "ref:" + reference
	}
	return s.store.RecordEvent(ctx, gateway, eventID, reference, payload)
}

// SettleBooking credits the professional's earnings (net of platform fee) when a booking completes.
func (s *Service) SettleBooking(ctx context.Context, booking *bookings.Booking) error {
	if booking.TotalAmount <= 0 {
		return nil
	}
	pro, err := s.proStore.GetByID(ctx, booking.ProfessionalID)
	if err != nil {
		return err
	}
	currency := booking.Currency
	if currency == "" {
		currency = s.cfg.DefaultCurrency
	}
	fee := roundMoney(booking.TotalAmount * s.cfg.PlatformFeePercent / 100)
	earnings := roundMoney(booking.TotalAmount - fee)

	if _, err := s.store.Credit(ctx, pro.UserID, CatEarning, earnings, currency,
		"earn_"+booking.ID, &booking.ID, nil); err != nil {
		return err
	}
	if _, err := s.store.Credit(ctx, PlatformUserID, CatPlatformFee, fee, currency,
		"fee_"+booking.ID, &booking.ID, nil); err != nil {
		return err
	}
	_ = s.notifier.Notify(ctx, pro.UserID, "earning", "Booking completed",
		fmt.Sprintf("You earned %.2f %s from a completed booking.", earnings, currency),
		map[string]any{"booking_id": booking.ID})
	return nil
}

func (s *Service) Balance(ctx context.Context, userID string) (*Wallet, error) {
	return s.store.GetWallet(ctx, userID, s.cfg.DefaultCurrency)
}

func (s *Service) Transactions(ctx context.Context, userID string, limit, offset int) ([]*LedgerEntry, int64, error) {
	return s.store.ListTransactions(ctx, userID, limit, offset)
}

func categoryFor(amountType string) string {
	switch amountType {
	case IntentDeposit:
		return CatDeposit
	case IntentBalance:
		return CatBalance
	default:
		return CatFull
	}
}

func roundMoney(v float64) float64 {
	return math.Round(v*100) / 100
}

// isTestKey returns true when a gateway key uses a test/sandbox prefix
// (e.g. "SBTEST...", "sk_test_..."). Test keys should trigger mock-like
// auto-confirmation instead of real gateway calls.
func isTestKey(key string) bool {
	k := strings.ToUpper(strings.TrimSpace(key))
	return strings.HasPrefix(k, "SBTEST") ||
		strings.HasPrefix(k, "SK_TEST") ||
		strings.HasPrefix(k, "TEST")
}
