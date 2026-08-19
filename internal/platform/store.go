package platform

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Setting struct {
	Name      string    `json:"name"`
	Value     string    `json:"value"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) All(ctx context.Context) ([]*Setting, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT name, COALESCE(value,''), updated_at FROM platform_settings ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Setting{}
	for rows.Next() {
		st := &Setting{}
		if err := rows.Scan(&st.Name, &st.Value, &st.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, st)
	}
	return out, rows.Err()
}

func (s *Store) Get(ctx context.Context, name string) (*Setting, error) {
	row := s.db.QueryRowContext(ctx, `SELECT name, COALESCE(value,''), updated_at FROM platform_settings WHERE name = ?`, name)
	st := &Setting{}
	if err := row.Scan(&st.Name, &st.Value, &st.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("setting_not_found", "setting not found")
		}
		return nil, err
	}
	return st, nil
}

func (s *Store) Set(ctx context.Context, name, value string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO platform_settings (name, value) VALUES (?, ?)
		ON DUPLICATE KEY UPDATE value = VALUES(value)`, name, value)
	return err
}

func (s *Store) UpsertMany(ctx context.Context, pairs map[string]string) error {
	for k, v := range pairs {
		if err := s.Set(ctx, k, v); err != nil {
			return err
		}
	}
	return nil
}
