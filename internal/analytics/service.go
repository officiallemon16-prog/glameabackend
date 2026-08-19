package analytics

import (
	"context"
)

type Service struct {
	store *Store
}

func NewService(store *Store) *Service {
	return &Service{store: store}
}

func (s *Service) Summary(ctx context.Context, from, to string) (*Summary, error) {
	return s.store.Summary(ctx, from, to)
}

func (s *Service) Trends(ctx context.Context, from, to string) ([]*BookingTrend, error) {
	return s.store.Trends(ctx, from, to)
}

func (s *Service) RevenueByService(ctx context.Context, from, to string) ([]*ServiceRevenue, error) {
	return s.store.RevenueByService(ctx, from, to)
}

func (s *Service) TopProfessionals(ctx context.Context, from, to string, limit int) ([]*ProPerformance, error) {
	return s.store.TopProfessionals(ctx, from, to, limit)
}
