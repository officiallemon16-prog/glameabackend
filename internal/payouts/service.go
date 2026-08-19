package payouts

import (
	"context"
	"time"

	"github.com/glamea/glamea-backend/internal/payments"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Service struct {
	store    *Store
	proStore *professionals.Store
	ledger   *payments.Store
	cfg      *config.Config
}

func NewService(store *Store, proStore *professionals.Store, ledger *payments.Store, cfg *config.Config) *Service {
	return &Service{store: store, proStore: proStore, ledger: ledger, cfg: cfg}
}

func (s *Service) requirePro(ctx context.Context, userID string) (*professionals.Professional, error) {
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return pro, nil
}

type AddAccountInput struct {
	BankName      string
	BankCode      string
	AccountNumber string
	AccountName   string
	IsDefault     bool
}

func (s *Service) AddAccount(ctx context.Context, userID string, in AddAccountInput) (*PayoutAccount, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	if in.BankName == "" || in.AccountNumber == "" || in.AccountName == "" {
		return nil, httpx.BadRequest("invalid_account", "bank_name, account_number and account_name are required")
	}
	return s.store.AddAccount(ctx, PayoutAccount{
		ProfessionalID: pro.ID,
		BankName:       in.BankName,
		BankCode:       in.BankCode,
		AccountNumber:  in.AccountNumber,
		AccountName:    in.AccountName,
		IsDefault:      in.IsDefault,
	})
}

func (s *Service) ListAccounts(ctx context.Context, userID string) ([]*PayoutAccount, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.store.ListAccounts(ctx, pro.ID)
}

func (s *Service) SetDefault(ctx context.Context, userID, accountID string) error {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return err
	}
	return s.store.SetDefault(ctx, pro.ID, accountID)
}

func (s *Service) DeleteAccount(ctx context.Context, userID, accountID string) error {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return err
	}
	return s.store.DeleteAccount(ctx, pro.ID, accountID)
}

type RequestPayoutInput struct {
	Amount    float64
	AccountID string
	Note      string
}

func (s *Service) RequestPayout(ctx context.Context, userID string, in RequestPayoutInput) (*Payout, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	if in.Amount <= 0 {
		return nil, httpx.BadRequest("invalid_amount", "amount must be positive")
	}
	currency := s.cfg.DefaultCurrency
	available, err := s.AvailableBalance(ctx, userID)
	if err != nil {
		return nil, err
	}
	if available < in.Amount {
		return nil, httpx.Conflict("insufficient_available_balance",
			"only funds outside the payout holding period are available for withdrawal")
	}

	var accountID *string
	if in.AccountID != "" {
		acct, err := s.store.GetAccount(ctx, in.AccountID)
		if err != nil {
			return nil, err
		}
		if acct.ProfessionalID != pro.ID {
			return nil, httpx.Forbidden("not_your_account", "this payout account belongs to another professional")
		}
		accountID = &acct.ID
	}

	ref := "payout_" + uuid.NewString()
	if _, err := s.ledger.Debit(ctx, pro.UserID, payments.CatPayout, in.Amount, currency, ref, nil, nil); err != nil {
		return nil, err
	}
	return s.store.Create(ctx, Payout{
		ProfessionalID:  pro.ID,
		PayoutAccountID: accountID,
		Amount:          in.Amount,
		Currency:        currency,
		Note:            in.Note,
	})
}

func (s *Service) ListMine(ctx context.Context, userID string, limit, offset int) ([]*Payout, int64, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	return s.store.ListForProfessional(ctx, pro.ID, limit, offset)
}

func (s *Service) ListAll(ctx context.Context, status string, limit, offset int) ([]*Payout, int64, error) {
	return s.store.ListAll(ctx, status, limit, offset)
}

func (s *Service) Pay(ctx context.Context, payoutID string) (*Payout, error) {
	if err := s.store.MarkPaid(ctx, payoutID); err != nil {
		return nil, err
	}
	return s.store.GetByID(ctx, payoutID)
}

// AvailableBalance returns funds not inside the payout holding period.
// Recent earnings are held; earlier earnings and non-earning credits are withdrawable.
func (s *Service) AvailableBalance(ctx context.Context, userID string) (float64, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return 0, err
	}
	wallet, err := s.ledger.GetWallet(ctx, pro.UserID, s.cfg.DefaultCurrency)
	if err != nil {
		return 0, err
	}
	holdUntil := time.Now().UTC().Add(-s.cfg.PayoutHoldingPeriod)
	pending, err := s.ledger.PendingEarnings(ctx, pro.UserID, s.cfg.DefaultCurrency, holdUntil)
	if err != nil {
		return 0, err
	}
	available := wallet.Balance - pending
	if available < 0 {
		available = 0
	}
	return available, nil
}

// PendingBalance returns the portion of the wallet inside the holding period.
func (s *Service) PendingBalance(ctx context.Context, userID string) (float64, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return 0, err
	}
	holdUntil := time.Now().UTC().Add(-s.cfg.PayoutHoldingPeriod)
	return s.ledger.PendingEarnings(ctx, pro.UserID, s.cfg.DefaultCurrency, holdUntil)
}

// EarningsSummary is the pro-facing earnings snapshot shown on the dashboard:
// lifetime earnings, withdrawable/held balances and this-week/this-month totals.
type EarningsSummary struct {
	Currency      string  `json:"currency"`
	TotalEarned   float64 `json:"total_earned"`
	Available     float64 `json:"available"`
	Pending       float64 `json:"pending"`
	WalletBalance float64 `json:"wallet_balance"`
	ThisWeek      float64 `json:"this_week"`
	ThisMonth     float64 `json:"this_month"`
}

func (s *Service) EarningsSummary(ctx context.Context, userID string) (*EarningsSummary, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	currency := s.cfg.DefaultCurrency
	wallet, err := s.ledger.GetWallet(ctx, pro.UserID, currency)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	holdUntil := now.Add(-s.cfg.PayoutHoldingPeriod)
	weekStart := startOfWeek(now)
	monthStart := startOfMonth(now)

	pending, err := s.ledger.PendingEarnings(ctx, pro.UserID, currency, holdUntil)
	if err != nil {
		return nil, err
	}
	totalEarned, err := s.ledger.SumEarnings(ctx, pro.UserID, currency, time.Time{})
	if err != nil {
		return nil, err
	}
	thisWeek, err := s.ledger.SumEarnings(ctx, pro.UserID, currency, weekStart)
	if err != nil {
		return nil, err
	}
	thisMonth, err := s.ledger.SumEarnings(ctx, pro.UserID, currency, monthStart)
	if err != nil {
		return nil, err
	}

	available := wallet.Balance - pending
	if available < 0 {
		available = 0
	}
	return &EarningsSummary{
		Currency:      currency,
		TotalEarned:   totalEarned,
		Available:     available,
		Pending:       pending,
		WalletBalance: wallet.Balance,
		ThisWeek:      thisWeek,
		ThisMonth:     thisMonth,
	}, nil
}

// startOfWeek returns the UTC instant at the start of the ISO week (Monday).
func startOfWeek(t time.Time) time.Time {
	utc := t.UTC()
	daysSinceMonday := (int(utc.Weekday()) + 6) % 7
	return time.Date(utc.Year(), utc.Month(), utc.Day()-daysSinceMonday, 0, 0, 0, 0, time.UTC)
}

// startOfMonth returns the UTC instant at the start of the month.
func startOfMonth(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), 1, 0, 0, 0, 0, time.UTC)
}
