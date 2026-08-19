package deals

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	DiscountPercent = "PERCENT"
	DiscountFixed   = "FIXED"
)

type Deal struct {
	ID             string     `json:"id"`
	ProfessionalID string     `json:"professional_id"`
	Code           string     `json:"code"`
	Name           string     `json:"name"`
	Description    string     `json:"description,omitempty"`
	DiscountType   string     `json:"discount_type"`
	DiscountValue  float64    `json:"discount_value"`
	MinOrderAmount float64    `json:"min_order_amount"`
	UsageLimit     *int       `json:"usage_limit,omitempty"`
	TimesUsed      int        `json:"times_used"`
	StartsAt       *time.Time `json:"starts_at,omitempty"`
	EndsAt         *time.Time `json:"ends_at,omitempty"`
	IsActive       bool       `json:"is_active"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`

	ServiceIDs []string `json:"-"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `d.id, d.professional_id, d.code, d.name, d.description, d.discount_type, d.discount_value,
	d.min_order_amount, d.usage_limit, d.times_used, d.starts_at, d.ends_at, d.is_active, d.created_at, d.updated_at`

const from = ` deals d`

func scan(row interface{ Scan(...any) error }) (*Deal, error) {
	var d Deal
	var desc sql.NullString
	var usageLimit sql.NullInt32
	var startsAt, endsAt sql.NullTime
	err := row.Scan(&d.ID, &d.ProfessionalID, &d.Code, &d.Name, &desc, &d.DiscountType, &d.DiscountValue,
		&d.MinOrderAmount, &usageLimit, &d.TimesUsed, &startsAt, &endsAt, &d.IsActive, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}
	d.Description = desc.String
	if usageLimit.Valid {
		v := int(usageLimit.Int32)
		d.UsageLimit = &v
	}
	if startsAt.Valid {
		d.StartsAt = &startsAt.Time
	}
	if endsAt.Valid {
		d.EndsAt = &endsAt.Time
	}
	return &d, nil
}

func (s *Store) Create(ctx context.Context, in Deal) (*Deal, error) {
	id := uuid.NewString()
	if in.Code == "" {
		in.Code = strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))[:8]
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO deals
		(id, professional_id, code, name, description, discount_type, discount_value, min_order_amount, usage_limit, starts_at, ends_at, is_active)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
		id, in.ProfessionalID, in.Code, in.Name, in.Description, in.DiscountType, in.DiscountValue,
		in.MinOrderAmount, nullableInt(in.UsageLimit), in.StartsAt, in.EndsAt)
	if err != nil {
		return nil, err
	}
	for _, svcID := range in.ServiceIDs {
		if _, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO deal_services (deal_id, service_id) VALUES (?, ?)`, id, svcID); err != nil {
			return nil, err
		}
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Deal, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM`+from+` WHERE d.id = ?`, id)
	d, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("deal_not_found", "deal not found")
		}
		return nil, err
	}
	return d, nil
}

func (s *Store) Update(ctx context.Context, id string, upd func(*Deal)) (*Deal, error) {
	d, err := s.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	upd(d)
	_, err = s.db.ExecContext(ctx, `UPDATE deals SET
		name = ?, description = ?, discount_type = ?, discount_value = ?, min_order_amount = ?, usage_limit = ?, starts_at = ?, ends_at = ?, is_active = ?
		WHERE id = ?`,
		d.Name, d.Description, d.DiscountType, d.DiscountValue, d.MinOrderAmount,
		nullableInt(d.UsageLimit), d.StartsAt, d.EndsAt, d.IsActive, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) SetActive(ctx context.Context, id string, active bool) error {
	_, err := s.db.ExecContext(ctx, `UPDATE deals SET is_active = ? WHERE id = ?`, active, id)
	return err
}

func (s *Store) Delete(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM deals WHERE id = ?`, id)
	return err
}

func (s *Store) ListActive(ctx context.Context, limit, offset int) ([]*Deal, int64, error) {
	where := ` WHERE d.is_active = 1 AND (d.starts_at IS NULL OR d.starts_at <= NOW()) AND (d.ends_at IS NULL OR d.ends_at > NOW())`
	return s.list(ctx, where, nil, limit, offset)
}

func (s *Store) ListForProfessional(ctx context.Context, professionalID string, limit, offset int) ([]*Deal, int64, error) {
	where := ` WHERE d.professional_id = ?`
	return s.list(ctx, where, []any{professionalID}, limit, offset)
}

func (s *Store) ListAll(ctx context.Context, active string, limit, offset int) ([]*Deal, int64, error) {
	where := ` WHERE 1=1`
	args := []any{}
	if active == "true" {
		where += ` AND d.is_active = 1`
	} else if active == "false" {
		where += ` AND d.is_active = 0`
	}
	return s.list(ctx, where, args, limit, offset)
}

func (s *Store) list(ctx context.Context, where string, args []any, limit, offset int) ([]*Deal, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM deals d`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM`+from+where+
		` ORDER BY d.created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Deal{}
	for rows.Next() {
		d, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, d)
	}
	return out, total, rows.Err()
}

func nullableInt(v *int) any {
	if v == nil {
		return nil
	}
	return *v
}
