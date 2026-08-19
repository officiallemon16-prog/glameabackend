package bookings

import "time"

const (
	StatusPending    = "PENDING"
	StatusConfirmed  = "CONFIRMED"
	StatusInProgress = "IN_PROGRESS"
	StatusCompleted  = "COMPLETED"
	StatusCancelled  = "CANCELLED"
	StatusNoShow     = "NO_SHOW"
)

type Booking struct {
	ID                   string     `json:"id"`
	ProfessionalID       string     `json:"professional_id"`
	CustomerID           string     `json:"customer_id"`
	ServiceID            string     `json:"service_id"`
	VariantID            *string    `json:"variant_id,omitempty"`
	Status               string     `json:"status"`
	StartAt              time.Time  `json:"start_at"`
	EndAt                time.Time  `json:"end_at"`
	BaseAmount           float64    `json:"base_amount"`
	TotalAmount          float64    `json:"total_amount"`
	DepositAmount        float64    `json:"deposit_amount"`
	Currency             string     `json:"currency"`
	HomeService          bool       `json:"home_service"`
	LocationLat          *float64   `json:"location_lat,omitempty"`
	LocationLng          *float64   `json:"location_lng,omitempty"`
	LocationAddress      string     `json:"location_address,omitempty"`
	CustomerNotes        string     `json:"customer_notes,omitempty"`
	CancellationPolicyID *string    `json:"cancellation_policy_id,omitempty"`
	CancelledAt          *time.Time `json:"cancelled_at,omitempty"`
	CancelledBy          *string    `json:"cancelled_by,omitempty"`
	CancelReason         string     `json:"cancel_reason,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`

	// BalanceAmount is the outstanding amount after subtracting every SUCCEEDED
	// payment intent for the booking. Populated by the service layer (it is not
	// stored on the row), so the UI never derives it from total - deposit and
	// misses partial payments.
	BalanceAmount float64 `json:"balance_amount"`

	ServiceName      string `json:"service_name"`
	ProfessionalName string `json:"professional_name"`
	CustomerName     string `json:"customer_name"`
}

type StatusEvent struct {
	ID         string    `json:"id"`
	BookingID  string    `json:"booking_id"`
	FromStatus string    `json:"from_status,omitempty"`
	ToStatus   string    `json:"to_status"`
	ChangedBy  *string   `json:"changed_by,omitempty"`
	Note       string    `json:"note,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type Slot struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}
