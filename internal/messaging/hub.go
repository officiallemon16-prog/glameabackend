package messaging

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/gorilla/websocket"
)

// Websocket ops (server -> client).
const (
	opMessage        = "message"
	opCallRequest    = "call_request"
	opCallSignal     = "call_signal"
	opCallAccept     = "call_accept"
	opCallReject     = "call_reject"
	opCallCancel     = "call_cancel"
	opCallEnd        = "call_end"
	opCallUnavailable = "call_unavailable"
	opCallBusy       = "call_busy"
	opPong           = "pong"
)

// Inbound ops (client -> server).
const (
	inPing         = "ping"
	inCallRequest  = "call_request"
	inCallSignal   = "call_signal"
	inCallAccept   = "call_accept"
	inCallReject   = "call_reject"
	inCallCancel   = "call_cancel"
	inCallEnd      = "call_end"
	inTyping       = "typing"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = 50 * time.Second
	maxMessageSize = 64 * 1024
	sendBufferSize = 64
)

var allowedOrigins = map[string]bool{
	"http://localhost:3000":  true,
	"http://localhost:3001":  true,
	"http://localhost:8081":  true,
	"http://192.168.1.2:3000": true,
	"http://192.168.1.2:8080": true,
	"https://glamea.com":     true,
	"https://www.glamea.com": true,
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			// Native clients (Flutter/dart:io WebSocket) send no Origin header.
			// Auth is via the ?token= query param, so allow them through.
			return true
		}
		return allowedOrigins[origin]
	},
}

// Client is a single websocket connection belonging to a user.
type Client struct {
	UserID string
	send   chan []byte
	done   chan struct{}
	once   sync.Once
}

// Enqueue queues an outbound frame without ever blocking the broadcaster.
func (c *Client) Enqueue(payload []byte) bool {
	select {
	case c.send <- payload:
		return true
	case <-c.done:
		return false
	default:
		return false
	}
}

func (c *Client) close() {
	c.once.Do(func() { close(c.done) })
}

// Hub tracks all live websocket connections by user id. It is a thin relay:
// it knows who is online and fans payloads out to the target user's devices.
type Hub struct {
	mu       sync.Mutex
	clients  map[string]map[*Client]struct{}
	logger   *slog.Logger
	notifyFn func(ctx context.Context, userID, title, body string, data map[string]string)
}

func NewHub(logger *slog.Logger) *Hub {
	return &Hub{
		clients: map[string]map[*Client]struct{}{},
		logger:  logger,
	}
}

// SetNotifyFn sets the callback used to send push notifications (FCM) for
// events like incoming calls when the target user is offline.
func (h *Hub) SetNotifyFn(fn func(ctx context.Context, userID, title, body string, data map[string]string)) {
	h.notifyFn = fn
}

func (h *Hub) register(cl *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[cl.UserID] == nil {
		h.clients[cl.UserID] = map[*Client]struct{}{}
	}
	h.clients[cl.UserID][cl] = struct{}{}
}

func (h *Hub) unregister(cl *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set := h.clients[cl.UserID]; set != nil {
		delete(set, cl)
		if len(set) == 0 {
			delete(h.clients, cl.UserID)
		}
	}
	cl.close()
}

// online reports whether the user has at least one live connection.
func (h *Hub) online(userID string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.clients[userID]) > 0
}

// SendToUser delivers a JSON payload to every live connection of the user.
func (h *Hub) SendToUser(userID string, payload any) {
	body, err := json.Marshal(payload)
	if err != nil {
		h.logger.Error("hub marshal payload", "error", err)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for cl := range h.clients[userID] {
		if !cl.Enqueue(body) {
			h.unregister(cl)
		}
	}
}

// BroadcastMessage pushes a new message to both participants.
func (h *Hub) BroadcastMessage(senderID, recipientID string, msg *Message) {
	payload := map[string]any{"op": opMessage, "data": msg}
	h.SendToUser(senderID, payload)
	h.SendToUser(recipientID, payload)
}

// Close shuts the hub down, closing every connection.
func (h *Hub) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, set := range h.clients {
		for cl := range set {
			cl.close()
		}
	}
	h.clients = map[string]map[*Client]struct{}{}
}

