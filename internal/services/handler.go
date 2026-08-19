package services

import (
	"net/http"
	"strconv"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc    *ServiceService
	authMw func(http.Handler) http.Handler
}

func NewHandler(svc *ServiceService, authMw func(http.Handler) http.Handler) *Handler {
	return &Handler{svc: svc, authMw: authMw}
}

type variantRequest struct {
	Name                 string  `json:"name"`
	PriceDelta           float64 `json:"price_delta"`
	DurationDeltaMinutes int     `json:"duration_delta_minutes"`
}

type serviceRequest struct {
	CategoryID           *string          `json:"category_id"`
	Name                 string           `json:"name"`
	Description          string           `json:"description"`
	BasePrice            float64          `json:"base_price"`
	Currency             string           `json:"currency"`
	DurationMinutes      int              `json:"duration_minutes"`
	DepositPercentage    float64          `json:"deposit_percentage"`
	HomeServiceAvailable bool             `json:"home_service_available"`
	CancellationPolicyID *string          `json:"cancellation_policy_id"`
	DisplayOrder         int              `json:"display_order"`
	Variants             []variantRequest `json:"variants"`
}

func toInput(req serviceRequest) CreateInput {
	variants := []VariantInput{}
	for _, v := range req.Variants {
		variants = append(variants, VariantInput{
			Name:                 v.Name,
			PriceDelta:           v.PriceDelta,
			DurationDeltaMinutes: v.DurationDeltaMinutes,
		})
	}
	return CreateInput{
		CategoryID:           req.CategoryID,
		Name:                 req.Name,
		Description:          req.Description,
		BasePrice:            req.BasePrice,
		Currency:             req.Currency,
		DurationMinutes:      req.DurationMinutes,
		DepositPercentage:    req.DepositPercentage,
		HomeServiceAvailable: req.HomeServiceAvailable,
		CancellationPolicyID: req.CancellationPolicyID,
		DisplayOrder:         req.DisplayOrder,
		Variants:             variants,
	}
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req serviceRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	svc, err := h.svc.Create(r.Context(), httpx.UserID(r), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"service": svc})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	svc, err := h.svc.Get(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"service": svc})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	var req serviceRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	svc, err := h.svc.Update(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"service": svc})
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Delete(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage == 0 {
		perPage = 50
	}

	items, total, err := h.svc.List(r.Context(), ListFilter{
		ProfessionalID: r.URL.Query().Get("professional_id"),
		CategoryID:     r.URL.Query().Get("category_id"),
		Limit:          perPage,
		Offset:         (page - 1) * perPage,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{
		"services": items,
		"meta": httpx.Meta{
			Page:    page,
			PerPage: perPage,
			Total:   total,
			HasMore: int64(page*perPage) < total,
		},
	})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/services", h.list)
	router.Get("/api/v1/services/{id}", h.get)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/services", h.create)
		r.Patch("/api/v1/services/{id}", h.update)
		r.Delete("/api/v1/services/{id}", h.delete)
	})
}
