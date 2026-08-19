package categories

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

const cols = `id, slug, name, description, icon_media_id, image_url, display_order, is_active, created_at, updated_at`

func scan(row interface{ Scan(...any) error }) (*Category, error) {
	var c Category
	var desc sql.NullString
	var icon sql.NullString
	var imageURL sql.NullString
	err := row.Scan(&c.ID, &c.Slug, &c.Name, &desc, &icon, &imageURL, &c.DisplayOrder, &c.IsActive, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		return nil, err
	}
	c.Description = desc.String
	if icon.Valid {
		c.IconMediaID = &icon.String
	}
	c.ImageURL = imageURL.String
	return &c, nil
}

func (s *Store) List(ctx context.Context, includeInactive bool) ([]*Category, error) {
	q := `SELECT ` + cols + ` FROM categories`
	if !includeInactive {
		q += ` WHERE is_active = 1`
	}
	q += ` ORDER BY display_order ASC, name ASC`

	rows, err := s.db.QueryContext(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []*Category{}
	for rows.Next() {
		c, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) GetBySlug(ctx context.Context, slug string) (*Category, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM categories WHERE slug = ?`, slug)
	c, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("category_not_found", "category not found")
		}
		return nil, err
	}
	return c, nil
}

func (s *Store) GetByID(ctx context.Context, id string) (*Category, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM categories WHERE id = ?`, id)
	c, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("category_not_found", "category not found")
		}
		return nil, err
	}
	return c, nil
}

type CreateInput struct {
	Slug         string
	Name         string
	Description  string
	IconMediaID  *string
	ImageURL     string
	DisplayOrder int
}

func (s *Store) Create(ctx context.Context, in CreateInput) (*Category, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO categories
		(id, slug, name, description, icon_media_id, image_url, display_order, is_active)
		VALUES (?, ?, ?, ?, ?, ?, ?, 1)`,
		id, in.Slug, in.Name, in.Description, nullString(in.IconMediaID), nullStr(in.ImageURL), in.DisplayOrder)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Update(ctx context.Context, id string, in CreateInput) (*Category, error) {
	_, err := s.db.ExecContext(ctx, `UPDATE categories SET
		slug = ?, name = ?, description = ?, icon_media_id = ?, image_url = ?, display_order = ?
		WHERE id = ?`,
		in.Slug, in.Name, in.Description, nullString(in.IconMediaID), nullStr(in.ImageURL), in.DisplayOrder, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) SetActive(ctx context.Context, id string, active bool) error {
	_, err := s.db.ExecContext(ctx, `UPDATE categories SET is_active = ? WHERE id = ?`, active, id)
	return err
}

func (s *Store) Delete(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM categories WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("category_not_found", "category not found")
	}
	return nil
}

func Slugify(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	name = strings.NewReplacer("&", "-and-", "@", "-", " ", "-", "_", "-", "--", "-").Replace(name)
	name = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		return -1
	}, name)
	name = strings.Trim(name, "-")
	if name == "" {
		name = "category"
	}
	return name
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}

func nullStr(v string) sql.NullString {
	if v == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: v, Valid: true}
}
