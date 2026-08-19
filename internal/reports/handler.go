package reports

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

func (h *Handler) rangeParams(r *http.Request) (string, string) {
	from, to := DefaultRange()
	if v := r.URL.Query().Get("from"); v != "" {
		from = v
	}
	if v := r.URL.Query().Get("to"); v != "" {
		to = v
	}
	return from, to
}

func (h *Handler) bookings(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	limit, offset := pageParams(r)
	items, total, err := h.svc.Bookings(r.Context(), from, to, limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"bookings": items, "total": total})
}

func (h *Handler) payments(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	limit, offset := pageParams(r)
	items, total, err := h.svc.Payments(r.Context(), from, to, limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"payments": items, "total": total})
}

func (h *Handler) payouts(w http.ResponseWriter, r *http.Request) {
	from, to := h.rangeParams(r)
	limit, offset := pageParams(r)
	items, total, err := h.svc.Payouts(r.Context(), from, to, limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"payouts": items, "total": total})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/reports/bookings", h.bookings)
		r.Get("/api/v1/admin/reports/payments", h.payments)
		r.Get("/api/v1/admin/reports/payouts", h.payouts)
	})
}

func pageParams(r *http.Request) (int, int) {
	limit := 50
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 200 {
		limit = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return limit, offset
}
