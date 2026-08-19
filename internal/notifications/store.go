package notifications

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Notification struct {
	ID        string          `json:"id"`
	UserID    string          `json:"user_id"`
	Type      string          `json:"type"`
	Title     string          `json:"title"`
	Body      string          `json:"body,omitempty"`
	Data      json.RawMessage `json:"data,omitempty"`
	IsRead    bool            `json:"is_read"`
	ReadAt    *time.Time      `json:"read_at,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = "id, user_id, type, title, body, data, is_read, read_at, created_at"

func scan(row interface{ Scan(...any) error }) (*Notification, error) {
	var n Notification
	var body, data sql.NullString
	var readAt sql.NullTime
	err := row.Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &body, &data, &n.IsRead, &readAt, &n.CreatedAt)
	if err != nil {
		return nil, err
	}
	n.Body = body.String
	if data.Valid {
		n.Data = json.RawMessage(data.String)
	}
	if readAt.Valid {
		n.ReadAt = &readAt.Time
	}
	return &n, nil
}

func (s *Store) Create(ctx context.Context, userID, notifType, title, body string, data any) (*Notification, error) {
	id := uuid.NewString()
	var raw any
	if data != nil {
		b, err := json.Marshal(data)
		if err != nil {
			return nil, err
		}
		raw = string(b)
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO notifications (id, user_id, type, title, body, data)
		VALUES (?, ?, ?, ?, ?, ?)`,
		id, userID, notifType, title, body, raw)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Notification, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM notifications WHERE id = ?`, id)
	n, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("notification_not_found", "notification not found")
		}
		return nil, err
	}
	return n, nil
}

func (s *Store) ListForUser(ctx context.Context, userID string, limit, offset int) ([]*Notification, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM notifications WHERE user_id = ?`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols+` FROM notifications WHERE user_id = ?
		ORDER BY created_at DESC LIMIT ? OFFSET ?`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Notification{}
	for rows.Next() {
		n, err := scan(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, n)
	}
	return out, total, rows.Err()
}

func (s *Store) UnreadCount(ctx context.Context, userID string) (int64, error) {
	var n int64
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0`, userID).Scan(&n)
	return n, err
}

func (s *Store) MarkRead(ctx context.Context, userID, id string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE notifications SET is_read = 1, read_at = NOW()
		WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("notification_not_found", "notification not found")
	}
	return nil
}

func (s *Store) MarkAllRead(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE notifications SET is_read = 1, read_at = NOW()
		WHERE user_id = ? AND is_read = 0`, userID)
	return err
}

// DeviceToken is a registered push destination for a user.
type DeviceToken struct {
	ID         string    `json:"id"`
	UserID     string    `json:"user_id"`
	Token      string    `json:"token"`
	Platform   string    `json:"platform"`
	Disabled   bool      `json:"disabled"`
	LastSeenAt time.Time `json:"last_seen_at"`
	CreatedAt  time.Time `json:"created_at"`
}

// RegisterDevice upserts a device token for a user (re-registration on every
// app start refreshes the owner, platform and last-seen time).
func (s *Store) RegisterDevice(ctx context.Context, userID, token, platform string) (*DeviceToken, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO device_tokens (id, user_id, token, platform)
		VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			user_id = VALUES(user_id),
			platform = VALUES(platform),
			disabled = 0,
			last_seen_at = NOW()`,
		id, userID, token, platform)
	if err != nil {
		return nil, err
	}
	row := s.db.QueryRowContext(ctx, `SELECT id, user_id, token, platform, disabled, last_seen_at, created_at
		FROM device_tokens WHERE token = ?`, token)
	var d DeviceToken
	if err := row.Scan(&d.ID, &d.UserID, &d.Token, &d.Platform, &d.Disabled, &d.LastSeenAt, &d.CreatedAt); err != nil {
		return nil, err
	}
	return &d, nil
}

// ListTokensForUser returns the active (non-disabled) push tokens for a user.
func (s *Store) ListTokensForUser(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT token FROM device_tokens
		WHERE user_id = ? AND disabled = 0`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// RemoveDevice deletes a device token (logout / unregister).
func (s *Store) RemoveDevice(ctx context.Context, userID, token string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM device_tokens WHERE token = ? AND user_id = ?`, token, userID)
	return err
}

// DisableDevice marks a token invalid (FCM reports it unregistered).
func (s *Store) DisableDevice(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE device_tokens SET disabled = 1 WHERE token = ?`, token)
	return err
}
