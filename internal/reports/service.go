package reports

import (
	"context"
	"time"
)

type Service struct {
	store *Store
}

func NewService(store *Store) *Service {
	return &Service{store: store}
}

func (s *Service) Bookings(ctx context.Context, from, to string, limit, offset int) ([]*BookingRow, int64, error) {
	return s.store.Bookings(ctx, from, to, limit, offset)
}

func (s *Service) Payments(ctx context.Context, from, to string, limit, offset int) ([]*PaymentRow, int64, error) {
	return s.store.Payments(ctx, from, to, limit, offset)
}

func (s *Service) Payouts(ctx context.Context, from, to string, limit, offset int) ([]*PayoutRow, int64, error) {
	return s.store.Payouts(ctx, from, to, limit, offset)
}

func DefaultRange() (string, string) {
	to := time.Now().Add(24 * time.Hour).Format("2006-01-02")
	from := time.Now().AddDate(0, -1, 0).Format("2006-01-02")
	return from, to
}
