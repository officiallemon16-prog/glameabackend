package notifications

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/glamea/glamea-backend/pkg/fcm"
)

// Pusher delivers push messages to a single device.
type Pusher interface {
	Send(ctx context.Context, in fcm.SendInput) error
}

type Service struct {
	store  *Store
	pusher Pusher
}

func NewService(store *Store, pusher Pusher) *Service {
	return &Service{store: store, pusher: pusher}
}

func (s *Service) Notify(ctx context.Context, userID, notifType, title, body string, data any) error {
	return s.NotifyReturning(ctx, userID, notifType, title, body, data)
}

func (s *Service) NotifyReturning(ctx context.Context, userID, notifType, title, body string, data any) error {
	if userID == "" {
		return nil
	}
	_, err := s.store.Create(ctx, userID, notifType, title, body, data)
	if err != nil {
		return err
	}
	s.push(ctx, userID, notifType, title, body, data)
	return nil
}

// push fans a notification out to every registered device for the user.
// Delivery is best-effort and asynchronous with a bounded worker pool.
func (s *Service) push(ctx context.Context, userID, notifType, title, body string, data any) {
	if s.pusher == nil {
		return
	}
	tokens, err := s.store.ListTokensForUser(ctx, userID)
	if err != nil || len(tokens) == 0 {
		return
	}
	dataMap := stringifyData(data)
	go func() {
		const maxConcurrent = 5
		sem := make(chan struct{}, maxConcurrent)
		for _, tok := range tokens {
			tok := tok
			sem <- struct{}{}
			go func() {
				defer func() { <-sem }()
				defer func() { _ = recover() }()
				pushCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
				defer cancel()
				if err := s.pusher.Send(pushCtx, fcm.SendInput{Token: tok, Title: title, Body: body, Type: notifType, Data: dataMap}); err != nil {
					if errors.Is(err, fcm.ErrTokenUnregistered) {
						_ = s.store.DisableDevice(context.WithoutCancel(ctx), tok)
					}
				}
			}()
		}
	}()
}

func stringifyData(data any) map[string]string {
	switch v := data.(type) {
	case nil:
		return nil
	case map[string]string:
		return v
	case map[string]any:
		out := make(map[string]string, len(v))
		for k, val := range v {
			out[k] = fmt.Sprint(val)
		}
		return out
	default:
		return map[string]string{"value": fmt.Sprint(data)}
	}
}

// RegisterDevice upserts a device push token for the authenticated user.
func (s *Service) RegisterDevice(ctx context.Context, userID, token, platform string) (*DeviceToken, error) {
	return s.store.RegisterDevice(ctx, userID, token, platform)
}

// RemoveDevice deletes a device push token (logout).
func (s *Service) RemoveDevice(ctx context.Context, userID, token string) error {
	return s.store.RemoveDevice(ctx, userID, token)
}

func (s *Service) List(ctx context.Context, userID string, limit, offset int) ([]*Notification, int64, error) {
	return s.store.ListForUser(ctx, userID, limit, offset)
}

func (s *Service) UnreadCount(ctx context.Context, userID string) (int64, error) {
	return s.store.UnreadCount(ctx, userID)
}

func (s *Service) MarkRead(ctx context.Context, userID, id string) error {
	return s.store.MarkRead(ctx, userID, id)
}

func (s *Service) MarkAllRead(ctx context.Context, userID string) error {
	return s.store.MarkAllRead(ctx, userID)
}
