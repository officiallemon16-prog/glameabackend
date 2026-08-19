package disputes

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	StatusOpen     = "OPEN"
	StatusResolved = "RESOLVED"
	StatusClosed   = "CLOSED"
)

type Dispute struct {
	ID          string     `json:"id"`
	BookingID   string     `json:"booking_id"`
	RaisedBy    string     `json:"raised_by"`
	Reason      string     `json:"reason"`
	Description string     `json:"description,omitempty"`
	Status      string     `json:"status"`
	Resolution  string     `json:"resolution,omitempty"`
	ResolvedBy  *string    `json:"resolved_by,omitempty"`
	ResolvedAt  *time.Time `json:"resolved_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`

	RaisedByName string `json:"raised_by_name,omitempty"`
}

type DisputeMessage struct {
	ID        string    `json:"id"`
	DisputeID string    `json:"dispute_id"`
	SenderID  string    `json:"sender_id"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `d.id, d.booking_id, d.raised_by, d.reason, d.description, d.status, d.resolution,
	d.resolved_by, d.resolved_at, d.created_at, d.updated_at,
	CONCAT(u.first_name, ' ', u.last_name)`

const from = ` disputes d JOIN users u ON u.id = d.raised_by`

func scan(row interface{ Scan(...any) error }) (*Dispute, error) {
	var d Dispute
	var desc, resolution sql.NullString
	var resolvedBy sql.NullString
	var resolvedAt sql.NullTime
	var name sql.NullString
	err := row.Scan(&d.ID, &d.BookingID, &d.RaisedBy, &d.Reason, &desc, &d.Status, &resolution,
		&resolvedBy, &resolvedAt, &d.CreatedAt, &d.UpdatedAt, &name)
	if err != nil {
		return nil, err
	}
	d.Description = desc.String
	d.Resolution = resolution.String
	if resolvedBy.Valid {
		d.ResolvedBy = &resolvedBy.String
	}
	if resolvedAt.Valid {
		d.ResolvedAt = &resolvedAt.Time
	}
	d.RaisedByName = name.String
	return &d, nil
}

func (s *Store) Create(ctx context.Context, in Dispute) (*Dispute, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO disputes
		(id, booking_id, raised_by, reason, description, status)
		VALUES (?, ?, ?, ?, ?, ?)`,
		id, in.BookingID, in.RaisedBy, in.Reason, in.Description, StatusOpen)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Dispute, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM`+from+` WHERE d.id = ?`, id)
	d, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("dispute_not_found", "dispute not found")
		}
		return nil, err
	}
	return d, nil
}

func (s *Store) ListForBooking(ctx context.Context, bookingID string) ([]*Dispute, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM`+from+` WHERE d.booking_id = ? ORDER BY d.created_at DESC`, bookingID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Dispute{}
	for rows.Next() {
		d, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Store) ListForUser(ctx context.Context, userID string, limit, offset int) ([]*Dispute, int64, error) {
	where := ` WHERE d.raised_by = ? OR d.booking_id IN (
		SELECT id FROM bookings WHERE customer_id = ? OR professional_id IN (SELECT id FROM professionals WHERE user_id = ?))`
	args := []any{userID, userID, userID}
	return s.list(ctx, where, args, limit, offset)
}

func (s *Store) ListAll(ctx context.Context, status string, limit, offset int) ([]*Dispute, int64, error) {
	where := " WHERE 1=1"
	args := []any{}
	if status != "" {
		where += " AND d.status = ?"
		args = append(args, status)
	}
	return s.list(ctx, where, args, limit, offset)
}

func (s *Store) list(ctx context.Context, where string, args []any, limit, offset int) ([]*Dispute, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM disputes d`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	qArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM`+from+where+
		` ORDER BY d.created_at DESC LIMIT ? OFFSET ?`, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Dispute{}
	for rows.Next() {
		d, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, d)
	}
	return out, total, rows.Err()
}

func (s *Store) AddMessage(ctx context.Context, disputeID, senderID, body string) (*DisputeMessage, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO dispute_messages (id, dispute_id, sender_id, body) VALUES (?, ?, ?, ?)`,
		id, disputeID, senderID, body)
	if err != nil {
		return nil, err
	}
	return &DisputeMessage{ID: id, DisputeID: disputeID, SenderID: senderID, Body: body, CreatedAt: time.Now()}, nil
}

func (s *Store) ListMessages(ctx context.Context, disputeID string) ([]*DisputeMessage, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, dispute_id, sender_id, body, created_at
		FROM dispute_messages WHERE dispute_id = ? ORDER BY created_at ASC`, disputeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*DisputeMessage{}
	for rows.Next() {
		var m DisputeMessage
		if err := rows.Scan(&m.ID, &m.DisputeID, &m.SenderID, &m.Body, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, &m)
	}
	return out, rows.Err()
}

func (s *Store) Resolve(ctx context.Context, id, resolution, resolvedBy string) (*Dispute, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE disputes SET status = ?, resolution = ?, resolved_by = ?, resolved_at = NOW()
		WHERE id = ? AND status = ?`, StatusResolved, resolution, resolvedBy, id, StatusOpen)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, httpx.Conflict("invalid_dispute_status", "dispute is not open")
	}
	return s.GetByID(ctx, id)
}
