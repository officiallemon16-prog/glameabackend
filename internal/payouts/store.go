package payouts

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	StatusPending = "PENDING"
	StatusPaid    = "PAID"
	StatusFailed  = "FAILED"
	StatusCancel  = "CANCELLED"
)

type PayoutAccount struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id"`
	BankName       string    `json:"bank_name"`
	BankCode       string    `json:"bank_code,omitempty"`
	AccountNumber  string    `json:"account_number"`
	AccountName    string    `json:"account_name"`
	IsVerified     bool      `json:"is_verified"`
	IsDefault      bool      `json:"is_default"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type Payout struct {
	ID               string     `json:"id"`
	ProfessionalID   string     `json:"professional_id"`
	PayoutAccountID  *string    `json:"payout_account_id,omitempty"`
	Amount           float64    `json:"amount"`
	Currency         string     `json:"currency"`
	Status           string     `json:"status"`
	GatewayReference string     `json:"gateway_reference,omitempty"`
	Note             string     `json:"note,omitempty"`
	PaidAt           *time.Time `json:"paid_at,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`

	ProfessionalName string `json:"professional_name,omitempty"`
	AccountName      string `json:"account_name,omitempty"`
	BankName         string `json:"bank_name,omitempty"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const accountCols = "id, professional_id, bank_name, bank_code, account_number, account_name, is_verified, is_default, created_at, updated_at"

func scanAccount(row interface{ Scan(...any) error }) (*PayoutAccount, error) {
	var a PayoutAccount
	var bankCode sql.NullString
	err := row.Scan(&a.ID, &a.ProfessionalID, &a.BankName, &bankCode, &a.AccountNumber, &a.AccountName,
		&a.IsVerified, &a.IsDefault, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		return nil, err
	}
	a.BankCode = bankCode.String
	return &a, nil
}

func (s *Store) AddAccount(ctx context.Context, in PayoutAccount) (*PayoutAccount, error) {
	id := uuid.NewString()
	if in.IsDefault {
		_, _ = s.db.ExecContext(ctx, `UPDATE payout_accounts SET is_default = 0 WHERE professional_id = ?`, in.ProfessionalID)
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO payout_accounts
		(id, professional_id, bank_name, bank_code, account_number, account_name, is_verified, is_default)
		VALUES (?, ?, ?, ?, ?, ?, 0, ?)`,
		id, in.ProfessionalID, in.BankName, in.BankCode, in.AccountNumber, in.AccountName, in.IsDefault)
	if err != nil {
		return nil, err
	}
	return s.GetAccount(ctx, id)
}

func (s *Store) GetAccount(ctx context.Context, id string) (*PayoutAccount, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+accountCols+` FROM payout_accounts WHERE id = ?`, id)
	a, err := scanAccount(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("account_not_found", "payout account not found")
		}
		return nil, err
	}
	return a, nil
}

func (s *Store) ListAccounts(ctx context.Context, professionalID string) ([]*PayoutAccount, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+accountCols+` FROM payout_accounts
		WHERE professional_id = ? ORDER BY is_default DESC, created_at DESC`, professionalID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*PayoutAccount{}
	for rows.Next() {
		a, err := scanAccount(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (s *Store) SetDefault(ctx context.Context, professionalID, accountID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var owner string
	if err := tx.QueryRowContext(ctx, `SELECT professional_id FROM payout_accounts WHERE id = ?`, accountID).Scan(&owner); err != nil {
		if err == sql.ErrNoRows {
			return httpx.NotFound("account_not_found", "payout account not found")
		}
		return err
	}
	if owner != professionalID {
		return httpx.Forbidden("not_your_account", "this payout account belongs to another professional")
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payout_accounts SET is_default = 0 WHERE professional_id = ?`, professionalID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payout_accounts SET is_default = 1 WHERE id = ?`, accountID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) DeleteAccount(ctx context.Context, professionalID, accountID string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM payout_accounts WHERE id = ? AND professional_id = ?`, accountID, professionalID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("account_not_found", "payout account not found")
	}
	return nil
}

const payoutCols = `p.id, p.professional_id, p.payout_account_id, p.amount, p.currency, p.status,
	p.gateway_reference, p.note, p.paid_at, p.created_at, p.updated_at,
	pr.business_name, a.account_name, a.bank_name`

const payoutFrom = ` payouts p
	JOIN professionals pr ON pr.id = p.professional_id
	LEFT JOIN payout_accounts a ON a.id = p.payout_account_id`

func scanPayout(row interface{ Scan(...any) error }) (*Payout, error) {
	var p Payout
	var accountID, ref, note, proName, accName, bankName sql.NullString
	var paidAt sql.NullTime
	err := row.Scan(&p.ID, &p.ProfessionalID, &accountID, &p.Amount, &p.Currency, &p.Status,
		&ref, &note, &paidAt, &p.CreatedAt, &p.UpdatedAt,
		&proName, &accName, &bankName)
	if err != nil {
		return nil, err
	}
	if accountID.Valid {
		p.PayoutAccountID = &accountID.String
	}
	p.GatewayReference = ref.String
	p.Note = note.String
	if paidAt.Valid {
		p.PaidAt = &paidAt.Time
	}
	p.ProfessionalName = proName.String
	p.AccountName = accName.String
	p.BankName = bankName.String
	return &p, nil
}

func (s *Store) Create(ctx context.Context, in Payout) (*Payout, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO payouts
		(id, professional_id, payout_account_id, amount, currency, status, note)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, in.ProfessionalID, nullString(in.PayoutAccountID), in.Amount, in.Currency, StatusPending, in.Note)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Payout, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+payoutCols+` FROM`+payoutFrom+` WHERE p.id = ?`, id)
	p, err := scanPayout(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("payout_not_found", "payout not found")
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) ListForProfessional(ctx context.Context, professionalID string, limit, offset int) ([]*Payout, int64, error) {
	return s.list(ctx, " WHERE p.professional_id = ?", []any{professionalID}, limit, offset)
}

func (s *Store) ListAll(ctx context.Context, status string, limit, offset int) ([]*Payout, int64, error) {
	where := " WHERE 1=1"
	args := []any{}
	if status != "" {
		where += " AND p.status = ?"
		args = append(args, status)
	}
	return s.list(ctx, where, args, limit, offset)
}

func (s *Store) list(ctx context.Context, where string, args []any, limit, offset int) ([]*Payout, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payouts p`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	queryArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT `+payoutCols+` FROM`+payoutFrom+where+
		` ORDER BY p.created_at DESC LIMIT ? OFFSET ?`, queryArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Payout{}
	for rows.Next() {
		p, err := scanPayout(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}

func (s *Store) MarkPaid(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE payouts SET status = ?, paid_at = NOW()
		WHERE id = ? AND status = ?`, StatusPaid, id, StatusPending)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.Conflict("invalid_payout_status", "payout can no longer be paid")
	}
	return nil
}

func nullString(v *string) any {
	if v == nil {
		return nil
	}
	return *v
}
