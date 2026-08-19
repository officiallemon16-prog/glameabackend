package disputes

import (
	"context"

	"github.com/glamea/glamea-backend/internal/bookings"
	"github.com/glamea/glamea-backend/internal/notifications"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/users"
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

func (s *Service) participantUserID(ctx context.Context, userID string, b *bookings.Booking) (string, error) {
	if b.CustomerID == userID {
		return b.CustomerID, nil
	}
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return "", httpx.Forbidden("not_participant", "you are not part of this booking")
	}
	if pro.ID != b.ProfessionalID {
		return "", httpx.Forbidden("not_participant", "you are not part of this booking")
	}
	return pro.UserID, nil
}

func (s *Service) Raise(ctx context.Context, userID string, in CreateInput) (*Dispute, error) {
	b, err := s.bookingStore.GetByID(ctx, in.BookingID)
	if err != nil {
		return nil, err
	}
	sender, err := s.participantUserID(ctx, userID, b)
	if err != nil {
		return nil, err
	}
	if b.Status == bookings.StatusCancelled {
		return nil, httpx.Conflict("booking_cancelled", "cannot raise a dispute for a cancelled booking")
	}
	d, err := s.store.Create(ctx, Dispute{
		BookingID:   in.BookingID,
		RaisedBy:    sender,
		Reason:      in.Reason,
		Description: in.Description,
	})
	if err != nil {
		return nil, err
	}
	// notify the other participant
	if sender == b.CustomerID {
		pro, err := s.proStore.GetByID(ctx, b.ProfessionalID)
		if err == nil {
			_ = s.notifier.Notify(ctx, pro.UserID, "dispute", "Dispute raised",
				"A dispute has been raised against one of your bookings.", map[string]any{"booking_id": b.ID, "dispute_id": d.ID})
		}
	} else {
		_ = s.notifier.Notify(ctx, b.CustomerID, "dispute", "Dispute raised",
			"A dispute has been raised regarding your booking.", map[string]any{"booking_id": b.ID, "dispute_id": d.ID})
	}
	return d, nil
}

func (s *Service) Get(ctx context.Context, userID string, role string, id string) (*Dispute, error) {
	d, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if role == users.RoleAdmin {
		return d, nil
	}
	b, err := s.bookingStore.GetByID(ctx, d.BookingID)
	if err != nil {
		return nil, err
	}
	if _, err := s.participantUserID(ctx, userID, b); err != nil {
		return nil, err
	}
	return d, nil
}

func (s *Service) Messages(ctx context.Context, userID, role, disputeID string) ([]*DisputeMessage, error) {
	if role == users.RoleAdmin {
		return s.store.ListMessages(ctx, disputeID)
	}
	d, err := s.store.GetByID(ctx, disputeID)
	if err != nil {
		return nil, err
	}
	// allow the raiser to always view
	if d.RaisedBy == userID {
		return s.store.ListMessages(ctx, disputeID)
	}
	b, err := s.bookingStore.GetByID(ctx, d.BookingID)
	if err != nil {
		return nil, err
	}
	if _, err := s.participantUserID(ctx, userID, b); err != nil {
		return nil, err
	}
	return s.store.ListMessages(ctx, disputeID)
}

func (s *Service) AddMessage(ctx context.Context, userID, role, disputeID, body string) (*DisputeMessage, error) {
	if body == "" {
		return nil, httpx.BadRequest("body_required", "message body is required")
	}
	d, err := s.store.GetByID(ctx, disputeID)
	if err != nil {
		return nil, err
	}
	if d.Status != StatusOpen {
		return nil, httpx.Conflict("dispute_closed", "dispute is not open")
	}
	if role == users.RoleAdmin {
		return s.store.AddMessage(ctx, disputeID, userID, body)
	}
	b, err := s.bookingStore.GetByID(ctx, d.BookingID)
	if err != nil {
		return nil, err
	}
	sender, err := s.participantUserID(ctx, userID, b)
	if err != nil {
		return nil, err
	}
	return s.store.AddMessage(ctx, disputeID, sender, body)
}

func (s *Service) Resolve(ctx context.Context, userID, disputeID, resolution string) (*Dispute, error) {
	d, err := s.store.Resolve(ctx, disputeID, resolution, userID)
	if err != nil {
		return nil, err
	}
	b, err := s.bookingStore.GetByID(ctx, d.BookingID)
	if err != nil {
		return nil, err
	}
	if d.RaisedBy == b.CustomerID {
		pro, err := s.proStore.GetByID(ctx, b.ProfessionalID)
		if err == nil {
			_ = s.notifier.Notify(ctx, pro.UserID, "dispute", "Dispute resolved",
				"The dispute on your booking has been resolved.", map[string]any{"booking_id": b.ID, "dispute_id": d.ID})
		}
	} else {
		_ = s.notifier.Notify(ctx, b.CustomerID, "dispute", "Dispute resolved",
			"The dispute on your booking has been resolved.", map[string]any{"booking_id": b.ID, "dispute_id": d.ID})
	}
	return d, nil
}

func (s *Service) ListMine(ctx context.Context, userID string, limit, offset int) ([]*Dispute, int64, error) {
	return s.store.ListForUser(ctx, userID, limit, offset)
}

func (s *Service) ListAll(ctx context.Context, status string, limit, offset int) ([]*Dispute, int64, error) {
	return s.store.ListAll(ctx, status, limit, offset)
}

type CreateInput struct {
	BookingID   string `json:"booking_id"`
	Reason      string `json:"reason"`
	Description string `json:"description,omitempty"`
}
