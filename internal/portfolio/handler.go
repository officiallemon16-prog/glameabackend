package portfolio

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

type itemRequest struct {
	MediaAssetID string  `json:"media_asset_id"`
	ServiceID    *string `json:"service_id"`
	Caption      string  `json:"caption"`
	IsFeatured   bool    `json:"is_featured"`
	DisplayOrder int     `json:"display_order"`
}

func toInput(req itemRequest) CreateInput {
	return CreateInput{
		MediaAssetID: req.MediaAssetID,
		ServiceID:    req.ServiceID,
		Caption:      req.Caption,
		IsFeatured:   req.IsFeatured,
		DisplayOrder: req.DisplayOrder,
	}
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req itemRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	item, err := h.svc.Create(r.Context(), httpx.UserID(r), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"item": item})
}

func (h *Handler) getOwn(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.ListOwn(r.Context(), httpx.UserID(r), true)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"items": items})
}

func (h *Handler) getByProfessional(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	items, err := h.svc.ListForProfessional(r.Context(), id, false)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"items": items})
}

func (h *Handler) getByID(w http.ResponseWriter, r *http.Request) {
	item, err := h.svc.GetPublic(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"item": item})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	var req itemRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	item, err := h.svc.Update(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"item": item})
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Delete(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/professionals/{id}/portfolio", h.getByProfessional)
	router.Get("/api/v1/portfolio/{id}", h.getByID)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Get("/api/v1/portfolio/me", h.getOwn)
		r.Post("/api/v1/portfolio", h.create)
		r.Patch("/api/v1/portfolio/{id}", h.update)
		r.Delete("/api/v1/portfolio/{id}", h.delete)
	})
}
