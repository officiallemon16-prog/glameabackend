package reviews

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

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req struct {
		BookingID string `json:"booking_id"`
		Rating    int    `json:"rating"`
		Comment   string `json:"comment"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	rv, err := h.svc.Create(r.Context(), httpx.UserID(r), CreateInput{
		BookingID: req.BookingID,
		Rating:    req.Rating,
		Comment:   req.Comment,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"review": rv})
}

func (h *Handler) listForProfessional(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListForProfessional(r.Context(), chi.URLParam(r, "id"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"reviews": items, "total": total})
}

func (h *Handler) myReviews(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListMineForPro(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"reviews": items, "total": total})
}

func (h *Handler) myWritten(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListMineAsCustomer(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"reviews": items, "total": total})
}

func (h *Handler) respond(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Response string `json:"response"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	rv, err := h.svc.Respond(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Response)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"review": rv})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/professionals/{id}/reviews", h.listForProfessional)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/reviews", h.create)
		r.Get("/api/v1/reviews/me", h.myWritten)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleProfessional))
		r.Get("/api/v1/professionals/me/reviews", h.myReviews)
		r.Post("/api/v1/professionals/me/reviews/{id}/respond", h.respond)
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
