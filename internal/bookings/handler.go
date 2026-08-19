package bookings

import (
	"log/slog"
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

type createRequest struct {
	ServiceID       string   `json:"service_id"`
	VariantID       *string  `json:"variant_id"`
	StartAt         string   `json:"start_at"`
	HomeService     bool     `json:"home_service"`
	LocationLat     *float64 `json:"location_lat"`
	LocationLng     *float64 `json:"location_lng"`
	LocationAddress string   `json:"location_address"`
	CustomerNotes   string   `json:"customer_notes"`
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	start, err := time.Parse(time.RFC3339, req.StartAt)
	if err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_start_at", "start_at must be an RFC3339 timestamp"))
		return
	}
	booking, created, err := h.svc.Create(r.Context(), httpx.UserID(r), CreateInput{
		ServiceID:       req.ServiceID,
		VariantID:       req.VariantID,
		StartAt:         start,
		HomeService:     req.HomeService,
		LocationLat:     req.LocationLat,
		LocationLng:     req.LocationLng,
		LocationAddress: req.LocationAddress,
		CustomerNotes:   req.CustomerNotes,
		IdempotencyKey:  r.Header.Get("Idempotency-Key"),
	})
	if err != nil {
		slog.Error("booking create failed", "error", err, "service_id", req.ServiceID, "start_at", req.StartAt)
		httpx.Fail(w, err)
		return
	}
	if created {
		httpx.Created(w, map[string]any{"booking": booking})
		return
	}
	httpx.OK(w, map[string]any{"booking": booking})
}

func (h *Handler) myBookings(w http.ResponseWriter, r *http.Request) {
	limit := pageParam(r, "limit", 50)
	offset := pageParam(r, "offset", 0)
	bookings, err := h.svc.ListForCustomer(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"bookings": bookings})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	b, err := h.svc.Get(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

func (h *Handler) history(w http.ResponseWriter, r *http.Request) {
	events, err := h.svc.StatusEvents(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"events": events})
}

type cancelRequest struct {
	Reason string `json:"reason"`
}

func (h *Handler) cancel(w http.ResponseWriter, r *http.Request) {
	var req cancelRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	b, err := h.svc.Cancel(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), req.Reason)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

type rescheduleRequest struct {
	StartAt string `json:"start_at"`
}

func (h *Handler) reschedule(w http.ResponseWriter, r *http.Request) {
	var req rescheduleRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	start, err := time.Parse(time.RFC3339, req.StartAt)
	if err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_start_at", "start_at must be an RFC3339 timestamp"))
		return
	}
	b, err := h.svc.Reschedule(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), start)
	if err != nil {
		slog.Error("booking reschedule failed", "error", err, "booking_id", chi.URLParam(r, "id"))
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

func (h *Handler) proBookings(w http.ResponseWriter, r *http.Request) {
	limit := pageParam(r, "limit", 50)
	offset := pageParam(r, "offset", 0)
	bookings, err := h.svc.ListForProfessional(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"bookings": bookings})
}

func (h *Handler) confirm(w http.ResponseWriter, r *http.Request) {
	b, err := h.svc.Confirm(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

func (h *Handler) start(w http.ResponseWriter, r *http.Request) {
	b, err := h.svc.Start(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

func (h *Handler) complete(w http.ResponseWriter, r *http.Request) {
	b, err := h.svc.Complete(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"booking": b})
}

func (h *Handler) slots(w http.ResponseWriter, r *http.Request) {
	duration, _ := strconv.Atoi(r.URL.Query().Get("duration_minutes"))
	if duration <= 0 {
		duration, _ = strconv.Atoi(r.URL.Query().Get("duration"))
	}
	step, _ := strconv.Atoi(r.URL.Query().Get("step"))
	slots, err := h.svc.AvailableSlots(r.Context(), AvailableSlotsInput{
		ProfessionalID: chi.URLParam(r, "id"),
		Date:           r.URL.Query().Get("date"),
		Duration:       duration,
		Step:           step,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"slots": slots})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/bookings", h.create)
		r.Get("/api/v1/bookings/me", h.myBookings)
		r.Get("/api/v1/bookings/{id}", h.get)
		r.Get("/api/v1/bookings/{id}/history", h.history)
		r.Post("/api/v1/bookings/{id}/cancel", h.cancel)
		r.Post("/api/v1/bookings/{id}/reschedule", h.reschedule)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleProfessional))
		r.Get("/api/v1/professionals/me/bookings", h.proBookings)
		r.Post("/api/v1/professionals/me/bookings/{id}/confirm", h.confirm)
		r.Post("/api/v1/professionals/me/bookings/{id}/start", h.start)
		r.Post("/api/v1/professionals/me/bookings/{id}/complete", h.complete)
	})

	router.Get("/api/v1/professionals/{id}/availability/slots", h.slots)
}

func pageParam(r *http.Request, key string, def int) int {
	if v := r.URL.Query().Get(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			return n
		}
	}
	return def
}
