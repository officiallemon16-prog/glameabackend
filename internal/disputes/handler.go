package disputes

import (
	"net/http"
	"strconv"

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

func (h *Handler) raise(w http.ResponseWriter, r *http.Request) {
	var req CreateInput
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	d, err := h.svc.Raise(r.Context(), httpx.UserID(r), req)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"dispute": d})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	d, err := h.svc.Get(r.Context(), httpx.UserID(r), httpx.Role(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"dispute": d})
}

func (h *Handler) messages(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.Messages(r.Context(), httpx.UserID(r), httpx.Role(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"messages": items})
}

func (h *Handler) addMessage(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Body string `json:"body"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	m, err := h.svc.AddMessage(r.Context(), httpx.UserID(r), httpx.Role(r), chi.URLParam(r, "id"), req.Body)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"message": m})
}

func (h *Handler) myDisputes(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListMine(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"disputes": items, "total": total})
}

func (h *Handler) allDisputes(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListAll(r.Context(), r.URL.Query().Get("status"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"disputes": items, "total": total})
}

func (h *Handler) resolve(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Resolution string `json:"resolution"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	d, err := h.svc.Resolve(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Resolution)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"dispute": d})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/disputes", h.raise)
		r.Get("/api/v1/disputes/me", h.myDisputes)
		r.Get("/api/v1/disputes/{id}", h.get)
		r.Get("/api/v1/disputes/{id}/messages", h.messages)
		r.Post("/api/v1/disputes/{id}/messages", h.addMessage)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/disputes", h.allDisputes)
		r.Post("/api/v1/admin/disputes/{id}/resolve", h.resolve)
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
