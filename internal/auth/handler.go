package auth

import (
	"net/http"
	"strings"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc       *Service
	rateLimit func(http.Handler) http.Handler
}

func NewHandler(svc *Service, rateLimitPerMinute int) *Handler {
	return &Handler{svc: svc, rateLimit: httpx.RateLimitMiddleware(rateLimitPerMinute)}
}

type registerRequest struct {
	Email     string `json:"email"`
	Phone     string `json:"phone"`
	Password  string `json:"password"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Role      string `json:"role"`
}

type socialLoginRequest struct {
	IDToken     string `json:"id_token"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

type loginRequest struct {
	Identifier string `json:"identifier"`
	Password   string `json:"password"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type verifyPhoneRequest struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

type requestOTPRequest struct {
	Phone string `json:"phone"`
}

type sendEmailCodeRequest struct {
	Email string `json:"email"`
}

type verifyEmailRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

type clerkSyncRequest struct {
	ClerkUserID string `json:"clerk_user_id"`
	Email       string `json:"email"`
	FirstName   string `json:"first_name"`
	LastName    string `json:"last_name"`
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}

	u, pair, err := h.svc.Register(r.Context(), RegisterInput{
		Email:     req.Email,
		Phone:     req.Phone,
		Password:  req.Password,
		FirstName: req.FirstName,
		LastName:  req.LastName,
		Role:      req.Role,
	}, clientIP(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"user": u, "tokens": pair})
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}

	u, pair, err := h.svc.Login(r.Context(), req.Identifier, req.Password, clientIP(r), r.UserAgent())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u, "tokens": pair})
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}

	pair, err := h.svc.Refresh(r.Context(), req.RefreshToken, clientIP(r), r.UserAgent())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"tokens": pair})
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.Logout(r.Context(), req.RefreshToken); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) verifyPhone(w http.ResponseWriter, r *http.Request) {
	var req verifyPhoneRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.VerifyPhone(r.Context(), req.Phone, req.Code); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"verified": true})
}

func (h *Handler) requestOTP(w http.ResponseWriter, r *http.Request) {
	var req requestOTPRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.RequestOTP(r.Context(), req.Phone); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"sent": true})
}

func (h *Handler) sendEmailCode(w http.ResponseWriter, r *http.Request) {
	var req sendEmailCodeRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.RequestEmailVerification(r.Context(), req.Email); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"sent": true})
}

func (h *Handler) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var req verifyEmailRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if err := h.svc.VerifyEmail(r.Context(), req.Email, req.Code); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"verified": true})
}

func (h *Handler) clerkSync(w http.ResponseWriter, r *http.Request) {
	var req clerkSyncRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if req.ClerkUserID == "" {
		httpx.Fail(w, httpx.BadRequest("clerk_user_id_required", "clerk_user_id is required"))
		return
	}
	u, pair, err := h.svc.ClerkSync(r.Context(), req.ClerkUserID, req.Email, req.FirstName, req.LastName, clientIP(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u, "tokens": pair})
}

func (h *Handler) googleLogin(w http.ResponseWriter, r *http.Request) {
	var req socialLoginRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if req.IDToken == "" {
		httpx.Fail(w, httpx.BadRequest("id_token_required", "id_token is required"))
		return
	}
	u, pair, err := h.svc.SocialLogin(r.Context(), "google", req.IDToken, req.Email, req.DisplayName, clientIP(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u, "tokens": pair})
}

func (h *Handler) appleLogin(w http.ResponseWriter, r *http.Request) {
	var req socialLoginRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	if req.IDToken == "" {
		httpx.Fail(w, httpx.BadRequest("id_token_required", "id_token is required"))
		return
	}
	u, pair, err := h.svc.SocialLogin(r.Context(), "apple", req.IDToken, req.Email, req.DisplayName, clientIP(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"user": u, "tokens": pair})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.rateLimit)
		r.Post("/api/v1/auth/register", h.register)
		r.Post("/api/v1/auth/login", h.login)
		r.Post("/api/v1/auth/google", h.googleLogin)
		r.Post("/api/v1/auth/apple", h.appleLogin)
		r.Post("/api/v1/auth/refresh", h.refresh)
		r.Post("/api/v1/auth/logout", h.logout)
		r.Post("/api/v1/auth/verify-phone", h.verifyPhone)
		r.Post("/api/v1/auth/resend-otp", h.requestOTP)
		r.Post("/api/v1/auth/send-email-code", h.sendEmailCode)
		r.Post("/api/v1/auth/verify-email", h.verifyEmail)
		r.Post("/api/v1/auth/clerk-sync", h.clerkSync)
	})
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		return strings.TrimSpace(parts[0])
	}
	host := r.RemoteAddr
	if i := strings.LastIndex(host, ":"); i != -1 {
		return host[:i]
	}
	return host
}
