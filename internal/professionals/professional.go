package professionals

import "time"

const (
	StatusPending     = "PENDING"
	StatusActive      = "ACTIVE"
	StatusSuspended   = "SUSPENDED"
	StatusDeactivated = "DEACTIVATED"
)

const (
	VerificationUnverified = "UNVERIFIED"
	VerificationPending    = "PENDING"
	VerificationVerified   = "VERIFIED"
	VerificationRejected   = "REJECTED"
)

type Professional struct {
	ID                 string    `json:"id"`
	UserID             string    `json:"user_id"`
	BusinessName       string    `json:"business_name"`
	DisplayName        string    `json:"display_name,omitempty"`
	Bio                string    `json:"bio,omitempty"`
	CategoryID         *string   `json:"category_id,omitempty"`
	ExperienceYears    *int      `json:"experience_years,omitempty"`
	Rating             float64   `json:"rating"`
	ReviewCount        int       `json:"review_count"`
	BookingCount       int       `json:"booking_count"`
	CompletionRate     float64   `json:"completion_rate"`
	Status             string    `json:"status"`
	VerificationStatus string    `json:"verification_status"`
	TrustScore         float64   `json:"trust_score"`
	Latitude           *float64  `json:"latitude,omitempty"`
	Longitude          *float64  `json:"longitude,omitempty"`
	AddressLine        string    `json:"address_line,omitempty"`
	City               string    `json:"city,omitempty"`
	Country            string    `json:"country,omitempty"`
	Timezone           string    `json:"timezone,omitempty"`
	HomeServiceEnabled bool      `json:"home_service_enabled"`
	ServiceRadiusKm    *float64  `json:"service_radius_km,omitempty"`
	TravelFeePerKm     float64   `json:"travel_fee_per_km"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type PublicProfile struct {
	Professional
	User struct {
		FirstName     string  `json:"first_name"`
		LastName      string  `json:"last_name"`
		AvatarMediaID *string `json:"avatar_media_id"`
	} `json:"user"`
}
