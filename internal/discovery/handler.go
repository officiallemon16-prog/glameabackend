package discovery

import (
	"net/http"
	"strconv"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) home(w http.ResponseWriter, r *http.Request) {
	limit, _ := pageParams(r)
	data, err := h.svc.Home(r.Context(), limit)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, data)
}

func (h *Handler) search(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	in := SearchInput{
		Query:           q.Get("q"),
		CategoryID:      q.Get("category_id"),
		City:            q.Get("city"),
		VerifiedOnly:    q.Get("verified") == "true",
		HomeServiceOnly: q.Get("home_service") == "true",
		Sort:            q.Get("sort"),
	}
	in.Limit, in.Offset = pageParams(r)
	if in.Limit == 0 {
		in.Limit = 20
	}
	res, err := h.svc.Search(r.Context(), in)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, res)
}

func (h *Handler) professional(w http.ResponseWriter, r *http.Request) {
	p, err := h.svc.Professional(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"professional": p})
}

func (h *Handler) professionalServices(w http.ResponseWriter, r *http.Request) {
	items, _, err := h.svc.ServicesForProfessional(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"services": items})
}

func (h *Handler) category(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	res, err := h.svc.CategoryBySlug(r.Context(), chi.URLParam(r, "slug"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"category": res.Category, "professionals": res.Professionals})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Get("/api/v1/discovery/home", h.home)
	router.Get("/api/v1/discovery/search", h.search)
	router.Get("/api/v1/discovery/categories/{slug}", h.category)
	router.Get("/api/v1/discovery/professionals/{id}", h.professional)
	router.Get("/api/v1/discovery/professionals/{id}/services", h.professionalServices)
}

func pageParams(r *http.Request) (int, int) {
	limit := 0
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 100 {
		limit = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return limit, offset
}
