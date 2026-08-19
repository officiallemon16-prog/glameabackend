package payouts

import (
	"net/http"
	"strconv"

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

func (h *Handler) addAccount(w http.ResponseWriter, r *http.Request) {
	var req struct {
		BankName      string `json:"bank_name"`
		BankCode      string `json:"bank_code"`
		AccountNumber string `json:"account_number"`
		AccountName   string `json:"account_name"`
		IsDefault     bool   `json:"is_default"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	acct, err := h.svc.AddAccount(r.Context(), httpx.UserID(r), AddAccountInput{
		BankName:      req.BankName,
		BankCode:      req.BankCode,
		AccountNumber: req.AccountNumber,
		AccountName:   req.AccountName,
		IsDefault:     req.IsDefault,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"account": acct})
}

func (h *Handler) listAccounts(w http.ResponseWriter, r *http.Request) {
	accounts, err := h.svc.ListAccounts(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"accounts": accounts})
}

func (h *Handler) setDefault(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.SetDefault(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"ok": true})
}

func (h *Handler) deleteAccount(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.DeleteAccount(r.Context(), httpx.UserID(r), chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) requestPayout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Amount    float64 `json:"amount"`
		AccountID string  `json:"account_id"`
		Note      string  `json:"note"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Fail(w, httpx.BadRequest("invalid_body", "invalid request body"))
		return
	}
	payout, err := h.svc.RequestPayout(r.Context(), httpx.UserID(r), RequestPayoutInput{
		Amount:    req.Amount,
		AccountID: req.AccountID,
		Note:      req.Note,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.Created(w, map[string]any{"payout": payout})
}

func (h *Handler) listMine(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListMine(r.Context(), httpx.UserID(r), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"payouts": items, "total": total})
}

func (h *Handler) availableBalance(w http.ResponseWriter, r *http.Request) {
	available, err := h.svc.AvailableBalance(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	pending, err := h.svc.PendingBalance(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{
		"available_balance": available,
		"pending_balance":   pending,
		"total_balance":     available + pending,
	})
}

func (h *Handler) earnings(w http.ResponseWriter, r *http.Request) {
	summary, err := h.svc.EarningsSummary(r.Context(), httpx.UserID(r))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"earnings": summary})
}

// admin endpoints

func (h *Handler) listAll(w http.ResponseWriter, r *http.Request) {
	limit, offset := pageParams(r)
	items, total, err := h.svc.ListAll(r.Context(), r.URL.Query().Get("status"), limit, offset)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"payouts": items, "total": total})
}

func (h *Handler) pay(w http.ResponseWriter, r *http.Request) {
	payout, err := h.svc.Pay(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.OK(w, map[string]any{"payout": payout})
}

func (h *Handler) RegisterRoutes(router chi.Router) {
	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleProfessional))
		r.Post("/api/v1/payouts/accounts", h.addAccount)
		r.Get("/api/v1/payouts/accounts", h.listAccounts)
		r.Post("/api/v1/payouts/accounts/{id}/default", h.setDefault)
		r.Delete("/api/v1/payouts/accounts/{id}", h.deleteAccount)
		r.Post("/api/v1/payouts/requests", h.requestPayout)
		r.Get("/api/v1/payouts/requests", h.listMine)
		r.Get("/api/v1/payouts/balance", h.availableBalance)
		r.Get("/api/v1/payouts/earnings", h.earnings)
	})

	router.Group(func(r chi.Router) {
		r.Use(h.authMw)
		r.Use(auth.RequireRoles(users.RoleAdmin))
		r.Get("/api/v1/admin/payouts", h.listAll)
		r.Post("/api/v1/admin/payouts/{id}/pay", h.pay)
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
