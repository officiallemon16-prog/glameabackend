package professionals

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

type profileRequest struct {
	BusinessName       string   `json:"business_name"`
	DisplayName        string   `json:"display_name"`
	Bio                string   `json:"bio"`
	CategoryID         *string  `json:"category_id"`
	ExperienceYears    *int     `json:"experience_years"`
	Latitude           *float64 `json:"latitude"`
	Longitude          *float64 `json:"longitude"`
	AddressLine        string   `json:"address_line"`
	City               string   `json:"city"`
	Country            string   `json:"country"`
	Timezone           string   `json:"timezone"`
	HomeServiceEnabled bool     `json:"home_service_enabled"`
	ServiceRadiusKm    *float64 `json:"service_radius_km"`
	TravelFeePerKm     float64  `json:"travel_fee_per_km"`
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req profileRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	p, err := h.svc.Create(r.Context(), httpx.UserID(r), fromRequest(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"professional": p})
}

func (h *Handler) getOwn(w http.ResponseWriter, r *http.Request) {
	p, err := h.svc.GetOwn(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professional": p})
}

func (h *Handler) updateOwn(w http.ResponseWriter, r *http.Request) {
	var req profileRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	p, err := h.svc.UpdateOwn(r.Context(), httpx.UserID(r), fromRequest(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professional": p})
}

func (h *Handler) getPublic(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	p, err := h.svc.GetPublic(r.Context(), id)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professional": p})
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if limit == 0 {
		limit = 20
	}
	if page < 1 {
		page = 1
	}
	offset := (page - 1) * limit

	items, total, err := h.svc.List(r.Context(), ListFilter{
		Query:           r.URL.Query().Get("q"),
		CategoryID:      r.URL.Query().Get("category_id"),
		City:            r.URL.Query().Get("city"),
		VerifiedOnly:    r.URL.Query().Get("verified") == "true",
		HomeServiceOnly: r.URL.Query().Get("home_service") == "true",
		Sort:            r.URL.Query().Get("sort"),
		Limit:           limit,
		Offset:          offset,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{
		"professionals": items,
		"meta": httpx.Meta{
			Page:    page,
			PerPage: limit,
			Total:   total,
			HasMore: int64(page*limit) < total,
		},
	})
}

func fromRequest(req profileRequest) ProfileInput {
	return ProfileInput{
		BusinessName:       req.BusinessName,
		DisplayName:        req.DisplayName,
		Bio:                req.Bio,
		CategoryID:         req.CategoryID,
		ExperienceYears:    req.ExperienceYears,
		Latitude:           req.Latitude,
		Longitude:          req.Longitude,
		AddressLine:        req.AddressLine,
		City:               req.City,
		Country:            req.Country,
		Timezone:           req.Timezone,
		HomeServiceEnabled: req.HomeServiceEnabled,
		ServiceRadiusKm:    req.ServiceRadiusKm,
		TravelFeePerKm:     req.TravelFeePerKm,
	}
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/professionals", h.list)
	router.Get("/api/v1/professionals/{id}", h.getPublic)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/professionals", h.create)
		r.Get("/api/v1/professionals/me", h.getOwn)
		r.Patch("/api/v1/professionals/me", h.updateOwn)
	})
}
