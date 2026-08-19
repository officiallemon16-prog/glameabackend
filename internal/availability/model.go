package availability

import "time"

const (
	ExceptionBlocked = 0
	ExceptionOpen    = 1
)

type Window struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id"`
	DayOfWeek      int       `json:"day_of_week"`
	StartMinutes   int       `json:"start_minutes"`
	EndMinutes     int       `json:"end_minutes"`
	IsActive       bool      `json:"is_active"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type Exception struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id"`
	Date           string    `json:"date"`
	StartMinutes   *int      `json:"start_minutes,omitempty"`
	EndMinutes     *int      `json:"end_minutes,omitempty"`
	IsAvailable    bool      `json:"is_available"`
	Note           string    `json:"note,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

type WindowInput struct {
	DayOfWeek    int `json:"day_of_week"`
	StartMinutes int `json:"start_minutes"`
	EndMinutes   int `json:"end_minutes"`
}

type ExceptionInput struct {
	Date         string `json:"date"`
	StartMinutes *int   `json:"start_minutes"`
	EndMinutes   *int   `json:"end_minutes"`
	IsAvailable  bool   `json:"is_available"`
	Note         string `json:"note"`
}
