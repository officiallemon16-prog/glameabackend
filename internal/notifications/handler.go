package notifications

import (
	"net/http"
	"strconv"

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
	limit, offset := pageParams(r)
	items, total, err := h.svc.List(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{
		"notifications": items,
		"total":         total,
	})
}

func (h *Handler) unreadCount(w http.ResponseWriter, r *http.Request) {
	n, err := h.svc.UnreadCount(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"unread_count": n})
}

func (h *Handler) markRead(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.MarkRead(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) markAllRead(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.MarkAllRead(r.Context(), httpx.UserID(r)); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

type deviceRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (h *Handler) registerDevice(w http.ResponseWriter, r *http.Request) {
	var req deviceRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if req.Token == "" {
		httpx.Fail(w, httpx.BadRequest("token_required", "device token is required"))
		return
	}
	if req.Platform == "" {
		req.Platform = "android"
	}
	dev, err := h.svc.RegisterDevice(r.Context(), httpx.UserID(r), req.Token, req.Platform)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"device": dev})
}

func (h *Handler) unregisterDevice(w http.ResponseWriter, r *http.Request) {
	var req deviceRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if req.Token == "" {
		httpx.Fail(w, httpx.BadRequest("token_required", "device token is required"))
		return
	}
	if err := h.svc.RemoveDevice(r.Context(), httpx.UserID(r), req.Token); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Get("/api/v1/notifications/me", h.list)
		r.Get("/api/v1/notifications/me/unread-count", h.unreadCount)
		r.Post("/api/v1/notifications/me/read-all", h.markAllRead)
		r.Post("/api/v1/notifications/{id}/read", h.markRead)
		r.Post("/api/v1/notifications/devices", h.registerDevice)
		r.Post("/api/v1/notifications/devices/unregister", h.unregisterDevice)
	})
}

func pageParams(r *http.Request) (int, int) {
	limit := 50
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 100 {
		limit = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return limit, offset
}
