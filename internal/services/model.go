package services

import "time"

type Service struct {
	ID                   string           `json:"id"`
	ProfessionalID       string           `json:"professional_id"`
	CategoryID           *string          `json:"category_id,omitempty"`
	Name                 string           `json:"name"`
	Description          string           `json:"description,omitempty"`
	BasePrice            float64          `json:"base_price"`
	Currency             string           `json:"currency"`
	DurationMinutes      int              `json:"duration_minutes"`
	DepositPercentage    float64          `json:"deposit_percentage"`
	HomeServiceAvailable bool             `json:"home_service_available"`
	CancellationPolicyID *string          `json:"cancellation_policy_id,omitempty"`
	DisplayOrder         int              `json:"display_order"`
	IsActive             bool             `json:"is_active"`
	Variants             []ServiceVariant `json:"variants,omitempty"`
	CreatedAt            time.Time        `json:"created_at"`
	UpdatedAt            time.Time        `json:"updated_at"`
}

type ServiceVariant struct {
	ID                   string  `json:"id"`
	ServiceID            string  `json:"service_id"`
	Name                 string  `json:"name"`
	PriceDelta           float64 `json:"price_delta"`
	DurationDeltaMinutes int     `json:"duration_delta_minutes"`
	IsActive             bool    `json:"is_active"`
}

type CreateInput struct {
	ProfessionalID       string
	CategoryID           *string
	Name                 string
	Description          string
	BasePrice            float64
	Currency             string
	DurationMinutes      int
	DepositPercentage    float64
	HomeServiceAvailable bool
	CancellationPolicyID *string
	DisplayOrder         int
	Variants             []VariantInput
}

type VariantInput struct {
	Name                 string
	PriceDelta           float64
	DurationDeltaMinutes int
}
