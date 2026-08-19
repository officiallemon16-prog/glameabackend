package categories

import (
	"net/http"

	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/users"
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

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.List(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"categories": items, "count": len(items)})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")
	c, err := h.svc.GetBySlug(r.Context(), slug)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"category": c})
}

type categoryRequest struct {
	Name         string  `json:"name"`
	Slug         string  `json:"slug"`
	Description  string  `json:"description"`
	IconMediaID  *string `json:"icon_media_id"`
	DisplayOrder int     `json:"display_order"`
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req categoryRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	c, err := h.svc.Create(r.Context(), CreateInput{
		Name:         req.Name,
		Slug:         req.Slug,
		Description:  req.Description,
		IconMediaID:  req.IconMediaID,
		DisplayOrder: req.DisplayOrder,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"category": c})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req categoryRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	c, err := h.svc.Update(r.Context(), id, CreateInput{
		Name:         req.Name,
		Slug:         req.Slug,
		Description:  req.Description,
		IconMediaID:  req.IconMediaID,
		DisplayOrder: req.DisplayOrder,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"category": c})
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := h.svc.Delete(r.Context(), id); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/categories", h.list)
	router.Get("/api/v1/categories/{slug}", h.get)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Post("/api/v1/categories", h.create)
		r.Patch("/api/v1/categories/{id}", h.update)
		r.Delete("/api/v1/categories/{id}", h.delete)
	})
}
