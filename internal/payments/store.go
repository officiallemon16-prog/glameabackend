package payments

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	IntentDeposit = "DEPOSIT"
	IntentBalance = "BALANCE"
	IntentFull    = "FULL"

	IntentPending  = "PENDING"
	IntentSucceed  = "SUCCEEDED"
	IntentFailed   = "FAILED"
	IntentRefunded = "REFUNDED"
	IntentCancel   = "CANCELLED"

	CatDeposit     = "DEPOSIT"
	CatBalance     = "BALANCE_PAYMENT"
	CatFull        = "FULL_PAYMENT"
	CatRefund      = "REFUND"
	CatEarning     = "EARNING"
	CatPlatformFee = "PLATFORM_FEE"
	CatPayout      = "PAYOUT"
	CatAdjustment  = "ADJUSTMENT"

	TypeDebit  = "DEBIT"
	TypeCredit = "CREDIT"
)

// PlatformUserID is a virtual account holder used to accrue platform fees.
const PlatformUserID = "00000000-0000-0000-0000-000000000000"

type Wallet struct {
	UserID   string    `json:"user_id"`
	Currency string    `json:"currency"`
	Balance  float64   `json:"balance"`
	Updated  time.Time `json:"updated_at"`
}

type LedgerEntry struct {
	ID              string    `json:"id"`
	UserID          string    `json:"user_id"`
	BookingID       *string   `json:"booking_id,omitempty"`
	PaymentIntentID *string   `json:"payment_intent_id,omitempty"`
	Type            string    `json:"type"`
	Category        string    `json:"category"`
	Amount          float64   `json:"amount"`
	BalanceAfter    float64   `json:"balance_after"`
	Currency        string    `json:"currency"`
	Reference       string    `json:"reference"`
	CreatedAt       time.Time `json:"created_at"`
}

type PaymentIntent struct {
	ID               string    `json:"id"`
	BookingID        string    `json:"booking_id"`
	CustomerID       string    `json:"customer_id"`
	AmountType       string    `json:"amount_type"`
	Amount           float64   `json:"amount"`
	Currency         string    `json:"currency"`
	Status           string    `json:"status"`
	Gateway          *string   `json:"gateway,omitempty"`
	GatewayReference *string   `json:"gateway_reference,omitempty"`
	AuthorizationURL *string   `json:"authorization_url,omitempty"`
	ProviderCharge   float64   `json:"provider_charge"`
	PlatformFee      float64   `json:"platform_fee"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) GetWallet(ctx context.Context, userID, currency string) (*Wallet, error) {
	row := s.db.QueryRowContext(ctx, `SELECT user_id, currency, balance, updated_at
		FROM wallets WHERE user_id = ? AND currency = ?`, userID, currency)
	var w Wallet
	if err := row.Scan(&w.UserID, &w.Currency, &w.Balance, &w.Updated); err != nil {
		if err == sql.ErrNoRows {
			return &Wallet{UserID: userID, Currency: currency, Balance: 0}, nil
		}
		return nil, err
	}
	return &w, nil
}

// applyLedger atomically upserts the wallet and writes a ledger entry. It returns the new balance.
func (s *Store) applyLedger(ctx context.Context, userID, txType, category string, amount float64, currency, reference string, bookingID, intentID *string) (float64, error) {
	if userID == "" {
		return 0, httpx.BadRequest("invalid_user", "user is required")
	}
	if amount <= 0 {
		return 0, httpx.BadRequest("invalid_amount", "amount must be positive")
	}
	if currency == "" {
		currency = "NGN"
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var balance float64
	err = tx.QueryRowContext(ctx, `SELECT balance FROM wallets WHERE user_id = ? AND currency = ? FOR UPDATE`,
		userID, currency).Scan(&balance)
	if err == sql.ErrNoRows {
		if txType == TypeDebit {
			return 0, httpx.Conflict("insufficient_balance", "insufficient balance")
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO wallets (id, user_id, currency, balance) VALUES (?, ?, ?, 0)`,
			uuid.NewString(), userID, currency); err != nil {
			return 0, err
		}
		balance = 0
	} else if err != nil {
		return 0, err
	}

	if txType == TypeDebit && balance < amount {
		return 0, httpx.Conflict("insufficient_balance", "insufficient balance")
	}

	var newBalance float64
	if txType == TypeCredit {
		newBalance = balance + amount
	} else {
		newBalance = balance - amount
	}
	if _, err := tx.ExecContext(ctx, `UPDATE wallets SET balance = ? WHERE user_id = ? AND currency = ?`,
		newBalance, userID, currency); err != nil {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO wallet_transactions
		(id, user_id, booking_id, payment_intent_id, type, category, amount, balance_after, currency, reference)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), userID, nullable(bookingID), nullable(intentID), txType, category, amount,
		newBalance, currency, reference); err != nil {
		return 0, err
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return newBalance, nil
}

func (s *Store) Debit(ctx context.Context, userID, category string, amount float64, currency, reference string, bookingID, intentID *string) (float64, error) {
	return s.applyLedger(ctx, userID, TypeDebit, category, amount, currency, reference, bookingID, intentID)
}

func (s *Store) Credit(ctx context.Context, userID, category string, amount float64, currency, reference string, bookingID, intentID *string) (float64, error) {
	return s.applyLedger(ctx, userID, TypeCredit, category, amount, currency, reference, bookingID, intentID)
}

