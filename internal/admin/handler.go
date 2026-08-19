package admin

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

func (h *Handler) dashboard(w http.ResponseWriter, r *http.Request) {
	stats, err := h.svc.Dashboard(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, stats)
}

func (h *Handler) dailyMetrics(w http.ResponseWriter, r *http.Request) {
	to := time.Now().Add(24 * time.Hour).Format("2006-01-02")
	from := time.Now().AddDate(0, -1, 0).Format("2006-01-02")
	if v := r.URL.Query().Get("from"); v != "" {
		from = v
	}
	if v := r.URL.Query().Get("to"); v != "" {
		to = v
	}
	items, err := h.svc.DailyMetrics(r.Context(), from, to)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"metrics": items})
}

func (h *Handler) listUsers(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListUsers(r.Context(), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"users": items, "total": total})
}

func (h *Handler) setUserStatus(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Status string `json:"status"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.SetUserStatus(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Status); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) setUserRole(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Role string `json:"role"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.SetUserRole(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Role); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) listProfessionals(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListProfessionals(r.Context(), r.URL.Query().Get("status"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professionals": items, "total": total})
}

func (h *Handler) setProfessionalStatus(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Status string `json:"status"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.SetProfessionalStatus(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Status); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) listAudit(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListAudit(r.Context(), r.URL.Query().Get("entity_type"), r.URL.Query().Get("entity_id"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"audit_logs": items, "total": total})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/dashboard", h.dashboard)
		r.Get("/api/v1/admin/dashboard/metrics", h.dailyMetrics)
		r.Get("/api/v1/admin/users", h.listUsers)
		r.Patch("/api/v1/admin/users/{id}/status", h.setUserStatus)
		r.Patch("/api/v1/admin/users/{id}/role", h.setUserRole)
		r.Get("/api/v1/admin/professionals", h.listProfessionals)
		r.Patch("/api/v1/admin/professionals/{id}/status", h.setProfessionalStatus)
		r.Get("/api/v1/admin/audit-logs", h.listAudit)
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
