package deals

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

func (s *Service) requirePro(ctx context.Context, userID string) (*professionals.Professional, error) {
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return pro, nil
}

func (s *Service) Create(ctx context.Context, userID string, in CreateInput) (*Deal, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	if in.Name == "" {
		return nil, httpx.BadRequest("name_required", "deal name is required")
	}
	if in.DiscountType == "" {
		in.DiscountType = DiscountPercent
	}
	if in.DiscountType != DiscountPercent && in.DiscountType != DiscountFixed {
		return nil, httpx.BadRequest("invalid_discount_type", "discount_type must be PERCENT or FIXED")
	}
	if in.DiscountValue <= 0 {
		return nil, httpx.BadRequest("invalid_discount", "discount_value must be positive")
	}
	if in.DiscountType == DiscountPercent && in.DiscountValue > 100 {
		return nil, httpx.BadRequest("invalid_discount", "percent discount cannot exceed 100")
	}
	return s.store.Create(ctx, Deal{
		ProfessionalID: pro.ID,
		Name:           in.Name,
		Description:    in.Description,
		Code:           in.Code,
		DiscountType:   in.DiscountType,
		DiscountValue:  in.DiscountValue,
		MinOrderAmount: in.MinOrderAmount,
		UsageLimit:     in.UsageLimit,
		StartsAt:       in.StartsAt,
		EndsAt:         in.EndsAt,
		ServiceIDs:     in.ServiceIDs,
	})
}

func (s *Service) Update(ctx context.Context, userID, dealID string, in UpdateInput) (*Deal, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, err
	}
	d, err := s.store.GetByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if d.ProfessionalID != pro.ID {
		return nil, httpx.Forbidden("not_your_deal", "this deal belongs to another professional")
	}
	return s.store.Update(ctx, dealID, func(upd *Deal) {
		if in.Name != nil {
			upd.Name = *in.Name
		}
		if in.Description != nil {
			upd.Description = *in.Description
		}
		if in.DiscountType != nil {
			upd.DiscountType = *in.DiscountType
		}
		if in.DiscountValue != nil {
			upd.DiscountValue = *in.DiscountValue
		}
		if in.MinOrderAmount != nil {
			upd.MinOrderAmount = *in.MinOrderAmount
		}
		if in.UsageLimit != nil {
			upd.UsageLimit = in.UsageLimit
		}
		if in.StartsAt != nil {
			upd.StartsAt = in.StartsAt
		}
		if in.EndsAt != nil {
			upd.EndsAt = in.EndsAt
		}
		if in.IsActive != nil {
			upd.IsActive = *in.IsActive
		}
	})
}

func (s *Service) Deactivate(ctx context.Context, userID, dealID string) error {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return err
	}
	d, err := s.store.GetByID(ctx, dealID)
	if err != nil {
		return err
	}
	if d.ProfessionalID != pro.ID {
		return httpx.Forbidden("not_your_deal", "this deal belongs to another professional")
	}
	return s.store.SetActive(ctx, dealID, false)
}

func (s *Service) Get(ctx context.Context, id string) (*Deal, error) {
	return s.store.GetByID(ctx, id)
}

func (s *Service) ListActive(ctx context.Context, limit, offset int) ([]*Deal, int64, error) {
	return s.store.ListActive(ctx, limit, offset)
}

func (s *Service) ListMine(ctx context.Context, userID string, limit, offset int) ([]*Deal, int64, error) {
	pro, err := s.requirePro(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	return s.store.ListForProfessional(ctx, pro.ID, limit, offset)
}

func (s *Service) ListAll(ctx context.Context, active string, limit, offset int) ([]*Deal, int64, error) {
	return s.store.ListAll(ctx, active, limit, offset)
}

func (s *Service) Toggle(ctx context.Context, dealID string, active bool) (*Deal, error) {
	if err := s.store.SetActive(ctx, dealID, active); err != nil {
		return nil, err
	}
	return s.store.GetByID(ctx, dealID)
}

type CreateInput struct {
	Name           string     `json:"name"`
	Description    string     `json:"description,omitempty"`
	Code           string     `json:"code,omitempty"`
	DiscountType   string     `json:"discount_type"`
	DiscountValue  float64    `json:"discount_value"`
	MinOrderAmount float64    `json:"min_order_amount,omitempty"`
	UsageLimit     *int       `json:"usage_limit,omitempty"`
	StartsAt       *time.Time `json:"starts_at,omitempty"`
	EndsAt         *time.Time `json:"ends_at,omitempty"`
	ServiceIDs     []string   `json:"service_ids,omitempty"`
}

type UpdateInput struct {
	Name           *string    `json:"name,omitempty"`
	Description    *string    `json:"description,omitempty"`
	DiscountType   *string    `json:"discount_type,omitempty"`
	DiscountValue  *float64   `json:"discount_value,omitempty"`
	MinOrderAmount *float64   `json:"min_order_amount,omitempty"`
	UsageLimit     *int       `json:"usage_limit,omitempty"`
	StartsAt       *time.Time `json:"starts_at,omitempty"`
	EndsAt         *time.Time `json:"ends_at,omitempty"`
	IsActive       *bool      `json:"is_active,omitempty"`
}
