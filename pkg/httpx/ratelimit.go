package httpx

import (
	"net"
	"net/http"
	"sync"
	"time"
)

// tokenBucket is a simple fixed-capacity token bucket used by RateLimitMiddleware.
type tokenBucket struct {
	mu       sync.Mutex
	tokens   float64
	lastFill time.Time
}

// rateLimiter holds per-IP buckets with lazy expiry.
type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*tokenBucket
	cap     float64
	perSec  float64
}

func newRateLimiter(requestsPerMinute int) *rateLimiter {
	rl := &rateLimiter{
		buckets: map[string]*tokenBucket{},
		cap:     float64(requestsPerMinute),
	}
	if requestsPerMinute > 0 {
		rl.perSec = float64(requestsPerMinute) / 60.0
	}
	return rl
}

func (rl *rateLimiter) allow(key string) bool {
	now := time.Now()
	rl.mu.Lock()
	defer rl.mu.Unlock()

	b, ok := rl.buckets[key]
	if !ok {
		if len(rl.buckets) > 10000 {
			rl.prune(now)
		}
		b = &tokenBucket{tokens: rl.cap, lastFill: now}
		rl.buckets[key] = b
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	elapsed := now.Sub(b.lastFill).Seconds()
	b.tokens += elapsed * rl.perSec
	if b.tokens > rl.cap {
		b.tokens = rl.cap
	}
	b.lastFill = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

func (rl *rateLimiter) prune(now time.Time) {
	for k, b := range rl.buckets {
		b.mu.Lock()
		stale := now.Sub(b.lastFill) > 15*time.Minute
		b.mu.Unlock()
		if stale {
			delete(rl.buckets, k)
		}
	}
}

// RateLimitMiddleware returns a middleware that limits requests per client IP.
// requestsPerMinute <= 0 disables limiting.
func RateLimitMiddleware(requestsPerMinute int) func(http.Handler) http.Handler {
	if requestsPerMinute <= 0 {
		return func(next http.Handler) http.Handler { return next }
	}
	rl := newRateLimiter(requestsPerMinute)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !rl.allow(clientIP(r)) {
				Fail(w, NewError(http.StatusTooManyRequests, "rate_limited", "too many requests, please try again later"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func clientIP(r *http.Request) string {
	if ip, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return ip
	}
	return r.RemoteAddr
}
