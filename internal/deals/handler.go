package deals

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

func (h *Handler) listActive(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListActive(r.Context(), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deals": items, "total": total})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	d, err := h.svc.Get(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deal": d})
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req CreateInput
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	d, err := h.svc.Create(r.Context(), httpx.UserID(r), req)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"deal": d})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	var req UpdateInput
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	d, err := h.svc.Update(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deal": d})
}

func (h *Handler) deactivate(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Deactivate(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) myDeals(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListMine(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deals": items, "total": total})
}

func (h *Handler) allDeals(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListAll(r.Context(), r.URL.Query().Get("active"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deals": items, "total": total})
}

func (h *Handler) toggle(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Active bool `json:"active"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	d, err := h.svc.Toggle(r.Context(), chi.URLParam(r, "id"), req.Active)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"deal": d})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/deals", h.listActive)
	router.Get("/api/v1/deals/{id}", h.get)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleProfessional))
		r.Post("/api/v1/professionals/me/deals", h.create)
		r.Get("/api/v1/professionals/me/deals", h.myDeals)
		r.Patch("/api/v1/professionals/me/deals/{id}", h.update)
		r.Delete("/api/v1/professionals/me/deals/{id}", h.deactivate)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/deals", h.allDeals)
		r.Patch("/api/v1/admin/deals/{id}/toggle", h.toggle)
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
