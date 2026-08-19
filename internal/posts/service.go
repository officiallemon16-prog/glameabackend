package posts

import (
	"context"
	"strings"

	"github.com/glamea/glamea-backend/internal/categories"
	"github.com/glamea/glamea-backend/internal/media"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store    *Store
	proStore *professionals.Store
	catStore *categories.Store
	mediaSvc *media.Service
}

func NewService(store *Store, proStore *professionals.Store, catStore *categories.Store, mediaSvc *media.Service) *Service {
	return &Service{store: store, proStore: proStore, catStore: catStore, mediaSvc: mediaSvc}
}

type CreateInput struct {
	CategoryID *string
	Caption    string
	Location   string
	Sponsored  bool
	Images     []string
}

func (s *Service) Create(ctx context.Context, userID string, in CreateInput) (*Post, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if len(in.Images) == 0 {
		return nil, httpx.BadRequest("images_required", "at least one image is required")
	}
	urls, err := s.resolveImages(ctx, userID, in.Images)
	if err != nil {
		return nil, err
	}
	if in.CategoryID != nil && *in.CategoryID != "" {
		if _, err := s.catStore.GetByID(ctx, *in.CategoryID); err != nil {
			return nil, err
		}
	}

	post := Post{
		ProfessionalID: prof.ID,
		CategoryID:     in.CategoryID,
		Caption:        strings.TrimSpace(in.Caption),
		Location:       strings.TrimSpace(in.Location),
		Sponsored:      in.Sponsored,
	}
	created, err := s.store.Create(ctx, post)
	if err != nil {
		return nil, err
	}
	if err := s.store.SetImages(ctx, created.ID, urls); err != nil {
		return nil, err
	}
	return created, nil
}

func (s *Service) Feed(ctx context.Context, f FeedFilter) ([]*FeedPost, int64, error) {
	if f.Limit <= 0 || f.Limit > 100 {
		f.Limit = 30
	}
	return s.store.ListFeed(ctx, f)
}

func (s *Service) Get(ctx context.Context, id string) (*FeedPost, error) {
	return s.store.FeedPostByID(ctx, id)
}

// Like favorites a post for the user.
func (s *Service) Like(ctx context.Context, userID, postID string) error {
	return s.store.Like(ctx, userID, postID)
}

// Unlike removes a post from the user's favorites.
func (s *Service) Unlike(ctx context.Context, userID, postID string) error {
	return s.store.Unlike(ctx, userID, postID)
}

// LikedBy returns the user's favorited posts, newest like first.
func (s *Service) LikedBy(ctx context.Context, userID string, f FeedFilter) ([]*FeedPost, int64, error) {
	if f.Limit <= 0 || f.Limit > 100 {
		f.Limit = 30
	}
	return s.store.ListLiked(ctx, userID, f)
}

// Save bookmarks a post for the user.
func (s *Service) Save(ctx context.Context, userID, postID string) error {
	return s.store.Save(ctx, userID, postID)
}

// Unsave removes a post from the user's bookmarks.
func (s *Service) Unsave(ctx context.Context, userID, postID string) error {
	return s.store.Unsave(ctx, userID, postID)
}

// SavedBy returns the user's bookmarked posts, newest save first.
func (s *Service) SavedBy(ctx context.Context, userID string, f FeedFilter) ([]*FeedPost, int64, error) {
	if f.Limit <= 0 || f.Limit > 100 {
		f.Limit = 30
	}
	return s.store.ListSaved(ctx, userID, f)
}

func (s *Service) Mine(ctx context.Context, userID string) ([]*Post, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return s.store.ListMine(ctx, prof.ID)
}

func (s *Service) Update(ctx context.Context, userID, postID string, in CreateInput) (*Post, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	existing, err := s.store.GetByID(ctx, postID)
	if err != nil {
		return nil, err
	}
	if existing.ProfessionalID != prof.ID {
		return nil, httpx.Forbidden("not_your_post", "you can only update your own posts")
	}
	if in.CategoryID != nil && *in.CategoryID != "" {
		if _, err := s.catStore.GetByID(ctx, *in.CategoryID); err != nil {
			return nil, err
		}
	}

	updated := Post{
		CategoryID: in.CategoryID,
		Caption:    strings.TrimSpace(in.Caption),
		Location:   strings.TrimSpace(in.Location),
		Sponsored:  in.Sponsored,
	}
	res, err := s.store.Update(ctx, postID, updated)
	if err != nil {
		return nil, err
	}
	if len(in.Images) > 0 {
		urls, err := s.resolveImages(ctx, userID, in.Images)
		if err != nil {
			return nil, err
		}
		if err := s.store.SetImages(ctx, postID, urls); err != nil {
			return nil, err
		}
	}
	return res, nil
}

func (s *Service) Delete(ctx context.Context, userID, postID string) error {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	existing, err := s.store.GetByID(ctx, postID)
	if err != nil {
		return err
	}
	if existing.ProfessionalID != prof.ID {
		return httpx.Forbidden("not_your_post", "you can only delete your own posts")
	}
	return s.store.Delete(ctx, postID)
}

func (s *Service) SetSponsored(ctx context.Context, postID string, sponsored bool) (*Post, error) {
	existing, err := s.store.GetByID(ctx, postID)
	if err != nil {
		return nil, err
	}
	return s.store.Update(ctx, postID, Post{
		CategoryID: existing.CategoryID,
		Caption:    existing.Caption,
		Location:   existing.Location,
		Sponsored:  sponsored,
	})
}

// resolveImages maps raw image values to display URLs. A value that parses as a
// UUID is treated as a media asset id (resolved through the media store);
// anything else is treated as a direct URL.
func (s *Service) resolveImages(ctx context.Context, uploaderID string, images []string) ([]string, error) {
	out := make([]string, 0, len(images))
	for _, raw := range images {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		if looksLikeUUID(raw) {
			asset, err := s.mediaSvc.Get(ctx, raw)
			if err != nil {
				return nil, err
			}
			if asset.SecureURL == nil || *asset.SecureURL == "" {
				return nil, httpx.BadRequest("media_missing_url", "media asset has no url")
			}
			out = append(out, *asset.SecureURL)
			continue
		}
		if !strings.HasPrefix(raw, "http://") && !strings.HasPrefix(raw, "https://") {
			return nil, httpx.BadRequest("invalid_image", "image must be a URL or media asset id")
		}
		out = append(out, raw)
	}
	if len(out) == 0 {
		return nil, httpx.BadRequest("images_required", "at least one valid image is required")
	}
	return out, nil
}

func looksLikeUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for _, r := range s {
		if !strings.ContainsRune("0123456789abcdefABCDEF-", r) {
			return false
		}
	}
	return true
}
