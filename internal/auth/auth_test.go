package auth

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/glamea/glamea-backend/internal/users"
	"github.com/go-chi/chi/v5"
)

func TestPasswordHashAndVerify(t *testing.T) {
	hash, err := HashPassword("correct-horse-battery")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if hash == "" || hash == "correct-horse-battery" {
		t.Fatalf("hash should be a non-empty digest")
	}
	if !VerifyPassword(hash, "correct-horse-battery") {
		t.Fatalf("verify should pass for correct password")
	}
	if VerifyPassword(hash, "wrong-password") {
		t.Fatalf("verify should fail for wrong password")
	}
}

func TestAccessTokenRoundTrip(t *testing.T) {
	tm := NewTokenManager("test-secret", 15*time.Minute, 720*time.Hour)
	token, expires, err := tm.CreateAccessToken("user-123", "CUSTOMER")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if time.Until(expires) > 16*time.Minute {
		t.Fatalf("expiry should be ~15m, got %s", expires)
	}

	claims, err := tm.ParseAccessToken(token)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if claims.Subject != "user-123" {
		t.Fatalf("subject = %s, want user-123", claims.Subject)
	}
	if claims.Role != "CUSTOMER" {
		t.Fatalf("role = %s, want CUSTOMER", claims.Role)
	}
	if claims.Type != "access" {
		t.Fatalf("type = %s, want access", claims.Type)
	}
}

func TestAccessTokenRejectsTampering(t *testing.T) {
	tm := NewTokenManager("test-secret", time.Minute, time.Hour)
	token, _, err := tm.CreateAccessToken("user-123", "CUSTOMER")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	tampered := token[:len(token)-3] + "xyz"
	if _, err := tm.ParseAccessToken(tampered); err == nil {
		t.Fatalf("tampered token should be rejected")
	}
}

func TestAccessTokenRejectsWrongSecret(t *testing.T) {
	issuer := NewTokenManager("secret-a", time.Minute, time.Hour)
	verifier := NewTokenManager("secret-b", time.Minute, time.Hour)
	token, _, err := issuer.CreateAccessToken("user-123", "CUSTOMER")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := verifier.ParseAccessToken(token); err == nil {
		t.Fatalf("token signed with different secret should be rejected")
	}
}

func TestAccessTokenExpiry(t *testing.T) {
	tm := NewTokenManager("test-secret", -time.Minute, time.Hour)
	token, _, err := tm.CreateAccessToken("user-123", "CUSTOMER")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := tm.ParseAccessToken(token); err == nil {
		t.Fatalf("expired token should be rejected")
	}
}

func TestRefreshTokenHashing(t *testing.T) {
	plain, hash, expires, err := NewTokenManager("test-secret", time.Minute, time.Hour).NewRefreshToken()
	if err != nil {
		t.Fatalf("create refresh: %v", err)
	}
	if len(plain) < 32 {
		t.Fatalf("refresh token should be high entropy")
	}
	if hash == plain {
		t.Fatalf("hash must not equal plaintext")
	}
	if HashToken(plain) != hash {
		t.Fatalf("hash should be deterministic")
	}
	if time.Until(expires) > 61*time.Minute {
		t.Fatalf("refresh expiry should be ~1h, got %s", expires)
	}
}

func TestNormalizePhone(t *testing.T) {
	cases := map[string]string{
		"08012345678":     "08012345678",
		"+2348012345678":  "08012345678",
		"234 8012 345678": "08012345678",
		"(080) 123-45678": "08012345678",
		"":                "",
	}
	for in, want := range cases {
		if got := normalizePhone(in); got != want {
			t.Errorf("normalizePhone(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestNormalizeEmail(t *testing.T) {
	cases := map[string]string{
		"  A@B.Com ": "a@b.com",
		"a@b.com":    "a@b.com",
		"":           "",
	}
	for in, want := range cases {
		if got := normalizeEmail(in); got != want {
			t.Errorf("normalizeEmail(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEmailVerificationRoutesRegistered(t *testing.T) {
	svc := NewService(nil, nil, nil, nil, nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	h := NewHandler(svc, 20)
	r := chi.NewRouter()
	h.RegisterRoutes(r)

	// Empty payloads short-circuit to 400 before any store access.
	for _, tc := range []struct{ name, path string }{
		{"send-email-code", "/api/v1/auth/send-email-code"},
		{"verify-email", "/api/v1/auth/verify-email"},
	} {
		req := httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(`{}`))
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: got status %d, want 400", tc.name, rec.Code)
		}
	}
}

func TestEmailVerificationSenderIsUsed(t *testing.T) {
	email := "alice@example.com"
	store := &fakeUserStore{
		getByEmail: func(_ context.Context, _ string) (*users.User, error) {
			return &users.User{ID: "u-1", Email: &email, Role: users.RoleCustomer, Status: users.StatusActive}, nil
		},
	}
	var sentTo string
	svc := NewService(nil, nil, nil, nil, nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	svc.users = store
	svc.SetEmailSender(func(_ context.Context, email, _ string) error {
		sentTo = email
		return nil
	})

	if err := svc.RequestEmailVerification(context.Background(), "Alice@Example.com"); err != nil {
		t.Fatalf("request: %v", err)
	}
	if sentTo != "alice@example.com" {
		t.Errorf("sender called with %q, want normalized alice@example.com", sentTo)
	}
}

func TestEmailVerificationAlreadyVerifiedIsNoop(t *testing.T) {
	email := "alice@example.com"
	store := &fakeUserStore{
		getByEmail: func(_ context.Context, _ string) (*users.User, error) {
			return &users.User{ID: "u-1", Email: &email, EmailVerified: true, Role: users.RoleCustomer, Status: users.StatusActive}, nil
		},
	}
	called := false
	svc := NewService(nil, nil, nil, nil, nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
	svc.users = store
	svc.SetEmailSender(func(_ context.Context, _, _ string) error {
		called = true
		return nil
	})

	if err := svc.RequestEmailVerification(context.Background(), email); err != nil {
		t.Fatalf("request: %v", err)
	}
	if called {
		t.Error("sender should not be called for an already-verified email")
	}
}

type fakeUserStore struct {
	*users.Store
	getByEmail        func(ctx context.Context, email string) (*users.User, error)
	markEmailVerified func(ctx context.Context, id string) error
}

func (f *fakeUserStore) GetByEmail(ctx context.Context, email string) (*users.User, error) {
	return f.getByEmail(ctx, email)
}

func (f *fakeUserStore) MarkEmailVerified(ctx context.Context, id string) error {
	return f.markEmailVerified(ctx, id)
}