// ServeWS upgrades an authenticated websocket connection and pumps frames.
// Auth uses the `token` query parameter so browsers/web clients can connect
// (they cannot set custom headers on a websocket handshake).
func (h *Hub) ServeWS(userStore *users.Store, tokens *auth.TokenManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			httpx.Fail(w, httpx.Unauthorized("missing_token", "missing bearer token"))
			return
		}
		claims, err := tokens.ParseAccessToken(token)
		if err != nil {
			httpx.Fail(w, httpx.Unauthorized("invalid_token", "invalid or expired token"))
			return
		}
		u, err := userStore.GetByID(r.Context(), claims.Subject)
		if err != nil || u.Status != users.StatusActive {
			httpx.Fail(w, httpx.Unauthorized("invalid_token", "user no longer exists"))
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		cl := &Client{
			UserID: u.ID,
			send:   make(chan []byte, sendBufferSize),
			done:   make(chan struct{}),
		}
		h.register(cl)

		go h.writePump(cl, conn)
		go h.readPump(cl, conn, userStore)
	}
}

// readPump consumes inbound frames and dispatches them.
func (h *Hub) readPump(cl *Client, conn *websocket.Conn, userStore *users.Store) {
	defer func() {
		h.unregister(cl)
		_ = conn.Close()
	}()
	conn.SetReadLimit(maxMessageSize)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			return
		}
		var frame struct {
			Op         string          `json:"op"`
			Data       json.RawMessage `json:"data"`
			ToUserID   string          `json:"to_user_id"`
			CallID     string          `json:"call_id"`
			CallType   string          `json:"call_type"`
			FromUserID string          `json:"from_user_id"`
		}
		if err := json.Unmarshal(data, &frame); err != nil {
			continue
		}

		switch frame.Op {
		case inPing:
			_ = conn.WriteJSON(map[string]any{"op": opPong})
		case inCallRequest:
			h.handleCallRequest(cl, frame, userStore)
		case inCallSignal, inCallAccept, inCallReject, inCallCancel, inCallEnd:
			if frame.ToUserID == "" || frame.CallID == "" {
				continue
			}
			relay := map[string]any{
				"op":          frame.Op,
				"data":        frame.Data,
				"call_id":     frame.CallID,
				"from_user_id": cl.UserID,
				"to_user_id":  frame.ToUserID,
			}
			h.SendToUser(frame.ToUserID, relay)
		case inTyping:
			if frame.ToUserID == "" {
				continue
			}
			relay := map[string]any{
				"op":           frame.Op,
				"data":         frame.Data,
				"from_user_id": cl.UserID,
				"to_user_id":  frame.ToUserID,
			}
			h.SendToUser(frame.ToUserID, relay)
		}
	}
}

// handleCallRequest validates the callee and relays the incoming call - or
// rejects it when the callee is offline (the caller shows "no answer").
func (h *Hub) handleCallRequest(cl *Client, frame struct {
	Op         string          `json:"op"`
	Data       json.RawMessage `json:"data"`
	ToUserID   string          `json:"to_user_id"`
	CallID     string          `json:"call_id"`
	CallType   string          `json:"call_type"`
	FromUserID string          `json:"from_user_id"`
}, userStore *users.Store) {
	if frame.ToUserID == "" || frame.CallID == "" {
		return
	}
	if frame.ToUserID == cl.UserID {
		return
	}
	if _, err := userStore.GetByID(context.Background(), frame.ToUserID); err != nil {
		h.SendToUser(cl.UserID, map[string]any{"op": opCallUnavailable, "call_id": frame.CallID, "data": frame.Data})
		return
	}
	if !h.online(frame.ToUserID) {
		h.SendToUser(cl.UserID, map[string]any{"op": opCallUnavailable, "call_id": frame.CallID, "data": frame.Data})
		// Send a push notification so the offline user's phone rings.
		if h.notifyFn != nil {
			data := map[string]string{
				"notification_type": "incoming_call",
				"call_id":          frame.CallID,
				"call_type":        frame.CallType,
				"from_user_id":     cl.UserID,
				"booking_id":       "",
			}
			if len(frame.Data) > 0 {
				var d map[string]any
				if json.Unmarshal(frame.Data, &d) == nil {
					if name, ok := d["from_name"].(string); ok {
						data["from_name"] = name
					}
				}
			}
			go h.notifyFn(context.Background(), frame.ToUserID,
				"Incoming call",
				"Someone is calling you",
				data,
			)
		}
		return
	}
	h.SendToUser(frame.ToUserID, map[string]any{
		"op":          opCallRequest,
		"call_id":     frame.CallID,
		"call_type":   frame.CallType,
		"from_user_id": cl.UserID,
		"data":        frame.Data,
	})
}

// writePump forwards queued frames, heartbeat pings and closes on done.
func (h *Hub) writePump(cl *Client, conn *websocket.Conn) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		_ = conn.Close()
	}()
	for {
		select {
		case payload, ok := <-cl.send:
			_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = conn.WriteMessage(websocket.CloseMessage, nil)
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
				return
			}
		case <-ticker.C:
			_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case <-cl.done:
			return
		}
	}
}
