package platform

import (
	"context"
)

type Service struct {
	store *Store
}

func NewService(store *Store) *Service {
	return &Service{store: store}
}

func (s *Service) All(ctx context.Context) ([]*Setting, error) {
	return s.store.All(ctx)
}

func (s *Service) Get(ctx context.Context, name string) (*Setting, error) {
	return s.store.Get(ctx, name)
}

func (s *Service) Update(ctx context.Context, pairs map[string]string) error {
	return s.store.UpsertMany(ctx, pairs)
}
