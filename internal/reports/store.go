package reports

import (
	"context"
	"database/sql"
	"time"
)

type BookingRow struct {
	ID           string    `json:"id"`
	Professional string    `json:"professional"`
	Customer     string    `json:"customer"`
	Service      string    `json:"service"`
	Status       string    `json:"status"`
	Total        float64   `json:"total_amount"`
	Currency     string    `json:"currency"`
	StartAt      time.Time `json:"start_at"`
	CreatedAt    time.Time `json:"created_at"`
}

type PaymentRow struct {
	ID         string    `json:"id"`
	BookingID  string    `json:"booking_id"`
	CustomerID string    `json:"customer_id"`
	Amount     float64   `json:"amount"`
	Currency   string    `json:"currency"`
	Status     string    `json:"status"`
	Gateway    *string   `json:"gateway,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type PayoutRow struct {
	ID             string     `json:"id"`
	ProfessionalID string     `json:"professional_id"`
	Amount         float64    `json:"amount"`
	Currency       string     `json:"currency"`
	Status         string     `json:"status"`
	PaidAt         *time.Time `json:"paid_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Bookings(ctx context.Context, from, to string, limit, offset int) ([]*BookingRow, int64, error) {
	where := ` WHERE b.created_at >= ? AND b.created_at <= ?`
	args := []any{from, to}
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings b`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT b.id,
		COALESCE(p.business_name, p.display_name, ''),
		CONCAT(cu.first_name, ' ', cu.last_name),
		COALESCE(sv.name, ''),
		b.status, b.total_amount, b.currency, b.start_at, b.created_at
		FROM bookings b
		JOIN professionals p ON p.id = b.professional_id
		JOIN users cu ON cu.id = b.customer_id
		LEFT JOIN services sv ON sv.id = b.service_id
		`+where+` ORDER BY b.created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*BookingRow{}
	for rows.Next() {
		b := &BookingRow{}
		if err := rows.Scan(&b.ID, &b.Professional, &b.Customer, &b.Service, &b.Status, &b.Total, &b.Currency, &b.StartAt, &b.CreatedAt); err != nil {
			return nil, 0, err
		}
		out = append(out, b)
	}
	return out, total, rows.Err()
}

func (s *Store) Payments(ctx context.Context, from, to string, limit, offset int) ([]*PaymentRow, int64, error) {
	where := ` WHERE created_at >= ? AND created_at <= ?`
	args := []any{from, to}
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_intents`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT id, booking_id, customer_id, amount, currency, status, gateway, created_at
		FROM payment_intents`+where+` ORDER BY created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*PaymentRow{}
	for rows.Next() {
		p := &PaymentRow{}
		var gw sql.NullString
		if err := rows.Scan(&p.ID, &p.BookingID, &p.CustomerID, &p.Amount, &p.Currency, &p.Status, &gw, &p.CreatedAt); err != nil {
			return nil, 0, err
		}
		if gw.Valid {
			p.Gateway = &gw.String
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}

func (s *Store) Payouts(ctx context.Context, from, to string, limit, offset int) ([]*PayoutRow, int64, error) {
	where := ` WHERE created_at >= ? AND created_at <= ?`
	args := []any{from, to}
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payouts`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT id, professional_id, amount, currency, status, paid_at, created_at
		FROM payouts`+where+` ORDER BY created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*PayoutRow{}
	for rows.Next() {
		p := &PayoutRow{}
		var paidAt sql.NullTime
		if err := rows.Scan(&p.ID, &p.ProfessionalID, &p.Amount, &p.Currency, &p.Status, &paidAt, &p.CreatedAt); err != nil {
			return nil, 0, err
		}
		if paidAt.Valid {
			p.PaidAt = &paidAt.Time
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}
