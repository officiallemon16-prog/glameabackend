package verification

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

type submitRequest struct {
	Stage        string  `json:"stage"`
	DocumentType string  `json:"document_type"`
	MediaAssetID *string `json:"media_asset_id"`
}

func (h *Handler) submit(w http.ResponseWriter, r *http.Request) {
	var req submitRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	doc, err := h.svc.Submit(r.Context(), httpx.UserID(r), SubmitInput{
		Stage:        req.Stage,
		DocumentType: req.DocumentType,
		MediaAssetID: req.MediaAssetID,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"document": doc})
}

func (h *Handler) getOwn(w http.ResponseWriter, r *http.Request) {
	docs, err := h.svc.GetOwn(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"documents": docs})
}

type reviewRequest struct {
	Approve bool   `json:"approve"`
	Note    string `json:"note"`
}

func (h *Handler) review(w http.ResponseWriter, r *http.Request) {
	var req reviewRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	doc, err := h.svc.Review(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), ReviewInput{
		Approve: req.Approve,
		Note:    req.Note,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"document": doc})
}

func (h *Handler) listAll(w http.ResponseWriter, r *http.Request) {
	docs, err := h.svc.ListAll(r.Context(), r.URL.Query().Get("pending") == "true")
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"documents": docs})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/verification/documents", h.submit)
		r.Get("/api/v1/verification/me", h.getOwn)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/verification/documents", h.listAll)
		r.Post("/api/v1/admin/verification/documents/{id}/review", h.review)
	})
}
