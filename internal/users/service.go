package users

import (
	"context"

	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store *Store
}

func NewService(store *Store) *Service {
	return &Service{store: store}
}

type UpdateProfileInput struct {
	FirstName     string
	LastName      string
	AvatarMediaID *string
	Email         string
}

func (s *Service) GetCurrent(ctx context.Context, userID string) (*User, error) {
	return s.store.GetByID(ctx, userID)
}

func (s *Service) UpdateProfile(ctx context.Context, userID string, in UpdateProfileInput) (*User, error) {
	if in.FirstName == "" && in.LastName == "" && in.AvatarMediaID == nil && in.Email == "" {
		return nil, httpx.BadRequest("nothing_to_update", "no fields to update")
	}

	if in.Email != "" {
		existing, err := s.store.GetByEmail(ctx, in.Email)
		if err == nil && existing.ID != userID {
			return nil, httpx.Conflict("email_taken", "email is already registered")
		}
	}

	return s.store.Update(ctx, userID, func(u *User) {
		if in.FirstName != "" {
			u.FirstName = in.FirstName
		}
		if in.LastName != "" {
			u.LastName = in.LastName
		}
		if in.AvatarMediaID != nil {
			u.AvatarMediaID = in.AvatarMediaID
		}
		if in.Email != "" {
			e := in.Email
			u.Email = &e
		}
	})
}
