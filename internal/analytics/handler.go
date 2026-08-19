package analytics

import (
	"net/http"
	"strconv"
	"time"

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

func (h *Handler) rangeParams(r *http.Request) (string, string) {
	from, to := DefaultRange()
	if v := r.URL.Query().Get("from"); v != "" {
		if _, err := time.Parse("2006-01-02", v); err == nil {
			from = v
		}
	}
	if v := r.URL.Query().Get("to"); v != "" {
		if _, err := time.Parse("2006-01-02", v); err == nil {
			to = v
		}
	}
	return from, to
}

func (h *Handler) summary(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	s, err := h.svc.Summary(r.Context(), from, to)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, s)
}

func (h *Handler) trends(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	items, err := h.svc.Trends(r.Context(), from, to)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"trends": items})
}

func (h *Handler) revenueByService(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	items, err := h.svc.RevenueByService(r.Context(), from, to)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"services": items})
}

func (h *Handler) topProfessionals(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	limit := 10
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 50 {
		limit = v
	}
	items, err := h.svc.TopProfessionals(r.Context(), from, to, limit)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professionals": items})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/analytics/summary", h.summary)
		r.Get("/api/v1/admin/analytics/trends", h.trends)
		r.Get("/api/v1/admin/analytics/revenue-by-service", h.revenueByService)
		r.Get("/api/v1/admin/analytics/top-professionals", h.topProfessionals)
	})
}
