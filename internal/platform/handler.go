package platform

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
	items, err := h.svc.All(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"settings": items})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	st, err := h.svc.Get(r.Context(), chi.URLParam(r, "name"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, st)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	var req map[string]string
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	allowed := map[string]bool{
		"platform_name": true, "platform_fee_percent": true,
		"default_currency": true, "min_deposit_percent": true,
		"support_email": true, "maintenance_mode": true,
		"signup_enabled": true, "pro_signup_enabled": true,
	}
	filtered := make(map[string]string, len(req))
	for k, v := range req {
		if !allowed[k] {
			continue
		}
		if len(v) > 500 {
			continue
		}
		filtered[k] = v
	}
	if len(filtered) == 0 {
		httpx.Fail(w, httpx.BadRequest("no_valid_settings", "no valid setting names provided"))
		return
	}
	if err := h.svc.Update(r.Context(), filtered); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) publicSettings(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.All(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"settings": items})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/settings", h.publicSettings)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/settings", h.list)
		r.Get("/api/v1/admin/settings/{name}", h.get)
		r.Patch("/api/v1/admin/settings", h.update)
	})
}
