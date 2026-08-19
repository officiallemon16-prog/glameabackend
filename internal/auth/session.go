package auth

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Session struct {
	ID        string     `json:"id"`
	UserID    string     `json:"user_id"`
	TokenHash string     `json:"-"`
	ExpiresAt time.Time  `json:"expires_at"`
	RevokedAt *time.Time `json:"revoked_at,omitempty"`
	IP        string     `json:"-"`
	UserAgent string     `json:"-"`
	CreatedAt time.Time  `json:"created_at"`
}

type SessionStore struct {
	db *sql.DB
}

func NewSessionStore(db *sql.DB) *SessionStore {
	return &SessionStore{db: db}
}

func (s *SessionStore) Create(ctx context.Context, session *Session) (*Session, error) {
	if session.ID == "" {
		session.ID = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO auth_sessions
		(id, user_id, token_hash, expires_at, ip, user_agent)
		VALUES (?, ?, ?, ?, ?, ?)`,
		session.ID, session.UserID, session.TokenHash, session.ExpiresAt, session.IP, session.UserAgent)
	if err != nil {
		return nil, err
	}
	return session, nil
}

func (s *SessionStore) GetByHash(ctx context.Context, tokenHash string) (*Session, error) {
	var sess Session
	var revokedAt sql.NullTime
	err := s.db.QueryRowContext(ctx, `SELECT id, user_id, token_hash, expires_at, revoked_at, ip, user_agent, created_at
		FROM auth_sessions WHERE token_hash = ?`, tokenHash).
		Scan(&sess.ID, &sess.UserID, &sess.TokenHash, &sess.ExpiresAt, &revokedAt, &sess.IP, &sess.UserAgent, &sess.CreatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.Unauthorized("invalid_refresh_token", "refresh token is invalid")
		}
		return nil, err
	}
	if revokedAt.Valid {
		sess.RevokedAt = &revokedAt.Time
	}
	return &sess, nil
}

// Revoke marks the session revoked and reports whether it was still active.
// The atomic guard (revoked_at IS NULL) makes concurrent rotation safe: only one
// caller can transition a given session from active to revoked.
func (s *SessionStore) Revoke(ctx context.Context, id string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE auth_sessions SET revoked_at = NOW() WHERE id = ? AND revoked_at IS NULL`, id)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

func (s *SessionStore) RevokeAllForUser(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE auth_sessions SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL`, userID)
	return err
}
