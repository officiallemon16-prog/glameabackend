package users

import (
	"net/http"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc    *Service
	authMw func(http.Handler) http.Handler
}

func NewHandler(svc *Service, authMw func(http.Handler) http.Handler) *Handler {
	return &Handler{svc: svc, authMw: authMw}
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	userID := httpx.UserID(r)
	u, err := h.svc.GetCurrent(r.Context(), userID)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u})
}

type updateProfileRequest struct {
	FirstName     string  `json:"first_name"`
	LastName      string  `json:"last_name"`
	AvatarMediaID *string `json:"avatar_media_id"`
	Email         string  `json:"email"`
}

func (h *Handler) updateMe(w http.ResponseWriter, r *http.Request) {
	var req updateProfileRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}

	u, err := h.svc.UpdateProfile(r.Context(), httpx.UserID(r), UpdateProfileInput{
		FirstName:     req.FirstName,
		LastName:      req.LastName,
		AvatarMediaID: req.AvatarMediaID,
		Email:         req.Email,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Get("/api/v1/users/me", h.me)
		r.Patch("/api/v1/users/me", h.updateMe)
	})
}
