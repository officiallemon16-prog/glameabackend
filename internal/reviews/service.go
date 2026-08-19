package reviews

import (
	"context"

	"github.com/glamea/glamea-backend/internal/bookings"
	"github.com/glamea/glamea-backend/internal/notifications"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store        *Store
	bookingStore *bookings.Store
	proStore     *professionals.Store
	notifier     *notifications.Service
}

func NewService(store *Store, bookingStore *bookings.Store, proStore *professionals.Store, notifier *notifications.Service) *Service {
	return &Service{store: store, bookingStore: bookingStore, proStore: proStore, notifier: notifier}
}

type CreateInput struct {
	BookingID string
	Rating    int
	Comment   string
}

func (s *Service) Create(ctx context.Context, customerID string, in CreateInput) (*Review, error) {
	if in.BookingID == "" {
		return nil, httpx.BadRequest("booking_required", "booking_id is required")
	}
	if in.Rating < 1 || in.Rating > 5 {
		return nil, httpx.BadRequest("invalid_rating", "rating must be between 1 and 5")
	}

	existing, err := s.store.GetByBookingID(ctx, in.BookingID)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, httpx.Conflict("review_exists", "this booking has already been reviewed")
	}

	b, err := s.bookingStore.GetByID(ctx, in.BookingID)
	if err != nil {
		return nil, err
	}
	if b.CustomerID != customerID {
		return nil, httpx.Forbidden("not_your_booking", "only the customer can review their booking")
	}
	if b.Status != bookings.StatusCompleted {
		return nil, httpx.Conflict("booking_not_completed", "only completed bookings can be reviewed")
	}

	rv, err := s.store.Create(ctx, Review{
		BookingID:      b.ID,
		ProfessionalID: b.ProfessionalID,
		CustomerID:     b.CustomerID,
		ServiceID:      &b.ServiceID,
		Rating:         in.Rating,
		Comment:        in.Comment,
	})
	if err != nil {
		return nil, err
	}
	if err := s.store.RecomputeProfessional(ctx, b.ProfessionalID); err != nil {
		return nil, err
	}
	_ = s.notifier.Notify(ctx, b.ProfessionalID, "review", "New review",
		"You received a new rating review.", map[string]any{"booking_id": b.ID, "rating": in.Rating})
	return rv, nil
}

func (s *Service) ListForProfessional(ctx context.Context, professionalID string, limit, offset int) ([]*Review, int64, error) {
	return s.store.ListForProfessional(ctx, professionalID, limit, offset)
}

func (s *Service) ListMineForPro(ctx context.Context, userID string, limit, offset int) ([]*Review, int64, error) {
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, 0, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return s.store.ListForProfessional(ctx, pro.ID, limit, offset)
}

func (s *Service) ListMineAsCustomer(ctx context.Context, userID string, limit, offset int) ([]*Review, int64, error) {
	return s.store.ListForCustomer(ctx, userID, limit, offset)
}

func (s *Service) Respond(ctx context.Context, userID, reviewID, response string) (*Review, error) {
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	rv, err := s.store.GetByID(ctx, reviewID)
	if err != nil {
		return nil, err
	}
	if rv.ProfessionalID != pro.ID {
		return nil, httpx.Forbidden("not_your_review", "you can only respond to reviews of your own services")
	}
	if response == "" {
		return nil, httpx.BadRequest("response_required", "response is required")
	}
	if err := s.store.Respond(ctx, reviewID, response); err != nil {
		return nil, err
	}
	return s.store.GetByID(ctx, reviewID)
}
