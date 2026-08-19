package messaging

import (
	"context"
	"math"
	"strings"
	"time"

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
	hub          *Hub
}

func NewService(store *Store, bookingStore *bookings.Store, proStore *professionals.Store, notifier *notifications.Service) *Service {
	return &Service{store: store, bookingStore: bookingStore, proStore: proStore, notifier: notifier}
}

// SetHub attaches the realtime hub so messages are pushed live over websocket.
func (s *Service) SetHub(hub *Hub) {
	s.hub = hub
}

// SendInput describes a message to persist. Depending on Type only the
// relevant fields are required and validated.
type SendInput struct {
	Body         string
	Type         string
	MediaAssetID *string
	MediaURL     string
	MimeType     string
	DurationMs   *int
	Width        *int
	Height       *int
	Latitude     *float64
	Longitude    *float64
	Address      string
	CallType     string
	CallStatus   string
}

func (s *Service) requireParticipant(ctx context.Context, userID string, b *bookings.Booking) (string, error) {
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

func (s *Service) Send(ctx context.Context, userID, bookingID string, in SendInput) (*Message, error) {
	normalized, err := validateSendInput(in)
	if err != nil {
		return nil, err
	}

	b, err := s.bookingStore.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	senderUserID, err := s.requireParticipant(ctx, userID, b)
	if err != nil {
		return nil, err
	}

	pro, err := s.proStore.GetByID(ctx, b.ProfessionalID)
	if err != nil {
		return nil, err
	}

	conv, err := s.store.GetOrCreate(ctx, b.ID, b.CustomerID, pro.ID)
	if err != nil {
		return nil, err
	}

	recipient := pro.UserID
	if senderUserID == pro.UserID {
		recipient = b.CustomerID
	}

	msg, err := s.store.AddMessage(ctx, NewMessage{
		ConversationID: conv.ID,
		SenderID:       senderUserID,
		RecipientID:    recipient,
		Body:           normalized.Body,
		Type:           normalized.Type,
		MediaAssetID:   normalized.MediaAssetID,
		MediaURL:       normalized.MediaURL,
		MimeType:       normalized.MimeType,
		DurationMs:     normalized.DurationMs,
		Width:          normalized.Width,
		Height:         normalized.Height,
		Latitude:       normalized.Latitude,
		Longitude:      normalized.Longitude,
		Address:        normalized.Address,
		CallType:       normalized.CallType,
		CallStatus:     normalized.CallStatus,
		Preview:        previewFor(normalized),
	})
	if err != nil {
		return nil, err
	}

	if s.hub != nil {
		s.hub.BroadcastMessage(senderUserID, recipient, msg)
	}
	_ = s.notifier.Notify(ctx, recipient, "message", "New message",
		"You have a new message regarding your booking.",
		map[string]any{"booking_id": b.ID, "conversation_id": conv.ID, "message_type": msg.Type})
	return msg, nil
}

func (s *Service) ConversationForBooking(ctx context.Context, userID, bookingID string) (*Conversation, error) {
	b, err := s.bookingStore.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if _, err := s.requireParticipant(ctx, userID, b); err != nil {
		return nil, err
	}
	pro, err := s.proStore.GetByID(ctx, b.ProfessionalID)
	if err != nil {
		return nil, err
	}
	return s.store.GetOrCreate(ctx, b.ID, b.CustomerID, pro.ID)
}

func (s *Service) Messages(ctx context.Context, userID, bookingID string, limit, offset int, before *time.Time, beforeID string) ([]*Message, int64, error) {
	conv, err := s.ConversationForBooking(ctx, userID, bookingID)
	if err != nil {
		return nil, 0, err
	}
	return s.store.ListMessages(ctx, conv.ID, limit, offset, before, beforeID)
}

func (s *Service) ListConversations(ctx context.Context, userID string, limit, offset int) ([]*Conversation, int64, error) {
	return s.store.ListForUser(ctx, userID, "", limit, offset)
}

func (s *Service) UnreadTotal(ctx context.Context, userID string) (int64, error) {
	return s.store.UnreadTotal(ctx, userID)
}

func (s *Service) MarkRead(ctx context.Context, userID, bookingID string) error {
	conv, err := s.ConversationForBooking(ctx, userID, bookingID)
	if err != nil {
		return err
	}
	return s.store.MarkRead(ctx, conv.ID, userID)
}

// validateSendInput normalizes the message type and enforces the required
// fields per type so the DB never stores an inconsistent message.
func validateSendInput(in SendInput) (SendInput, error) {
	normalized := in
	normalized.Type = strings.ToUpper(strings.TrimSpace(in.Type))
	if normalized.Type == "" {
		normalized.Type = TypeText
	}
	normalized.Body = strings.TrimSpace(in.Body)
	normalized.MediaURL = strings.TrimSpace(in.MediaURL)

	switch normalized.Type {
	case TypeText:
		if normalized.Body == "" {
			return SendInput{}, httpx.BadRequest("body_required", "message body is required")
		}
	case TypeImage, TypeVoice, TypeVideo:
		if normalized.MediaURL == "" {
			return SendInput{}, httpx.BadRequest("media_required", "a media file is required for this message")
		}
	case TypeLocation:
		if normalized.Latitude == nil || normalized.Longitude == nil ||
			math.IsNaN(*normalized.Latitude) || math.IsNaN(*normalized.Longitude) {
			return SendInput{}, httpx.BadRequest("location_required", "a valid location is required")
		}
	case TypeCall:
		ct := strings.ToUpper(normalized.CallType)
		if ct != "VOICE" && ct != "VIDEO" {
			return SendInput{}, httpx.BadRequest("call_type_required", "call_type must be VOICE or VIDEO")
		}
		normalized.CallType = ct
		if cs := strings.ToUpper(normalized.CallStatus); cs != "" {
			if cs != "MISSED" && cs != "ANSWERED" && cs != "DECLINED" {
				return SendInput{}, httpx.BadRequest("invalid_call_status", "call_status must be MISSED, ANSWERED or DECLINED")
			}
			normalized.CallStatus = cs
		}
	default:
		return SendInput{}, httpx.BadRequest("invalid_message_type", "unsupported message type")
	}
	return normalized, nil
}

// previewFor produces the conversation list preview text for any message type.
func previewFor(in SendInput) string {
	switch in.Type {
	case TypeImage:
		return "📷 Photo"
	case TypeVoice:
		return "🎤 Voice message"
	case TypeVideo:
		return "🎬 Video message"
	case TypeLocation:
		return "📍 Location"
	case TypeCall:
		label := "📞 Call"
		if in.CallType == "VIDEO" {
			label = "📹 Video call"
		}
		if in.CallStatus == "MISSED" {
			return "Missed " + label
		}
		return label
	default:
		return in.Body
	}
}
