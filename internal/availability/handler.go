package availability

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

func (h *Handler) setWindows(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Windows []WindowInput `json:"windows"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	windows, err := h.svc.SetWindows(r.Context(), httpx.UserID(r), req.Windows)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"windows": windows})
}

func (h *Handler) myWindows(w http.ResponseWriter, r *http.Request) {
	windows, err := h.svc.ListMyWindows(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"windows": windows})
}

func (h *Handler) listWindows(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	windows, err := h.svc.ListWindows(r.Context(), id)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"windows": windows})
}

func (h *Handler) addException(w http.ResponseWriter, r *http.Request) {
	var req ExceptionInput
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	e, err := h.svc.AddException(r.Context(), httpx.UserID(r), req)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"exception": e})
}

func (h *Handler) myExceptions(w http.ResponseWriter, r *http.Request) {
	exceptions, err := h.svc.ListMyExceptions(r.Context(), httpx.UserID(r), r.URL.Query().Get("from"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"exceptions": exceptions})
}

func (h *Handler) deleteException(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.DeleteException(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Put("/api/v1/availability/windows", h.setWindows)
		r.Get("/api/v1/availability/windows", h.myWindows)
		r.Post("/api/v1/availability/exceptions", h.addException)
		r.Get("/api/v1/availability/exceptions", h.myExceptions)
		r.Delete("/api/v1/availability/exceptions/{id}", h.deleteException)
	})
	router.Get("/api/v1/professionals/{id}/availability", h.listWindows)
}