func (s *Store) ListTransactions(ctx context.Context, userID string, limit, offset int) ([]*LedgerEntry, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE user_id = ?`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, user_id, booking_id, payment_intent_id, type, category, amount,
		balance_after, currency, reference, created_at
		FROM wallet_transactions WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*LedgerEntry{}
	for rows.Next() {
		e, err := scanLedger(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, e)
	}
	return out, total, rows.Err()
}

func (s *Store) TransactionExists(ctx context.Context, reference string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE reference = ?`, reference).Scan(&n)
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

// SumEarnings sums CREDIT EARNING entries created on or after `since`.
// A zero-value `since` covers the full history.
func (s *Store) SumEarnings(ctx context.Context, userID, currency string, since time.Time) (float64, error) {
	var sum float64
	err := s.db.QueryRowContext(ctx, `SELECT IFNULL(SUM(amount), 0) FROM wallet_transactions
		WHERE user_id = ? AND currency = ? AND type = 'CREDIT' AND category = ? AND created_at >= ?`,
		userID, currency, CatEarning, since).Scan(&sum)
	if err != nil {
		return 0, err
	}
	return sum, nil
}

// PendingEarnings returns the CREDIT EARNING sum inside the payout holding window.
func (s *Store) PendingEarnings(ctx context.Context, userID, currency string, since time.Time) (float64, error) {
	return s.SumEarnings(ctx, userID, currency, since)
}

// RecordEvent records a processed gateway webhook. It returns true when the event
// is new, and false when the gateway+event_id pair has already been seen.
func (s *Store) RecordEvent(ctx context.Context, gateway, eventID, reference string, payload []byte) (bool, error) {
	id := uuid.NewString()
	res, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO payment_events (id, gateway, event_id, reference, payload)
		VALUES (?, ?, ?, ?, ?)`, id, gateway, eventID, reference, string(payload))
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func scanLedger(row interface{ Scan(...any) error }) (*LedgerEntry, error) {
	var e LedgerEntry
	var bookingID, intentID sql.NullString
	err := row.Scan(&e.ID, &e.UserID, &bookingID, &intentID, &e.Type, &e.Category, &e.Amount,
		&e.BalanceAfter, &e.Currency, &e.Reference, &e.CreatedAt)
	if err != nil {
		return nil, err
	}
	if bookingID.Valid {
		e.BookingID = &bookingID.String
	}
	if intentID.Valid {
		e.PaymentIntentID = &intentID.String
	}
	return &e, nil
}

const intentCols = "id, booking_id, customer_id, amount_type, amount, currency, status, gateway, gateway_reference, authorization_url, provider_charge, platform_fee, created_at, updated_at"

func scanIntent(row interface{ Scan(...any) error }) (*PaymentIntent, error) {
	var p PaymentIntent
	var gateway, ref, authURL sql.NullString
	err := row.Scan(&p.ID, &p.BookingID, &p.CustomerID, &p.AmountType, &p.Amount, &p.Currency,
		&p.Status, &gateway, &ref, &authURL, &p.ProviderCharge, &p.PlatformFee, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if gateway.Valid {
		p.Gateway = &gateway.String
	}
	if ref.Valid {
		p.GatewayReference = &ref.String
	}
	if authURL.Valid {
		p.AuthorizationURL = &authURL.String
	}
	return &p, nil
}

func (s *Store) CreateIntent(ctx context.Context, in PaymentIntent) (*PaymentIntent, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO payment_intents
		(id, booking_id, customer_id, amount_type, amount, currency, status, gateway, gateway_reference, authorization_url, provider_charge, platform_fee)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)`,
		id, in.BookingID, in.CustomerID, in.AmountType, in.Amount, in.Currency, in.Status,
		nullableString(in.Gateway), nullableString(in.GatewayReference), nullableString(in.AuthorizationURL),
		in.ProviderCharge, in.PlatformFee)
	if err != nil {
		return nil, err
	}
	return s.GetIntent(ctx, id)
}

func (s *Store) GetIntent(ctx context.Context, id string) (*PaymentIntent, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+intentCols+` FROM payment_intents WHERE id = ?`, id)
	p, err := scanIntent(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("intent_not_found", "payment intent not found")
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) GetIntentForBooking(ctx context.Context, bookingID, amountType string) (*PaymentIntent, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+intentCols+` FROM payment_intents
		WHERE booking_id = ? AND amount_type = ?`, bookingID, amountType)
	p, err := scanIntent(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) GetIntentByReference(ctx context.Context, gateway, reference string) (*PaymentIntent, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+intentCols+` FROM payment_intents
		WHERE gateway = ? AND gateway_reference = ?`, gateway, reference)
	p, err := scanIntent(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("intent_not_found", "payment intent not found")
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) MarkIntentSucceeded(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE payment_intents SET status = ? WHERE id = ? AND status != ?`,
		IntentSucceed, id, IntentSucceed)
	return err
}

func (s *Store) MarkIntentFailed(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE payment_intents SET status = ? WHERE id = ?`,
		IntentFailed, id)
	return err
}

func nullable(v *string) any {
	if v == nil {
		return nil
	}
	return *v
}

func nullableString(v *string) any {
	if v == nil {
		return nil
	}
	return *v
}
