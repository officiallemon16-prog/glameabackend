package reviews

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Review struct {
	ID             string     `json:"id"`
	BookingID      string     `json:"booking_id"`
	ProfessionalID string     `json:"professional_id"`
	CustomerID     string     `json:"customer_id"`
	ServiceID      *string    `json:"service_id,omitempty"`
	Rating         int        `json:"rating"`
	Comment        string     `json:"comment,omitempty"`
	Response       string     `json:"response,omitempty"`
	RespondedAt    *time.Time `json:"responded_at,omitempty"`
	IsPublished    bool       `json:"is_published"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`

	ProfessionalName string `json:"professional_name,omitempty"`
	CustomerName     string `json:"customer_name,omitempty"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `r.id, r.booking_id, r.professional_id, r.customer_id, r.service_id, r.rating, r.comment,
	r.response, r.responded_at, r.is_published, r.created_at, r.updated_at,
	p.business_name, CONCAT(u.first_name, ' ', u.last_name)`

const from = ` reviews r
	JOIN professionals p ON p.id = r.professional_id
	JOIN users u ON u.id = r.customer_id`

func scan(row interface{ Scan(...any) error }) (*Review, error) {
	var rv Review
	var serviceID, comment, response, proName, custName sql.NullString
	var respondedAt sql.NullTime
	err := row.Scan(&rv.ID, &rv.BookingID, &rv.ProfessionalID, &rv.CustomerID, &serviceID, &rv.Rating, &comment,
		&response, &respondedAt, &rv.IsPublished, &rv.CreatedAt, &rv.UpdatedAt,
		&proName, &custName)
	if err != nil {
		return nil, err
	}
	if serviceID.Valid {
		rv.ServiceID = &serviceID.String
	}
	rv.Comment = comment.String
	rv.Response = response.String
	if respondedAt.Valid {
		rv.RespondedAt = &respondedAt.Time
	}
	rv.ProfessionalName = proName.String
	rv.CustomerName = custName.String
	return &rv, nil
}

func (s *Store) Create(ctx context.Context, in Review) (*Review, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO reviews
		(id, booking_id, professional_id, customer_id, service_id, rating, comment, is_published)
		VALUES (?, ?, ?, ?, ?, ?, ?, 1)`,
		id, in.BookingID, in.ProfessionalID, in.CustomerID, nullString(in.ServiceID), in.Rating, in.Comment)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Review, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM`+from+` WHERE r.id = ?`, id)
	rv, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("review_not_found", "review not found")
		}
		return nil, err
	}
	return rv, nil
}

func (s *Store) GetByBookingID(ctx context.Context, bookingID string) (*Review, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM`+from+` WHERE r.booking_id = ?`, bookingID)
	rv, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return rv, nil
}

func (s *Store) ListForProfessional(ctx context.Context, professionalID string, limit, offset int) ([]*Review, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM reviews WHERE professional_id = ? AND is_published = 1`,
		professionalID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM`+from+
		` WHERE r.professional_id = ? AND r.is_published = 1 ORDER BY r.created_at DESC LIMIT ? OFFSET ?`,
		professionalID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Review{}
	for rows.Next() {
		rv, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, rv)
	}
	return out, total, rows.Err()
}

func (s *Store) ListForCustomer(ctx context.Context, customerID string, limit, offset int) ([]*Review, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM reviews WHERE customer_id = ?`,
		customerID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM`+from+
		` WHERE r.customer_id = ? ORDER BY r.created_at DESC LIMIT ? OFFSET ?`, customerID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Review{}
	for rows.Next() {
		rv, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, rv)
	}
	return out, total, rows.Err()
}

func (s *Store) Respond(ctx context.Context, id, response string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE reviews SET response = ?, responded_at = NOW() WHERE id = ? AND response IS NULL`,
		response, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.Conflict("review_responded", "review already has a response")
	}
	return nil
}

func (s *Store) RecomputeProfessional(ctx context.Context, professionalID string) error {
	var avg sql.NullFloat64
	var cnt int
	if err := s.db.QueryRowContext(ctx, `SELECT AVG(rating), COUNT(*) FROM reviews
		WHERE professional_id = ? AND is_published = 1`, professionalID).Scan(&avg, &cnt); err != nil {
		return err
	}
	rating := 0.0
	if avg.Valid {
		rating = avg.Float64
	}
	_, err := s.db.ExecContext(ctx, `UPDATE professionals SET rating = ?, review_count = ? WHERE id = ?`,
		rating, cnt, professionalID)
	return err
}

func nullString(v *string) any {
	if v == nil {
		return nil
	}
	return *v
}
