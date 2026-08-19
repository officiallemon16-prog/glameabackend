package messaging

import (
	"net/http"
	"strconv"
	"time"

	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

// STUN servers offered to callers when the operator has not configured TURN.
var defaultICEServers = []map[string]any{
	{"urls": []string{"stun:stun.l.google.com:19302"}},
	{"urls": []string{"stun:stun1.l.google.com:19302"}},
}

type Handler struct {
	svc       *Service
	authMw    func(http.Handler) http.Handler
	hub       *Hub
	userStore *users.Store
	tokens    *auth.TokenManager

	turnURL        string
	turnUsername   string
	turnCredential string
}

func NewHandler(svc *Service, authMw func(http.Handler) http.Handler, hub *Hub, userStore *users.Store, tokens *auth.TokenManager, turnURL, turnUsername, turnCredential string) *Handler {
	return &Handler{
		svc:            svc,
		authMw:         authMw,
		hub:            hub,
		userStore:      userStore,
		tokens:         tokens,
		turnURL:        turnURL,
		turnUsername:   turnUsername,
		turnCredential: turnCredential,
	}
}

type sendRequest struct {
	Body         string   `json:"body"`
	Type         string   `json:"type"`
	MediaAssetID *string  `json:"media_asset_id"`
	MediaURL     string   `json:"media_url"`
	MimeType     string   `json:"mime_type"`
	DurationMs   *int     `json:"duration_ms"`
	Width        *int     `json:"width"`
	Height       *int     `json:"height"`
	Latitude     *float64 `json:"latitude"`
	Longitude    *float64 `json:"longitude"`
	Address      string   `json:"address"`
	CallType     string   `json:"call_type"`
	CallStatus   string   `json:"call_status"`
}

func (h *Handler) send(w http.ResponseWriter, r *http.Request) {
	var req sendRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	msg, err := h.svc.Send(r.Context(), httpx.UserID(r), chi.URLParam(r, "booking_id"), SendInput{
		Body:         req.Body,
		Type:         req.Type,
		MediaAssetID: req.MediaAssetID,
		MediaURL:     req.MediaURL,
		MimeType:     req.MimeType,
		DurationMs:   req.DurationMs,
		Width:        req.Width,
		Height:       req.Height,
		Latitude:     req.Latitude,
		Longitude:    req.Longitude,
		Address:      req.Address,
		CallType:     req.CallType,
		CallStatus:   req.CallStatus,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"message": msg})
}

func (h *Handler) messages(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	before, beforeID := beforeParams(r)
	items, total, err := h.svc.Messages(r.Context(), httpx.UserID(r), chi.URLParam(r, "booking_id"), limit, offset, before, beforeID)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"messages": items, "total": total})
}

func (h *Handler) conversation(w http.ResponseWriter, r *http.Request) {
	conv, err := h.svc.ConversationForBooking(r.Context(), httpx.UserID(r), chi.URLParam(r, "booking_id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"conversation": conv})
}

func (h *Handler) listConversations(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListConversations(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"conversations": items, "total": total})
}

func (h *Handler) markRead(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.MarkRead(r.Context(), httpx.UserID(r), chi.URLParam(r, "booking_id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) unread(w http.ResponseWriter, r *http.Request) {
	n, err := h.svc.UnreadTotal(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"unread": n})
}

// iceServers returns the STUN/TURN configuration clients should use for calls.
func (h *Handler) iceServers(w http.ResponseWriter, r *http.Request) {
	servers := append([]map[string]any{}, defaultICEServers...)
	if h.turnURL != "" {
		server := map[string]any{"urls": []string{h.turnURL}}
		if h.turnUsername != "" {
			server["username"] = h.turnUsername
		}
		if h.turnCredential != "" {
			server["credential"] = h.turnCredential
		}
		servers = append(servers, server)
	}
	httpx.OK(w, map[string]any{"ice_servers": servers})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	// Websocket + ICE config are public routes; the socket authenticates via
	// the `token` query parameter (browsers cannot set handshake headers).
	router.Get("/api/v1/ws", h.hub.ServeWS(h.userStore, h.tokens))
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Get("/api/v1/messaging/ice-servers", h.iceServers)
		r.Get("/api/v1/conversations/me", h.listConversations)
		r.Get("/api/v1/conversations/me/unread", h.unread)
		r.Get("/api/v1/bookings/{booking_id}/conversation", h.conversation)
		r.Get("/api/v1/bookings/{booking_id}/messages", h.messages)
		r.Post("/api/v1/bookings/{booking_id}/messages", h.send)
		r.Post("/api/v1/bookings/{booking_id}/messages/read", h.markRead)
	})
}

func pageParams(r *http.Request) (int, int) {
	limit := 50
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 100 {
		limit = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return limit, offset
}

// beforeParams reads the keyset cursor: `before` (RFC3339 created_at) and
// `before_id`. When both are present the store paginates before that message.
func beforeParams(r *http.Request) (*time.Time, string) {
	raw := r.URL.Query().Get("before")
	beforeID := r.URL.Query().Get("before_id")
	if raw == "" || beforeID == "" {
		return nil, ""
	}
	t, err := time.Parse(time.RFC3339Nano, raw)
	if err != nil {
		return nil, ""
	}
	return &t, beforeID
}
