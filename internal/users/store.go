package users

import (
	"context"
	"database/sql"
	"strings"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const userColumns = `id, email, phone, first_name, last_name, avatar_media_id, role, status,
	email_verified_at IS NOT NULL, phone_verified_at IS NOT NULL, last_login_at, created_at, updated_at`

func scanUser(row interface{ Scan(...any) error }) (*User, error) {
	var u User
	var email, phone, avatar sql.NullString
	var lastLogin sql.NullTime
	err := row.Scan(&u.ID, &email, &phone, &u.FirstName, &u.LastName, &avatar, &u.Role, &u.Status,
		&u.EmailVerified, &u.PhoneVerified, &lastLogin, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if email.Valid {
		u.Email = &email.String
	}
	if phone.Valid {
		u.Phone = &phone.String
	}
	if avatar.Valid {
		u.AvatarMediaID = &avatar.String
	}
	if lastLogin.Valid {
		u.LastLoginAt = &lastLogin.Time
	}
	return &u, nil
}

func (s *Store) Create(ctx context.Context, u *User, passwordHash string) (*User, error) {
	if u.ID == "" {
		u.ID = newUUID()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO users
		(id, email, phone, first_name, last_name, avatar_media_id, role, status, password_hash)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		u.ID, nullString(u.Email), nullString(u.Phone), u.FirstName, u.LastName,
		nullString(u.AvatarMediaID), u.Role, u.Status, passwordHash)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, u.ID)
}

func (s *Store) GetByID(ctx context.Context, id string) (*User, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+userColumns+` FROM users WHERE id = ?`, id)
	u, err := scanUser(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("user_not_found", "user not found")
		}
		return nil, err
	}
	return u, nil
}

func (s *Store) GetByEmail(ctx context.Context, email string) (*User, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+userColumns+` FROM users WHERE email = ?`, email)
	u, err := scanUser(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("user_not_found", "user not found")
		}
		return nil, err
	}
	return u, nil
}

func (s *Store) GetByPhone(ctx context.Context, phone string) (*User, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+userColumns+` FROM users WHERE phone = ?`, phone)
	u, err := scanUser(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("user_not_found", "user not found")
		}
		return nil, err
	}
	return u, nil
}

func (s *Store) GetByIdentifier(ctx context.Context, identifier string) (*User, error) {
	u, err := s.GetByEmail(ctx, identifier)
	if err == nil {
		return u, nil
	}
	if !strings.Contains(identifier, "@") {
		return s.GetByPhone(ctx, identifier)
	}
	return nil, err
}

func (s *Store) GetPasswordHash(ctx context.Context, userID string) (string, error) {
	var hash string
	err := s.db.QueryRowContext(ctx, `SELECT password_hash FROM users WHERE id = ?`, userID).Scan(&hash)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", httpx.NotFound("user_not_found", "user not found")
		}
		return "", err
	}
	return hash, nil
}

func (s *Store) Update(ctx context.Context, id string, update func(*User)) (*User, error) {
	u, err := s.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	before := *u
	update(u)

	_, err = s.db.ExecContext(ctx, `UPDATE users SET
		email = ?, phone = ?, first_name = ?, last_name = ?, avatar_media_id = ?
		WHERE id = ?`,
		nullString(u.Email), nullString(u.Phone), u.FirstName, u.LastName, nullString(u.AvatarMediaID), id)
	if err != nil {
		return nil, err
	}
	_ = before
	return s.GetByID(ctx, id)
}

func (s *Store) MarkEmailVerified(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET email_verified_at = COALESCE(email_verified_at, NOW()) WHERE id = ?`, id)
	return err
}

func (s *Store) MarkPhoneVerified(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, NOW()) WHERE id = ?`, id)
	return err
}

func (s *Store) SetPasswordHash(ctx context.Context, id, passwordHash string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET password_hash = ? WHERE id = ?`, passwordHash, id)
	return err
}

func (s *Store) UpdateLoginInfo(ctx context.Context, id, ip string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET last_login_at = NOW(), last_login_ip = ? WHERE id = ?`, ip, id)
	return err
}

func (s *Store) List(ctx context.Context, limit, offset int) ([]*User, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := s.db.QueryContext(ctx, `SELECT `+userColumns+` FROM users ORDER BY created_at DESC LIMIT ? OFFSET ?`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	users := []*User{}
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, 0, err
		}
		users = append(users, u)
	}
	return users, total, rows.Err()
}

func (s *Store) SetStatus(ctx context.Context, id, status string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET status = ? WHERE id = ?`, status, id)
	return err
}

func (s *Store) SetRole(ctx context.Context, id, role string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE users SET role = ? WHERE id = ?`, role, id)
	return err
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}

func newUUID() string {
	return uuid.NewString()
}
