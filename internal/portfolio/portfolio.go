package portfolio

import (
	"context"
	"database/sql"
	"time"

	"github.com/glamea/glamea-backend/internal/media"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Item struct {
	ID              string       `json:"id"`
	ProfessionalID  string       `json:"professional_id"`
	MediaAssetID    string       `json:"media_asset_id"`
	ServiceID       *string      `json:"service_id,omitempty"`
	Caption         string       `json:"caption,omitempty"`
	IsFeatured      bool         `json:"is_featured"`
	DisplayOrder    int          `json:"display_order"`
	BeforeAfterPair *string      `json:"before_after_pair_id,omitempty"`
	IsVerification  bool         `json:"is_verification"`
	Asset           *media.Asset `json:"asset,omitempty"`
	CreatedAt       time.Time    `json:"created_at"`
	UpdatedAt       time.Time    `json:"updated_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const cols = `id, professional_id, media_asset_id, service_id, caption, is_featured, display_order,
	before_after_pair_id, is_verification, is_active, created_at, updated_at`

func scan(row interface{ Scan(...any) error }) (*Item, error) {
	var it Item
	var service, caption, pair sql.NullString
	var featured, verification, active sql.NullBool
	err := row.Scan(&it.ID, &it.ProfessionalID, &it.MediaAssetID, &service, &caption, &featured,
		&it.DisplayOrder, &pair, &verification, &active, &it.CreatedAt, &it.UpdatedAt)
	if err != nil {
		return nil, err
	}
	it.Caption = caption.String
	if service.Valid {
		it.ServiceID = &service.String
	}
	if pair.Valid {
		it.BeforeAfterPair = &pair.String
	}
	it.IsFeatured = featured.Valid && featured.Bool
	it.IsVerification = verification.Valid && verification.Bool
	return &it, nil
}

type CreateInput struct {
	ProfessionalID string
	MediaAssetID   string
	ServiceID      *string
	Caption        string
	IsFeatured     bool
	DisplayOrder   int
	IsVerification bool
}

func (s *Store) Create(ctx context.Context, in CreateInput) (*Item, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO portfolio_items
		(id, professional_id, media_asset_id, service_id, caption, is_featured, display_order, is_verification, is_active)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)`,
		id, in.ProfessionalID, in.MediaAssetID, nullString(in.ServiceID), in.Caption,
		in.IsFeatured, in.DisplayOrder, in.IsVerification)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Item, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM portfolio_items WHERE id = ?`, id)
	it, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("portfolio_item_not_found", "portfolio item not found")
		}
		return nil, err
	}
	return it, nil
}

// GetByIDActive returns a single active, non-verification item for public
// display, or a not-found error when the item is hidden or missing.
func (s *Store) GetByIDActive(ctx context.Context, id string) (*Item, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+cols+` FROM portfolio_items WHERE id = ? AND is_active = 1 AND is_verification = 0`, id)
	it, err := scan(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("portfolio_item_not_found", "portfolio item not found")
		}
		return nil, err
	}
	return it, nil
}

func (s *Store) Update(ctx context.Context, id string, in CreateInput) (*Item, error) {
	_, err := s.db.ExecContext(ctx, `UPDATE portfolio_items SET
		media_asset_id = ?, service_id = ?, caption = ?, is_featured = ?, display_order = ?, is_verification = ?
		WHERE id = ?`,
		in.MediaAssetID, nullString(in.ServiceID), in.Caption, in.IsFeatured, in.DisplayOrder, in.IsVerification, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Delete(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM portfolio_items WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("portfolio_item_not_found", "portfolio item not found")
	}
	return nil
}

func (s *Store) ListByProfessional(ctx context.Context, professionalID string, includeVerification bool) ([]*Item, error) {
	q := `SELECT ` + cols + ` FROM portfolio_items WHERE professional_id = ? AND is_active = 1`
	if !includeVerification {
		q += ` AND is_verification = 0`
	}
	q += ` ORDER BY is_featured DESC, display_order ASC, created_at DESC`

	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []*Item{}
	for rows.Next() {
		it, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}

type Service struct {
	store    *Store
	proStore *professionals.Store
	mediaSvc *media.Service
}

func NewService(store *Store, proStore *professionals.Store, mediaSvc *media.Service) *Service {
	return &Service{store: store, proStore: proStore, mediaSvc: mediaSvc}
}

func (s *Service) Create(ctx context.Context, userID string, in CreateInput) (*Item, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if in.MediaAssetID == "" {
		return nil, httpx.BadRequest("media_asset_required", "media_asset_id is required")
	}
	if _, err := s.mediaSvc.Get(ctx, in.MediaAssetID); err != nil {
		return nil, err
	}
	in.ProfessionalID = prof.ID
	item, err := s.store.Create(ctx, in)
	if err != nil {
		return nil, err
	}
	return s.withAsset(ctx, item)
}

func (s *Service) Update(ctx context.Context, userID, itemID string, in CreateInput) (*Item, error) {
	item, err := s.store.GetByID(ctx, itemID)
	if err != nil {
		return nil, err
	}
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if item.ProfessionalID != prof.ID {
		return nil, httpx.Forbidden("not_your_item", "you can only update your own portfolio items")
	}
	if in.MediaAssetID == "" {
		in.MediaAssetID = item.MediaAssetID
	}
	if in.ServiceID == nil {
		in.ServiceID = item.ServiceID
	}
	if in.Caption == "" {
		in.Caption = item.Caption
	}
	in.ProfessionalID = prof.ID
	updated, err := s.store.Update(ctx, itemID, in)
	if err != nil {
		return nil, err
	}
	return s.withAsset(ctx, updated)
}

func (s *Service) Delete(ctx context.Context, userID, itemID string) error {
	item, err := s.store.GetByID(ctx, itemID)
	if err != nil {
		return err
	}
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if item.ProfessionalID != prof.ID {
		return httpx.Forbidden("not_your_item", "you can only delete your own portfolio items")
	}
	return s.store.Delete(ctx, itemID)
}

func (s *Service) ListForProfessional(ctx context.Context, professionalID string, includeVerification bool) ([]*Item, error) {
	items, err := s.store.ListByProfessional(ctx, professionalID, includeVerification)
	if err != nil {
		return nil, err
	}
	out := make([]*Item, 0, len(items))
	for _, it := range items {
		withAsset, err := s.withAsset(ctx, it)
		if err != nil {
			return nil, err
		}
		out = append(out, withAsset)
	}
	return out, nil
}

func (s *Service) ListOwn(ctx context.Context, userID string, includeVerification bool) ([]*Item, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return s.ListForProfessional(ctx, prof.ID, includeVerification)
}

func (s *Service) withAsset(ctx context.Context, item *Item) (*Item, error) {
	asset, err := s.mediaSvc.Get(ctx, item.MediaAssetID)
	if err != nil {
		return nil, err
	}
	item.Asset = asset
	return item, nil
}

func (s *Service) Get(ctx context.Context, id string) (*Item, error) {
	item, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.withAsset(ctx, item)
}

// GetPublic returns a single active portfolio item (with its media asset)
// for public display, e.g. resolving a `/looks/{id}` deep link.
func (s *Service) GetPublic(ctx context.Context, id string) (*Item, error) {
	item, err := s.store.GetByIDActive(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.withAsset(ctx, item)
}
