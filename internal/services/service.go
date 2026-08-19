package services

import (
	"context"

	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type ServiceService struct {
	store    *Store
	proStore *professionals.Store
}

func NewService(store *Store, proStore *professionals.Store) *ServiceService {
	return &ServiceService{store: store, proStore: proStore}
}

func (s *ServiceService) Create(ctx context.Context, userID string, in CreateInput) (*Service, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if in.Name == "" {
		return nil, httpx.BadRequest("name_required", "service name is required")
	}
	if in.BasePrice < 0 {
		return nil, httpx.BadRequest("invalid_price", "base price cannot be negative")
	}
	if in.DurationMinutes <= 0 {
		return nil, httpx.BadRequest("invalid_duration", "duration must be positive")
	}
	if in.Currency == "" {
		in.Currency = "NGN"
	}
	in.ProfessionalID = prof.ID
	return s.store.Create(ctx, in)
}

func (s *ServiceService) Get(ctx context.Context, id string) (*Service, error) {
	return s.store.GetByID(ctx, id)
}

func (s *ServiceService) Update(ctx context.Context, userID, serviceID string, in CreateInput) (*Service, error) {
	svc, err := s.store.GetByID(ctx, serviceID)
	if err != nil {
		return nil, err
	}
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if svc.ProfessionalID != prof.ID {
		return nil, httpx.Forbidden("not_your_service", "you can only update your own services")
	}
	if in.Name == "" {
		in.Name = svc.Name
	}
	if in.Currency == "" {
		in.Currency = svc.Currency
	}
	return s.store.Update(ctx, serviceID, in)
}

func (s *ServiceService) Delete(ctx context.Context, userID, serviceID string) error {
	svc, err := s.store.GetByID(ctx, serviceID)
	if err != nil {
		return err
	}
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if svc.ProfessionalID != prof.ID {
		return httpx.Forbidden("not_your_service", "you can only delete your own services")
	}
	return s.store.Delete(ctx, serviceID)
}

func (s *ServiceService) List(ctx context.Context, filter ListFilter) ([]*Service, int64, error) {
	if filter.Limit == 0 {
		filter.Limit = 50
	}
	if filter.Limit > 100 {
		filter.Limit = 100
	}
	return s.store.List(ctx, filter)
}
