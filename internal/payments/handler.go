package payments

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	svc              *Service
	authMw           func(http.Handler) http.Handler
	webhookRateLimit func(http.Handler) http.Handler
}

func NewHandler(svc *Service, authMw func(http.Handler) http.Handler, webhookRateLimitPerMinute int) *Handler {
	return &Handler{svc: svc, authMw: authMw, webhookRateLimit: httpx.RateLimitMiddleware(webhookRateLimitPerMinute)}
}

func (h *Handler) createIntent(w http.ResponseWriter, r *http.Request) {
	var req struct {
		BookingID  string `json:"booking_id"`
		AmountType string `json:"amount_type"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	intent, err := h.svc.CreateIntent(r.Context(), httpx.UserID(r), CreateIntentInput{
		BookingID:  req.BookingID,
		AmountType: req.AmountType,
	})
	if err != nil {
		httpx.Fail(w, wrapIntentError(err))
		return
	}
	httpx.Created(w, map[string]any{"intent": intent})
}

func wrapIntentError(err error) error {
	var apiErr *httpx.APIError
	if errors.As(err, &apiErr) {
		return err
	}
	return httpx.Internal("payment_error", "Could not process payment. Please try again.")
}

func (h *Handler) getIntent(w http.ResponseWriter, r *http.Request) {
	intent, err := h.svc.GetIntent(r.Context(), httpx.UserID(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, wrapIntentError(err))
		return
	}
	httpx.OK(w, map[string]any{"intent": intent})
}

func (h *Handler) getIntentForBooking(w http.ResponseWriter, r *http.Request) {
	intent, err := h.svc.IntentForBooking(r.Context(), httpx.UserID(r), chi.URLParam(r, "bookingId"))
	if err != nil {
		httpx.Fail(w, wrapIntentError(err))
		return
	}
	httpx.OK(w, map[string]any{"intent": intent})
}

// callback is the Paystack redirect target after a customer completes checkout.
// The app polls the intent endpoint, so this is just a friendly landing page.
func (h *Handler) callback(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	io.WriteString(w, "<!doctype html><html><head><meta charset=\"utf-8\"><title>Glamea</title></head>"+
		"<body style=\"font-family:sans-serif;text-align:center;padding-top:64px\">"+
		"<h2>Payment received</h2>"+
		"<p>You can close this tab and return to the Glamea app.</p>"+
		"</body></html>")
}

func (h *Handler) wallet(w http.ResponseWriter, r *http.Request) {
	bal, err := h.svc.Balance(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, wrapIntentError(err))
		return
	}
	httpx.OK(w, map[string]any{"wallet": bal})
}

func (h *Handler) transactions(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.Transactions(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, wrapIntentError(err))
		return
	}
	httpx.OK(w, map[string]any{"transactions": items, "total": total})
}

// webhook receives gateway callbacks. Body: {"reference": "...", "event": "charge.success"}.
func (h *Handler) webhook(w http.ResponseWriter, r *http.Request) {
	gateway := chi.URLParam(r, "gateway")

	rawBody, err := io.ReadAll(r.Body)
	if err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "could not read request body"))
		return
	}

	signature := r.Header.Get("X-Paystack-Signature")
	if signature == "" {
		signature = r.Header.Get("Verif-Hash")
	}
	if err := h.svc.VerifyWebhookSignature(gateway, rawBody, signature); err != nil {
		httpx.Fail(w, err)
		return
	}

	var req struct {
		Reference        string `json:"reference"`
		PaymentReference string `json:"paymentReference"`
		Event            string `json:"event"`
		EventType        string `json:"eventType"`
		EventID          string `json:"event_id"`
		EventId          string `json:"eventId"`
		Status           string `json:"status"`
		Data             struct {
			Reference        string `json:"reference"`
			TxRef            string `json:"tx_ref"`
			PaymentReference string `json:"paymentReference"`
			EventID          string `json:"id"`
			Status           string `json:"status"`
			GatewayCode      string `json:"gatewayCode"`
			GatewayMessage   string `json:"gatewayMessage"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rawBody, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}

	// Paystack and Flutterwave nest the charge details under "data"; SeerBit
	// uses paymentReference and eventType.
	reference := req.Reference
	if reference == "" {
		reference = req.PaymentReference
	}
	if reference == "" {
		reference = req.Data.Reference
	}
	if reference == "" {
		reference = req.Data.TxRef
	}
	if reference == "" {
		reference = req.Data.PaymentReference
	}
	eventID := req.EventID
	if eventID == "" {
		eventID = req.EventId
	}
	if eventID == "" {
		eventID = req.Data.EventID
	}
	status := req.Status
	if status == "" {
		status = req.Data.Status
	}
	event := req.Event
	if event == "" {
		event = req.EventType
	}

	if reference == "" {
		httpx.Fail(w, httpx.BadRequest("reference_required", "reference is required"))
		return
	}

	success := event == "charge.success" || event == "charge.completed" ||
		event == "payment.success" || event == "payment.completed" ||
		status == "success" || status == "successful" || status == "completed" ||
		req.Data.GatewayCode == "00" ||
		strings.Contains(strings.ToLower(req.Data.GatewayMessage), "success")
	if !success {
		httpx.OK(w, map[string]any{"ok": true})
		return
	}

	inserted, err := h.svc.RecordWebhookEvent(r.Context(), gateway, eventID, reference, rawBody)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	if !inserted {
		httpx.OK(w, map[string]any{"ok": true, "duplicate": true})
		return
	}

	intent, err := h.svc.ConfirmByReference(r.Context(), gateway, reference)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true, "intent_id": intent.ID, "status": intent.Status})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Post("/api/v1/payments/intents", h.createIntent)
		r.Get("/api/v1/payments/intents/{id}", h.getIntent)
		r.Get("/api/v1/payments/intents/by-booking/{bookingId}", h.getIntentForBooking)
		r.Get("/api/v1/payments/wallet", h.wallet)
		r.Get("/api/v1/payments/transactions", h.transactions)
	})
	router.Group(func(r chi.Router) {
		r.Use(h.webhookRateLimit)
		r.Post("/api/v1/payments/webhook/{gateway}", h.webhook)
		r.Get("/api/v1/payments/callback", h.callback)
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
