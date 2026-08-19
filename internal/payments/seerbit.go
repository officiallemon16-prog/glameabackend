package payments

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
)

// SeerBit authenticates with an encrypted key derived from the merchant
// credentials: POST /encrypt/keys with {"key": "<secretKey>.<publicKey>"}
// returns the bearer token to use on every other call. The token is only
// valid for a short window (10 minutes) so it is cached and refreshed.
type seerbitClient struct {
	baseURL   string
	publicKey string
	secretKey string

	httpClient *http.Client

	mu    sync.Mutex
	token string
	exp   time.Time
}

const seerbitTokenTTL = 8 * time.Minute

func newSeerbitClient(baseURL, publicKey, secretKey string) *seerbitClient {
	return &seerbitClient{
		baseURL:    strings.TrimRight(baseURL, "/"),
		publicKey:  publicKey,
		secretKey:  secretKey,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *seerbitClient) bearerToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	if c.token != "" && time.Now().Before(c.exp) {
		token := c.token
		c.mu.Unlock()
		return token, nil
	}
	c.mu.Unlock()

	payload, err := json.Marshal(map[string]string{"key": c.secretKey + "." + c.publicKey})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/encrypt/keys", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not reach the payment provider")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not read the payment provider response")
	}

	var out struct {
		Status string `json:"status"`
		Data   struct {
			Code          string `json:"code"`
			Message       string `json:"message"`
			EncryptedKey  struct{ EncryptedKey string `json:"encryptedKey"` } `json:"EncryptedSecKey"`
			EncryptedTyPo struct{ EncryptedKey string `json:"encryptedKey"` } `json:"EncrytedSecKey"` // OpenAPI spec typo
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "invalid payment provider response")
	}
	token := out.Data.EncryptedKey.EncryptedKey
	if token == "" {
		token = out.Data.EncryptedTyPo.EncryptedKey
	}
	if token == "" || (out.Status != "SUCCESS" && out.Data.Code != "00") {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "payment provider rejected the credentials")
	}

	c.mu.Lock()
	c.token = token
	c.exp = time.Now().Add(seerbitTokenTTL)
	c.mu.Unlock()
	return token, nil
}

type seerbitInitializeInput struct {
	amount      float64
	currency    string
	reference   string
	email       string
	fullName    string
	callbackURL string
}

// initialize starts a Standard Checkout and returns the hosted redirectLink
// where the customer completes payment. Amounts are strings in the major unit
// (e.g. "500.00") as required by SeerBit.
func (c *seerbitClient) initialize(ctx context.Context, in seerbitInitializeInput) (string, error) {
	token, err := c.bearerToken(ctx)
	if err != nil {
		return "", err
	}

	payload, err := json.Marshal(map[string]any{
		"publicKey":        c.publicKey,
		"amount":           fmt.Sprintf("%.2f", in.amount),
		"currency":         in.currency,
		"country":          "NG",
		"paymentReference": in.reference,
		"email":            in.email,
		"fullName":         in.fullName,
		"callbackUrl":      in.callbackURL,
		"tokenize":         "false",
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/payments", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not reach the payment provider")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not read the payment provider response")
	}

	var out struct {
		Status string `json:"status"`
		Data   struct {
			Code     string          `json:"code"`
			Message  string          `json:"message"`
			Payments json.RawMessage `json:"payments"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "invalid payment provider response")
	}

	// SeerBit returns "payments" as an array in some versions and a single
	// object in others; handle both.
	redirectLink := extractRedirectLink(out.Data.Payments)
	if resp.StatusCode != http.StatusOK || out.Status != "SUCCESS" || out.Data.Code != "00" || redirectLink == "" {
		msg := out.Data.Message
		if msg == "" {
			msg = "payment provider could not initialize the payment"
		}
		return "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", msg)
	}
	return redirectLink, nil
}

func extractRedirectLink(payments json.RawMessage) string {
	if len(payments) == 0 {
		return ""
	}
	var arr []struct {
		RedirectLink string `json:"redirectLink"`
	}
	if err := json.Unmarshal(payments, &arr); err == nil {
		for _, p := range arr {
			if p.RedirectLink != "" {
				return p.RedirectLink
			}
		}
	}
	var obj struct {
		RedirectLink string `json:"redirectLink"`
	}
	if err := json.Unmarshal(payments, &obj); err == nil {
		return obj.RedirectLink
	}
	return ""
}

// verifyStatus checks the definitive transaction status for a payment
// reference. A payment only counts as successful when the response code and
// gateway code are both "00". Explicit declines, failed and cancelled
// transactions are reported as failed; anything else is left pending.
func (c *seerbitClient) verifyStatus(ctx context.Context, reference string) (succeeded, failed bool, message string, err error) {
	token, err := c.bearerToken(ctx)
	if err != nil {
		return false, false, "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/payments/query/"+reference, nil)
	if err != nil {
		return false, false, "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, false, "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not reach the payment provider")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return false, false, "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "could not read the payment provider response")
	}

	var out struct {
		Status string `json:"status"`
		Data   struct {
			Code     string          `json:"code"`
			Message  string          `json:"message"`
			Payments json.RawMessage `json:"payments"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return false, false, "", httpx.NewError(http.StatusBadGateway, "payment_provider_error", "invalid payment provider response")
	}

	gatewayCode, gatewayMessage := extractGatewayStatus(out.Data.Payments)
	code := out.Data.Code
	if code == "" {
		code = gatewayCode
	}
	message = strings.TrimSpace(gatewayMessage)
	if message == "" {
		message = out.Data.Message
	}

	if code == "00" && (gatewayCode == "" || gatewayCode == "00") {
		return true, false, message, nil
	}

	low := strings.ToLower(gatewayMessage + " " + message)
	for _, token := range []string{"declined", "failed", "cancelled", "expired", "insufficient", "error"} {
		if strings.Contains(low, token) {
			return false, true, message, nil
		}
	}
	return false, false, message, nil
}

func extractGatewayStatus(payments json.RawMessage) (gatewayCode, gatewayMessage string) {
	if len(payments) == 0 {
		return "", ""
	}
	var arr []struct {
		GatewayCode    string `json:"gatewayCode"`
		GatewayMessage string `json:"gatewayMessage"`
	}
	if err := json.Unmarshal(payments, &arr); err == nil && len(arr) > 0 {
		return arr[0].GatewayCode, arr[0].GatewayMessage
	}
	var obj struct {
		GatewayCode    string `json:"gatewayCode"`
		GatewayMessage string `json:"gatewayMessage"`
	}
	if err := json.Unmarshal(payments, &obj); err == nil {
		return obj.GatewayCode, obj.GatewayMessage
	}
	return "", ""
}
