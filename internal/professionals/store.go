package professionals

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `id, user_id, business_name, display_name, bio, category_id, experience_years,
	rating, review_count, booking_count, completion_rate, status, verification_status, trust_score,
	latitude, longitude, address_line, city, country, timezone, home_service_enabled,
	service_radius_km, travel_fee_per_km, created_at, updated_at`

func scan(row interface{ Scan(...any) error }) (*Professional, error) {
	var p Professional
	var display, bio, cat sql.NullString
	var dbName sql.NullString
	var expYears sql.NullInt64
	var latitude, longitude, serviceRadius sql.NullFloat64
	var homeEnabled sql.NullBool
	err := row.Scan(&p.ID, &p.UserID, &dbName, &display, &bio, &cat, &expYears,
		&p.Rating, &p.ReviewCount, &p.BookingCount, &p.CompletionRate, &p.Status, &p.VerificationStatus, &p.TrustScore,
		&latitude, &longitude, &p.AddressLine, &p.City, &p.Country, &p.Timezone, &homeEnabled,
		&serviceRadius, &p.TravelFeePerKm, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	p.BusinessName = dbName.String
	p.DisplayName = display.String
	p.Bio = bio.String
	if cat.Valid {
		p.CategoryID = &cat.String
	}
	if expYears.Valid {
		years := int(expYears.Int64)
		p.ExperienceYears = &years
	}
	if latitude.Valid {
		p.Latitude = &latitude.Float64
	}
	if longitude.Valid {
		p.Longitude = &longitude.Float64
	}
	if serviceRadius.Valid {
		p.ServiceRadiusKm = &serviceRadius.Float64
	}
	p.HomeServiceEnabled = homeEnabled.Valid && homeEnabled.Bool
	return &p, nil
}

func (s *Store) Create(ctx context.Context, p *Professional) (*Professional, error) {
	if p.ID == "" {
		p.ID = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO professionals
		(id, user_id, business_name, display_name, bio, category_id, experience_years, status, verification_status,
		 latitude, longitude, address_line, city, country, timezone, home_service_enabled, service_radius_km, travel_fee_per_km)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		p.ID, p.UserID, p.BusinessName, nullableString(p.DisplayName), p.Bio, nullString(p.CategoryID),
		nullInt(p.ExperienceYears), p.Status, p.VerificationStatus,
		nullFloat(p.Latitude), nullFloat(p.Longitude), p.AddressLine, p.City, p.Country, p.Timezone,
		p.HomeServiceEnabled, nullFloat(p.ServiceRadiusKm), p.TravelFeePerKm)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, p.ID)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Professional, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM professionals WHERE id = ?`, id)
	p, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("professional_not_found", "professional not found")
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) GetByUserID(ctx context.Context, userID string) (*Professional, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM professionals WHERE user_id = ?`, userID)
	p, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("professional_not_found", "professional profile not found")
		}
		return nil, err
	}
	return p, nil
}

func (s *Store) Update(ctx context.Context, id string, update func(*Professional)) (*Professional, error) {
	p, err := s.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	update(p)

	_, err = s.db.ExecContext(ctx, `UPDATE professionals SET
		business_name = ?, display_name = ?, bio = ?, category_id = ?, experience_years = ?,
		latitude = ?, longitude = ?, address_line = ?, city = ?, country = ?, timezone = ?,
		home_service_enabled = ?, service_radius_km = ?, travel_fee_per_km = ?
		WHERE id = ?`,
		p.BusinessName, nullableString(p.DisplayName), p.Bio, nullString(p.CategoryID), nullInt(p.ExperienceYears),
		nullFloat(p.Latitude), nullFloat(p.Longitude), p.AddressLine, p.City, p.Country, p.Timezone,
		p.HomeServiceEnabled, nullFloat(p.ServiceRadiusKm), p.TravelFeePerKm, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) SetStatus(ctx context.Context, id, status string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE professionals SET status = ? WHERE id = ?`, status, id)
	return err
}

func (s *Store) SetVerificationStatus(ctx context.Context, id, status string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE professionals SET verification_status = ? WHERE id = ?`, status, id)
	return err
}

func (s *Store) PublicProfile(ctx context.Context, id string) (*PublicProfile, error) {
	p, err := s.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	profile := &PublicProfile{Professional: *p}
	err = s.db.QueryRowContext(ctx, `SELECT first_name, last_name, avatar_media_id FROM users WHERE id = ?`, p.UserID).
		Scan(&profile.User.FirstName, &profile.User.LastName, &profile.User.AvatarMediaID)
	if err != nil {
		return nil, fmt.Errorf("load professional user: %w", err)
	}
	return profile, nil
}

func (s *Store) List(ctx context.Context, filter ListFilter) ([]*Professional, int64, error) {
	where := " WHERE status = 'ACTIVE'"
	args := []any{}
	if filter.CategoryID != "" {
		where += " AND category_id = ?"
		args = append(args, filter.CategoryID)
	}
	if filter.City != "" {
		where += " AND city = ?"
		args = append(args, filter.City)
	}
	if filter.VerifiedOnly {
		where += " AND verification_status = 'VERIFIED'"
	}
	if filter.HomeServiceOnly {
		where += " AND home_service_enabled = 1"
	}
	if filter.Query != "" {
		where += " AND (business_name LIKE ? OR display_name LIKE ? OR city LIKE ?)"
		like := "%" + filter.Query + "%"
		args = append(args, like, like, like)
	}

	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM professionals`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	order := "booking_count DESC"
	if filter.Sort == "rating" {
		order = "rating DESC, review_count DESC"
	}
	if filter.Sort == "newest" {
		order = "created_at DESC"
	}

	q := `SELECT ` + cols + ` FROM professionals` + where + ` ORDER BY ` + order + ` LIMIT ? OFFSET ?`
	args = append(args, filter.Limit, filter.Offset)

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := []*Professional{}
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}

type ListFilter struct {
	Query           string
	CategoryID      string
	City            string
	VerifiedOnly    bool
	HomeServiceOnly bool
	Sort            string
	Limit           int
	Offset          int
}

func (s *Store) ListAdmin(ctx context.Context, status string, limit, offset int) ([]*Professional, int64, error) {
	where := " WHERE 1=1"
	args := []any{}
	if status != "" {
		where += " AND status = ?"
		args = append(args, status)
	}
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM professionals`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM professionals`+where+
		` ORDER BY created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Professional{}
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}

func nullableString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

func nullInt(v *int) sql.NullInt64 {
	if v == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*v), Valid: true}
}

func nullFloat(v *float64) sql.NullFloat64 {
	if v == nil {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: *v, Valid: true}
}
