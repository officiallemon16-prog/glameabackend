package posts

import (
	"net/http"
	"strconv"

	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc            *Service
	authMw         func(http.Handler) http.Handler
	optionalAuthMw func(http.Handler) http.Handler
}

func NewHandler(svc *Service, authMw func(http.Handler) http.Handler, optionalAuthMw func(http.Handler) http.Handler) *Handler {
	return &Handler{svc: svc, authMw: authMw, optionalAuthMw: optionalAuthMw}
}

type postRequest struct {
	CategoryID *string  `json:"category_id"`
	Caption    string   `json:"caption"`
	Location   string   `json:"location"`
	Sponsored  bool     `json:"sponsored"`
	Images     []string `json:"images"`
}

func toInput(req postRequest) CreateInput {
	return CreateInput{
		CategoryID: req.CategoryID,
		Caption:    req.Caption,
		Location:   req.Location,
		Sponsored:  req.Sponsored,
		Images:     req.Images,
	}
}

func (h *Handler) feed(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	filter := FeedFilter{
		CategoryID: q.Get("category_id"),
		UserID:     httpx.UserID(r),
		Limit:      pageLimit(r),
		Offset:     pageOffset(r),
	}
	if v := q.Get("sponsored"); v != "" {
		b := v == "true"
		filter.Sponsored = &b
	}
	items, total, err := h.svc.Feed(r.Context(), filter)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"posts": items, "total": total})
}

// like favorites a post for the current user.
func (h *Handler) like(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Like(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"liked": true})
}

// unlike removes a post from the current user's favorites.
func (h *Handler) unlike(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Unlike(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"liked": false})
}

// liked lists the current user's favorited posts.
func (h *Handler) liked(w http.ResponseWriter, r *http.Request) {
	items, total, err := h.svc.LikedBy(r.Context(), httpx.UserID(r), FeedFilter{
		Limit:  pageLimit(r),
		Offset: pageOffset(r),
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"posts": items, "total": total})
}

// save bookmarks a post for the current user.
func (h *Handler) save(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Save(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"saved": true})
}

// unsave removes a post from the current user's bookmarks.
func (h *Handler) unsave(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Unsave(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"saved": false})
}

// saved lists the current user's bookmarked posts.
func (h *Handler) saved(w http.ResponseWriter, r *http.Request) {
	items, total, err := h.svc.SavedBy(r.Context(), httpx.UserID(r), FeedFilter{
		Limit:  pageLimit(r),
		Offset: pageOffset(r),
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"posts": items, "total": total})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	post, err := h.svc.Get(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"post": post})
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req postRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	post, err := h.svc.Create(r.Context(), httpx.UserID(r), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"post": post})
}

func (h *Handler) mine(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.Mine(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"posts": items})
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	var req postRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	post, err := h.svc.Update(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"), toInput(req))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"post": post})
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Delete(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) setSponsored(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Sponsored bool `json:"sponsored"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	post, err := h.svc.SetSponsored(r.Context(), chi.URLParam(r, "id"), req.Sponsored)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"post": post})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.optionalAuthMw)
		r.Get("/api/v1/feed", h.feed)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Get("/api/v1/posts/me/likes", h.liked)
		r.Get("/api/v1/posts/me/saves", h.saved)
		r.Post("/api/v1/posts/{id}/like", h.like)
		r.Delete("/api/v1/posts/{id}/like", h.unlike)
		r.Post("/api/v1/posts/{id}/save", h.save)
		r.Delete("/api/v1/posts/{id}/save", h.unsave)
	})

	router.Get("/api/v1/posts/{id}", h.get)

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleProfessional))
		r.Post("/api/v1/professionals/me/posts", h.create)
		r.Get("/api/v1/professionals/me/posts", h.mine)
		r.Patch("/api/v1/professionals/me/posts/{id}", h.update)
		r.Delete("/api/v1/professionals/me/posts/{id}", h.delete)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Patch("/api/v1/admin/posts/{id}/sponsored", h.setSponsored)
	})
}

func pageLimit(r *http.Request) int {
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 100 {
		return v
	}
	return 30
}

func pageOffset(r *http.Request) int {
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		return v
	}
	return 0
}
