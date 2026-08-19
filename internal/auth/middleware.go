package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type principalCtxKey struct{}

type Principal struct {
	UserID string
	Role   string
}

func PrincipalFrom(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalCtxKey{}).(Principal)
	return p, ok
}

func AuthMiddleware(userStore *users.Store, tokens *TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if !strings.HasPrefix(authHeader, "Bearer ") {
				httpx.Fail(w, httpx.Unauthorized("missing_token", "missing bearer token"))
				return
			}

			claims, err := tokens.ParseAccessToken(strings.TrimPrefix(authHeader, "Bearer "))
			if err != nil {
				httpx.Fail(w, httpx.Unauthorized("invalid_token", "invalid or expired token"))
				return
			}

			u, err := userStore.GetByID(r.Context(), claims.Subject)
			if err != nil {
				httpx.Fail(w, httpx.Unauthorized("invalid_token", "user no longer exists"))
				return
			}
			if u.Status != users.StatusActive {
				httpx.Fail(w, httpx.Forbidden("account_inactive", "account is not active"))
				return
			}

			ctx := context.WithValue(r.Context(), principalCtxKey{}, Principal{UserID: u.ID, Role: u.Role})
			ctx = context.WithValue(ctx, httpx.UserIDKey, u.ID)
			ctx = context.WithValue(ctx, httpx.RoleKey, u.Role)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// OptionalAuthMiddleware authenticates the request when a bearer token is
// present, but never rejects it. Public endpoints use it to enrich responses
// (e.g. liked_by_me on the feed) without requiring login.
func OptionalAuthMiddleware(userStore *users.Store, tokens *TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if !strings.HasPrefix(authHeader, "Bearer ") {
				next.ServeHTTP(w, r)
				return
			}
			claims, err := tokens.ParseAccessToken(strings.TrimPrefix(authHeader, "Bearer "))
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}
			u, err := userStore.GetByID(r.Context(), claims.Subject)
			if err != nil || u.Status != users.StatusActive {
				next.ServeHTTP(w, r)
				return
			}

			ctx := context.WithValue(r.Context(), principalCtxKey{}, Principal{UserID: u.ID, Role: u.Role})
			ctx = context.WithValue(ctx, httpx.UserIDKey, u.ID)
			ctx = context.WithValue(ctx, httpx.RoleKey, u.Role)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func RequireRoles(roles ...string) func(http.Handler) http.Handler {
	allowed := map[string]bool{}
	for _, r := range roles {
		allowed[r] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			p, ok := PrincipalFrom(r.Context())
			if !ok {
				httpx.Fail(w, httpx.Unauthorized("missing_token", "missing bearer token"))
				return
			}
			if !allowed[p.Role] {
				httpx.Fail(w, httpx.Forbidden("forbidden", "you do not have permission to perform this action"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
