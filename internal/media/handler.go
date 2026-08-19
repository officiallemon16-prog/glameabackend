package media

import (
	"io"
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

type signatureRequest struct {
	Folder       string `json:"folder"`
	PublicID     string `json:"public_id"`
	ResourceType string `json:"resource_type"`
}

func (h *Handler) uploadSignature(w http.ResponseWriter, r *http.Request) {
	var req signatureRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if h.svc.UploadMode() == modeLocal {
		httpx.OK(w, map[string]any{"mode": modeLocal, "max_bytes": h.svc.MaxBytes()})
		return
	}
	sig, err := h.svc.UploadSignature(UploadSignatureInput{
		Folder:       req.Folder,
		PublicID:     req.PublicID,
		ResourceType: req.ResourceType,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"mode": modeCloudinary, "signature": sig})
}

func (h *Handler) uploadLocal(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, h.svc.MaxBytes())
	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.Fail(w, httpx.BadRequest("file_required", "a multipart file field named 'file' is required"))
		return
	}
	defer file.Close()
	data, err := io.ReadAll(file)
	if err != nil {
		httpx.Fail(w, httpx.BadRequest("file_too_large", "file exceeds the maximum allowed size"))
		return
	}
	a, err := h.svc.SaveLocalUpload(r.Context(), httpx.UserID(r), header.Filename, data)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"asset": a})
}

type registerRequest struct {
	Provider     string  `json:"provider"`
	PublicID     string  `json:"public_id"`
	ResourceType string  `json:"resource_type"`
	Format       *string `json:"format"`
	Width        *int    `json:"width"`
	Height       *int    `json:"height"`
	DurationMs   *int    `json:"duration_ms"`
	Bytes        *int64  `json:"bytes"`
	SecureURL    *string `json:"secure_url"`
	Folder       string  `json:"folder"`
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	a, err := h.svc.RegisterAsset(r.Context(), httpx.UserID(r), RegisterAssetInput{
		Provider:     req.Provider,
		PublicID:     req.PublicID,
		ResourceType: req.ResourceType,
		Format:       req.Format,
		Width:        req.Width,
		Height:       req.Height,
		DurationMs:   req.DurationMs,
		Bytes:        req.Bytes,
		SecureURL:    req.SecureURL,
		Folder:       req.Folder,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"asset": a})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/media/upload-signature", h.uploadSignature)
		r.Post("/api/v1/media/upload", h.uploadLocal)
		r.Post("/api/v1/media", h.register)
	})
}
