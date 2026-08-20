package config

import (
	"fmt"
	"os"
	"time"

	"github.com/caarlos0/env/v11"
	"github.com/joho/godotenv"
)

type Config struct {
	Env  string `env:"APP_ENV" envDefault:"development"`
	Name string `env:"APP_NAME" envDefault:"glamea-backend"`

	HTTPAddr string `env:"HTTP_ADDR" envDefault:":8080"`

	DatabaseURL string `env:"DATABASE_URL" envDefault:"root:@tcp(127.0.0.1:4000)/glamea?parseTime=true&multiStatements=true"`
	RedisURL    string `env:"REDIS_URL" envDefault:"redis://localhost:6379/0"`

	JWTSecret           string        `env:"JWT_SECRET" envDefault:"dev-secret-change-me-in-prod"`
	AccessTokenTTL      time.Duration `env:"ACCESS_TOKEN_TTL" envDefault:"15m"`
	RefreshTokenTTL     time.Duration `env:"REFRESH_TOKEN_TTL" envDefault:"720h"`
	OTPTTL              time.Duration `env:"OTP_TTL" envDefault:"5m"`
	BookingSlotLockTTL  time.Duration `env:"BOOKING_SLOT_LOCK_TTL" envDefault:"10m"`
	IdempotencyKeyTTL   time.Duration `env:"IDEMPOTENCY_KEY_TTL" envDefault:"24h"`
	PayoutHoldingPeriod time.Duration `env:"PAYOUT_HOLDING_PERIOD" envDefault:"168h"`
	BookingBuffer       time.Duration `env:"BOOKING_BUFFER_MINUTES" envDefault:"15m"`
	TravelTime          time.Duration `env:"HOME_SERVICE_TRAVEL_MINUTES" envDefault:"30m"`
	CORSAllowedOrigins  []string      `env:"CORS_ALLOWED_ORIGINS" envDefault:"http://localhost:3000,http://localhost:8081"`
	MaxRequestBodyBytes int64         `env:"MAX_REQUEST_BODY_BYTES" envDefault:"10485760"`

	RateLimitPerMinute     int `env:"RATE_LIMIT_PER_MINUTE" envDefault:"600"`
	AuthRateLimitPerMinute int `env:"AUTH_RATE_LIMIT_PER_MINUTE" envDefault:"20"`
	WebhookRateLimitPerMin int `env:"WEBHOOK_RATE_LIMIT_PER_MINUTE" envDefault:"120"`

	JobInterval          time.Duration `env:"JOB_INTERVAL" envDefault:"1m"`
	ReminderBeforeStart  time.Duration `env:"REMINDER_BEFORE_START" envDefault:"2h"`
	ReviewReminderAfter  time.Duration `env:"REVIEW_REMINDER_AFTER" envDefault:"48h"`
	PendingBookingExpiry time.Duration `env:"PENDING_BOOKING_EXPIRY" envDefault:"24h"`

	// Re-engagement push nudges (frequency-capped via push_caps so we never spam).
	UnreadNudgeAfter          time.Duration `env:"UNREAD_NUDGE_AFTER" envDefault:"2h"`
	UnreadNudgeCooldown       time.Duration `env:"UNREAD_NUDGE_COOLDOWN" envDefault:"24h"`
	PendingExpiryNudgeBefore  time.Duration `env:"PENDING_EXPIRY_NUDGE_BEFORE" envDefault:"6h"`
	PendingExpiryNudgeCooldown time.Duration `env:"PENDING_EXPIRY_NUDGE_COOLDOWN" envDefault:"12h"`
	InactiveNudgeAfter        time.Duration `env:"INACTIVE_NUDGE_AFTER" envDefault:"168h"`
	InactiveNudgeCooldown     time.Duration `env:"INACTIVE_NUDGE_COOLDOWN" envDefault:"168h"`
	DigestInterval            time.Duration `env:"DIGEST_INTERVAL" envDefault:"168h"`
	DigestNewContentWindow    time.Duration `env:"DIGEST_NEW_CONTENT_WINDOW" envDefault:"168h"`

	CloudinaryCloudName    string `env:"CLOUDINARY_CLOUD_NAME"`
	CloudinaryAPIKey       string `env:"CLOUDINARY_API_KEY"`
	CloudinaryAPISecret    string `env:"CLOUDINARY_API_SECRET"`
	CloudinaryUploadFolder string `env:"CLOUDINARY_UPLOAD_FOLDER" envDefault:"glamea"`

	// Local file storage used when Cloudinary is not configured (dev fallback).
	LocalMediaDir string `env:"LOCAL_MEDIA_DIR" envDefault:"./uploads"`

	// Firebase Cloud Messaging. When the service-account file is blank, push
	// delivery is disabled (in-app notifications still work).
	FCMProjectID         string `env:"FCM_PROJECT_ID"`
	FCMServiceAccountFile string `env:"FCM_SERVICE_ACCOUNT_FILE"`

	PaystackSecretKey     string `env:"PAYSTACK_SECRET_KEY"`
	PaystackPublicKey     string `env:"PAYSTACK_PUBLIC_KEY"`
	PaystackBaseURL       string `env:"PAYSTACK_BASE_URL" envDefault:"https://api.paystack.co"`
	FlutterwaveSecretKey  string `env:"FLUTTERWAVE_SECRET_KEY"`
	FlutterwaveSecretHash string `env:"FLUTTERWAVE_SECRET_HASH"`
	FlutterwavePublicKey  string `env:"FLUTTERWAVE_PUBLIC_KEY"`
	FlutterwaveBaseURL    string `env:"FLUTTERWAVE_BASE_URL" envDefault:"https://api.flutterwave.com/v3"`

	SeerbitSecretKey string `env:"SEERBIT_SECRET_KEY"`
	SeerbitPublicKey string `env:"SEERBIT_PUBLIC_KEY"`
	SeerbitBaseURL   string `env:"SEERBIT_BASE_URL" envDefault:"https://seerbitapi.com/api/v2"`

	GoogleMapsAPIKey string `env:"GOOGLE_MAPS_API_KEY"`

	// Clerk authentication
	ClerkPublishableKey string `env:"CLERK_PUBLISHABLE_KEY"`
	ClerkSecretKey      string `env:"CLERK_SECRET_KEY"`
	ClerkAppID          string `env:"CLERK_APP_ID"`

	// Resend email API
	ResendAPIKey string `env:"RESEND_API_KEY"`
	EmailFrom    string `env:"EMAIL_FROM"`

	// WebRTC TURN relay for reliable voice/video calls behind NATs. When blank
	// clients fall back to STUN only (best-effort on symmetric NATs).
	TurnURL        string `env:"TURN_URL"`
	TurnUsername   string `env:"TURN_USERNAME"`
	TurnCredential string `env:"TURN_CREDENTIAL"`

	SentryDSN  string `env:"SENTRY_DSN"`
	PostHogKey string `env:"POSTHOG_API_KEY"`

	AppURL string `env:"APP_URL" envDefault:"http://localhost:8080"`

	PlatformFeePercent float64 `env:"PLATFORM_FEE_PERCENT" envDefault:"8.0"`
	DefaultCurrency    string  `env:"DEFAULT_CURRENCY" envDefault:"NGN"`
}

func Load() (*Config, error) {
	// Load .env if present; missing file is fine (env vars may be set directly).
	_ = godotenv.Load()

	// Render.com sets PORT instead of HTTP_ADDR. If HTTP_ADDR is not set
	// but PORT is, use it so the server binds to Render's assigned port.
	if os.Getenv("HTTP_ADDR") == "" {
		if port := os.Getenv("PORT"); port != "" {
			os.Setenv("HTTP_ADDR", ":"+port)
		}
	}

	cfg := &Config{}
	if err := env.Parse(cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET must be set")
	}
	if cfg.JWTSecret == "dev-secret-change-me-in-prod" && cfg.Env != "development" {
		return nil, fmt.Errorf("JWT_SECRET must be changed from the default in %s environment", cfg.Env)
	}
	if cfg.AppURL == "" || cfg.AppURL == "http://localhost:8080" {
		if cfg.Env == "production" {
			return nil, fmt.Errorf("APP_URL must be set to the public URL in production")
		}
	}
	return cfg, nil
}
