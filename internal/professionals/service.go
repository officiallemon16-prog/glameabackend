package professionals

import (
	"context"

	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store *Store
	users *users.Store
}

func NewService(store *Store, users *users.Store) *Service {
	return &Service{store: store, users: users}
}

type ProfileInput struct {
	BusinessName       string
	DisplayName        string
	Bio                string
	CategoryID         *string
	ExperienceYears    *int
	Latitude           *float64
	Longitude          *float64
	AddressLine        string
	City               string
	Country            string
	Timezone           string
	HomeServiceEnabled bool
	ServiceRadiusKm    *float64
	TravelFeePerKm     float64
}

func (s *Service) Create(ctx context.Context, userID string, in ProfileInput) (*Professional, error) {
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if u.Role != users.RoleProfessional {
		return nil, httpx.Forbidden("professional_required", "only PROFESSIONAL accounts can create a professional profile")
	}
	if in.BusinessName == "" {
		return nil, httpx.BadRequest("business_name_required", "business name is required")
	}

	existing, err := s.store.GetByUserID(ctx, userID)
	if err == nil {
		return existing, nil
	}

	p := &Professional{
		UserID:             userID,
		BusinessName:       in.BusinessName,
		DisplayName:        in.DisplayName,
		Bio:                in.Bio,
		CategoryID:         in.CategoryID,
		ExperienceYears:    in.ExperienceYears,
		Status:             StatusPending,
		VerificationStatus: VerificationUnverified,
		Country:            "NG",
		City:               in.City,
		AddressLine:        in.AddressLine,
		Timezone:           in.Timezone,
		HomeServiceEnabled: in.HomeServiceEnabled,
		ServiceRadiusKm:    in.ServiceRadiusKm,
		TravelFeePerKm:     in.TravelFeePerKm,
	}
	return s.store.Create(ctx, p)
}

func (s *Service) GetOwn(ctx context.Context, userID string) (*Professional, error) {
	return s.store.GetByUserID(ctx, userID)
}

func (s *Service) UpdateOwn(ctx context.Context, userID string, in ProfileInput) (*Professional, error) {
	p, err := s.store.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.store.Update(ctx, p.ID, func(prof *Professional) {
		if in.BusinessName != "" {
			prof.BusinessName = in.BusinessName
		}
		if in.DisplayName != "" {
			prof.DisplayName = in.DisplayName
		}
		if in.Bio != "" {
			prof.Bio = in.Bio
		}
		if in.CategoryID != nil {
			prof.CategoryID = in.CategoryID
		}
		if in.ExperienceYears != nil {
			prof.ExperienceYears = in.ExperienceYears
		}
		if in.Latitude != nil {
			prof.Latitude = in.Latitude
		}
		if in.Longitude != nil {
			prof.Longitude = in.Longitude
		}
		if in.AddressLine != "" {
			prof.AddressLine = in.AddressLine
		}
		if in.City != "" {
			prof.City = in.City
		}
		if in.Country != "" {
			prof.Country = in.Country
		}
		if in.Timezone != "" {
			prof.Timezone = in.Timezone
		}
		prof.HomeServiceEnabled = in.HomeServiceEnabled
		if in.ServiceRadiusKm != nil {
			prof.ServiceRadiusKm = in.ServiceRadiusKm
		}
		if in.TravelFeePerKm > 0 {
			prof.TravelFeePerKm = in.TravelFeePerKm
		}
	})
}

func (s *Service) GetPublic(ctx context.Context, id string) (*PublicProfile, error) {
	return s.store.PublicProfile(ctx, id)
}

func (s *Service) List(ctx context.Context, filter ListFilter) ([]*Professional, int64, error) {
	if filter.Limit == 0 {
		filter.Limit = 20
	}
	if filter.Limit > 100 {
		filter.Limit = 100
	}
	return s.store.List(ctx, filter)
}
