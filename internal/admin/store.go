package admin

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"
)

type DashboardStats struct {
	Users          int64   `json:"users"`
	Professionals  int64   `json:"professionals"`
	Bookings       int64   `json:"bookings"`
	Completed      int64   `json:"completed_bookings"`
	Cancelled      int64   `json:"cancelled_bookings"`
	ActiveDeals    int64   `json:"active_deals"`
	OpenDisputes   int64   `json:"open_disputes"`
	PendingPayouts int64   `json:"pending_payouts"`
	TotalRevenue   float64 `json:"total_revenue"`
	EscrowBalance  float64 `json:"escrow_balance"`
}

type DailyMetric struct {
	Date     string  `json:"date"`
	Bookings int64   `json:"bookings"`
	Revenue  float64 `json:"revenue"`
	Signups  int64   `json:"signups"`
}

type AdminStore struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *AdminStore {
	return &AdminStore{db: db}
}

func (s *AdminStore) Dashboard(ctx context.Context) (*DashboardStats, error) {
	d := &DashboardStats{}
	var totalRevenue sql.NullFloat64

	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&d.Users); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM professionals WHERE status = 'ACTIVE'`).Scan(&d.Professionals); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings`).Scan(&d.Bookings); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE status = 'COMPLETED'`).Scan(&d.Completed); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE status = 'CANCELLED'`).Scan(&d.Cancelled); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM deals WHERE is_active = 1`).Scan(&d.ActiveDeals); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM disputes WHERE status = 'OPEN'`).Scan(&d.OpenDisputes); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payouts WHERE status = 'PENDING'`).Scan(&d.PendingPayouts); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status = 'COMPLETED'`).Scan(&totalRevenue); err != nil {
		return nil, err
	}
	d.TotalRevenue = totalRevenue.Float64

	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(balance),0) FROM wallets WHERE user_id = ?`,
		"00000000-0000-0000-0000-000000000000").Scan(&d.EscrowBalance); err != nil {
		return nil, err
	}
	return d, nil
}

func (s *AdminStore) DailyMetrics(ctx context.Context, from, to string) ([]*DailyMetric, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT DATE(created_at), COUNT(*), COALESCE(SUM(CASE WHEN status = 'COMPLETED' THEN total_amount ELSE 0 END),0)
		FROM bookings
		WHERE created_at >= ? AND created_at <= ?
		GROUP BY DATE(created_at) ORDER BY DATE(created_at)`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*DailyMetric{}
	for rows.Next() {
		m := &DailyMetric{}
		if err := rows.Scan(&m.Date, &m.Bookings, &m.Revenue); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

type AuditedEntry struct {
	ID         string          `json:"id"`
	ActorID    *string         `json:"actor_id,omitempty"`
	ActorRole  *string         `json:"actor_role,omitempty"`
	Action     string          `json:"action"`
	EntityType string          `json:"entity_type"`
	EntityID   *string         `json:"entity_id,omitempty"`
	Before     json.RawMessage `json:"before_state,omitempty"`
	After      json.RawMessage `json:"after_state,omitempty"`
	IP         *string         `json:"ip,omitempty"`
	UserAgent  *string         `json:"user_agent,omitempty"`
	CreatedAt  time.Time       `json:"created_at"`
}

func (s *AdminStore) ListAudit(ctx context.Context, entityType, entityID string, limit, offset int) ([]*AuditedEntry, int64, error) {
	where := " WHERE 1=1"
	args := []any{}
	if entityType != "" {
		where += " AND entity_type = ?"
		args = append(args, entityType)
	}
	if entityID != "" {
		where += " AND entity_id = ?"
		args = append(args, entityID)
	}
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM audit_logs`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT id, actor_id, actor_role, action, entity_type, entity_id,
		before_state, after_state, ip, user_agent, created_at
		FROM audit_logs`+where+` ORDER BY created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*AuditedEntry{}
	for rows.Next() {
		e := &AuditedEntry{}
		var actorID, actorRole, entityIDCol, ip, ua sql.NullString
		var before, after []byte
		if err := rows.Scan(&e.ID, &actorID, &actorRole, &e.Action, &e.EntityType, &entityIDCol,
			&before, &after, &ip, &ua, &e.CreatedAt); err != nil {
			return nil, 0, err
		}
		if actorID.Valid {
			e.ActorID = &actorID.String
		}
		if actorRole.Valid {
			e.ActorRole = &actorRole.String
		}
		if entityIDCol.Valid {
			e.EntityID = &entityIDCol.String
		}
		if ip.Valid {
			e.IP = &ip.String
		}
		if ua.Valid {
			e.UserAgent = &ua.String
		}
		if len(before) > 0 {
			e.Before = json.RawMessage(before)
		}
		if len(after) > 0 {
			e.After = json.RawMessage(after)
		}
		out = append(out, e)
	}
	return out, total, rows.Err()
}
