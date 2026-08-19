package availability

import (
	"context"
	"time"

	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store    *Store
	proStore *professionals.Store
}

func NewService(store *Store, proStore *professionals.Store) *Service {
	return &Service{store: store, proStore: proStore}
}

func (s *Service) SetWindows(ctx context.Context, userID string, in []WindowInput) ([]*Window, error) {
	prof, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	for _, w := range in {
		if w.DayOfWeek < 0 || w.DayOfWeek > 6 {
			return nil, httpx.BadRequest("invalid_day_of_week", "day_of_week must be between 0 and 6")
		}
		if w.StartMinutes < 0 || w.EndMinutes > 1440 || w.EndMinutes <= w.StartMinutes {
			return nil, httpx.BadRequest("invalid_window", "invalid window; end_minutes must be greater than start_minutes and within 0..1440")
		}
	}
	return s.store.ReplaceWindows(ctx, prof.ID, in)
}

func (s *Service) ListWindows(ctx context.Context, professionalID string) ([]*Window, error) {
	if _, err := s.proStore.GetByID(ctx, professionalID); err != nil {
		return nil, err
	}
	return s.store.ListWindows(ctx, professionalID, false)
}

func (s *Service) ListMyWindows(ctx context.Context, userID string) ([]*Window, error) {
	prof, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.store.ListWindows(ctx, prof.ID, true)
}

func (s *Service) AddException(ctx context.Context, userID string, in ExceptionInput) (*Exception, error) {
	prof, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	if _, err := time.Parse("2006-01-02", in.Date); err != nil {
		return nil, httpx.BadRequest("invalid_date", "date must be in YYYY-MM-DD format")
	}
	if !in.IsAvailable && in.StartMinutes == nil {
		return nil, httpx.BadRequest("block_required", "blocked exceptions must include start_minutes and end_minutes")
	}
	return s.store.CreateException(ctx, prof.ID, in)
}

func (s *Service) ListMyExceptions(ctx context.Context, userID, fromDate string) ([]*Exception, error) {
	prof, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.store.ListExceptions(ctx, prof.ID, fromDate)
}

func (s *Service) DeleteException(ctx context.Context, userID, id string) error {
	prof, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return err
	}
	return s.store.DeleteException(ctx, prof.ID, id)
}

func (s *Service) requireProfessional(ctx context.Context, userID string) (*professionals.Professional, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return prof, nil
}
