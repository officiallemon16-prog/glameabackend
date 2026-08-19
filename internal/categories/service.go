package categories

import (
	"context"

	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store *Store
}

func NewService(store *Store) *Service {
	return &Service{store: store}
}

func (s *Service) List(ctx context.Context) ([]*Category, error) {
	return s.store.List(ctx, false)
}

func (s *Service) GetBySlug(ctx context.Context, slug string) (*Category, error) {
	return s.store.GetBySlug(ctx, slug)
}

func (s *Service) Create(ctx context.Context, in CreateInput) (*Category, error) {
	if in.Name == "" {
		return nil, httpx.BadRequest("name_required", "name is required")
	}
	if in.Slug == "" {
		in.Slug = Slugify(in.Name)
	}
	return s.store.Create(ctx, in)
}

func (s *Service) Update(ctx context.Context, id string, in CreateInput) (*Category, error) {
	existing, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if in.Name == "" {
		in.Name = existing.Name
	}
	if in.Slug == "" {
		in.Slug = existing.Slug
	}
	if in.Description == "" {
		in.Description = existing.Description
	}
	if in.IconMediaID == nil {
		in.IconMediaID = existing.IconMediaID
	}
	if in.DisplayOrder == 0 {
		in.DisplayOrder = existing.DisplayOrder
	}
	return s.store.Update(ctx, id, in)
}

func (s *Service) Delete(ctx context.Context, id string) error {
	return s.store.Delete(ctx, id)
}
