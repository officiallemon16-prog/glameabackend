package httpx

import (
	"context"
	"encoding/base64"
	"net/http"
	"strings"
)

func BasicAuth(r *http.Request) (username string, password string, ok bool) {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Basic ") {
		return "", "", false
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(auth, "Basic "))
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

type basicCredsCtxKey struct{}

func WithBasicCreds(ctx context.Context, user string, pass string) context.Context {
	return context.WithValue(ctx, basicCredsCtxKey{}, [2]string{user, pass})
}

func BasicCreds(ctx context.Context) (string, string, bool) {
	creds, ok := ctx.Value(basicCredsCtxKey{}).([2]string)
	if !ok {
		return "", "", false
	}
	return creds[0], creds[1], true
}
