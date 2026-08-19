package services

import (
	"context"
	"database/sql"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `id, professional_id, category_id, name, description, base_price, currency,
	duration_minutes, deposit_percentage, home_service_available, cancellation_policy_id,
	display_order, is_active, created_at, updated_at`

func scan(row interface{ Scan(...any) error }) (*Service, error) {
	var s Service
	var cat, cancel sql.NullString
	var desc sql.NullString
	var home sql.NullBool
	err := row.Scan(&s.ID, &s.ProfessionalID, &cat, &s.Name, &desc, &s.BasePrice, &s.Currency,
		&s.DurationMinutes, &s.DepositPercentage, &home, &cancel,
		&s.DisplayOrder, &s.IsActive, &s.CreatedAt, &s.UpdatedAt)
	if err != nil {
		return nil, err
	}
	s.Description = desc.String
	if cat.Valid {
		s.CategoryID = &cat.String
	}
	if cancel.Valid {
		s.CancellationPolicyID = &cancel.String
	}
	s.HomeServiceAvailable = home.Valid && home.Bool
	return &s, nil
}

func (s *Store) Create(ctx context.Context, in CreateInput) (*Service, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO services
		(id, professional_id, category_id, name, description, base_price, currency, duration_minutes,
		 deposit_percentage, home_service_available, cancellation_policy_id, display_order, is_active)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
		id, in.ProfessionalID, nullString(in.CategoryID), in.Name, in.Description, in.BasePrice, in.Currency,
		in.DurationMinutes, in.DepositPercentage, in.HomeServiceAvailable, nullString(in.CancellationPolicyID), in.DisplayOrder)
	if err != nil {
		return nil, err
	}
	for _, v := range in.Variants {
		if _, err := s.db.ExecContext(ctx, `INSERT INTO service_variants
			(id, service_id, name, price_delta, duration_delta_minutes, is_active)
			VALUES (?, ?, ?, ?, ?, 1)`,
			uuid.NewString(), id, v.Name, v.PriceDelta, v.DurationDeltaMinutes); err != nil {
			return nil, err
		}
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Service, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM services WHERE id = ?`, id)
	svc, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("service_not_found", "service not found")
		}
		return nil, err
	}
	variants, err := s.listVariants(ctx, id)
	if err != nil {
		return nil, err
	}
	svc.Variants = variants
	return svc, nil
}

func (s *Store) listVariants(ctx context.Context, serviceID string) ([]ServiceVariant, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, service_id, name, price_delta, duration_delta_minutes, is_active
		FROM service_variants WHERE service_id = ? AND is_active = 1 ORDER BY name`, serviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ServiceVariant{}
	for rows.Next() {
		var v ServiceVariant
		if err := rows.Scan(&v.ID, &v.ServiceID, &v.Name, &v.PriceDelta, &v.DurationDeltaMinutes, &v.IsActive); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (s *Store) Update(ctx context.Context, id string, in CreateInput) (*Service, error) {
	_, err := s.db.ExecContext(ctx, `UPDATE services SET
		category_id = ?, name = ?, description = ?, base_price = ?, currency = ?, duration_minutes = ?,
		deposit_percentage = ?, home_service_available = ?, cancellation_policy_id = ?, display_order = ?
		WHERE id = ?`,
		nullString(in.CategoryID), in.Name, in.Description, in.BasePrice, in.Currency, in.DurationMinutes,
		in.DepositPercentage, in.HomeServiceAvailable, nullString(in.CancellationPolicyID), in.DisplayOrder, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Delete(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM services WHERE id = ?`, id)
	return err
}

func (s *Store) SetActive(ctx context.Context, id string, active bool) error {
	_, err := s.db.ExecContext(ctx, `UPDATE services SET is_active = ? WHERE id = ?`, active, id)
	return err
}

type ListFilter struct {
	ProfessionalID  string
	CategoryID      string
	IncludeInactive bool
	Limit           int
	Offset          int
}

func (s *Store) List(ctx context.Context, filter ListFilter) ([]*Service, int64, error) {
	where := " WHERE 1=1"
	args := []any{}
	if filter.ProfessionalID != "" {
		where += " AND professional_id = ?"
		args = append(args, filter.ProfessionalID)
	}
	if filter.CategoryID != "" {
		where += " AND category_id = ?"
		args = append(args, filter.CategoryID)
	}
	if !filter.IncludeInactive {
		where += " AND is_active = 1"
	}

	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM services`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	limit := filter.Limit
	if limit == 0 {
		limit = 50
	}
	q := `SELECT ` + cols + ` FROM services` + where + ` ORDER BY display_order ASC, name ASC LIMIT ? OFFSET ?`
	args = append(args, limit, filter.Offset)

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := []*Service{}
	for rows.Next() {
		svc, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, svc)
	}
	return out, total, rows.Err()
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}
