package fcm

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// fcmSendURL is the Firebase Cloud Messaging HTTP v1 endpoint.
const fcmSendURL = "https://fcm.googleapis.com/v1/projects/%s/messages:send"

// ErrNotConfigured is returned by Send when FCM credentials are missing.
var ErrNotConfigured = errors.New("fcm is not configured")

// ErrTokenUnregistered indicates the device token is no longer valid and
// should be removed (FCM returns 404 for such tokens).
var ErrTokenUnregistered = errors.New("device token is not registered")

// ServiceAccount mirrors the fields of the Firebase service-account JSON we
// need to mint OAuth2 assertions.
type ServiceAccount struct {
	ProjectID     string `json:"project_id"`
	ClientEmail   string `json:"client_email"`
	PrivateKey    string `json:"private_key"`
	TokenURI      string `json:"token_uri"`
	oauthTokenURI string
	privateKey    *rsa.PrivateKey
}

// Config holds the credentials for the FCM client.
type Config struct {
	// ProjectID is the Firebase project id. When empty it is read from the
	// service account JSON.
	ProjectID string
	// ServiceAccountFile is the path to the Firebase service-account JSON.
	ServiceAccountFile string
}

// Client sends Firebase Cloud Messaging HTTP v1 messages.
type Client struct {
	projectID string
	sa        *ServiceAccount
	sendURL   string

	mu             sync.Mutex
	cachedToken    string
	tokenExpiresAt time.Time
	tokenInFlight  bool
	tokenWaiters   []chan struct{}

	http *http.Client
}

// New builds a Client from a service-account JSON file. Returns an error when
// the file is missing or malformed; the caller decides whether to fall back to
// a no-op sender (see Configured).
func New(cfg Config) (*Client, error) {
	if cfg.ServiceAccountFile == "" {
		return nil, errors.New("fcm service account file is required")
	}
	sa, err := parseServiceAccount(cfg.ServiceAccountFile)
	if err != nil {
		return nil, err
	}
	projectID := cfg.ProjectID
	if projectID == "" {
		projectID = sa.ProjectID
	}
	return &Client{
		projectID: projectID,
		sa:        sa,
		sendURL:   fmt.Sprintf(fcmSendURL, projectID),
		http:      &http.Client{Timeout: 15 * time.Second},
	}, nil
}

// Configured reports whether real push delivery is available.
func (c *Client) Configured() bool {
	return c != nil && c.projectID != "" && c.sa != nil && c.sa.privateKey != nil
}

// SendInput is a single push message for one device.
type SendInput struct {
	Token string
	Title string
	Body  string
	Type  string
	Data  map[string]string
}

// Send delivers a notification message to one device via HTTP v1.
func (c *Client) Send(ctx context.Context, in SendInput) error {
	if !c.Configured() {
		return ErrNotConfigured
	}
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}

	body := c.buildMessage(in)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.sendURL, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	res, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(res.Body, 4096))

	if res.StatusCode == http.StatusNotFound {
		return ErrTokenUnregistered
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("fcm send failed: %d %s", res.StatusCode, strings.TrimSpace(string(b)))
	}
	return nil
}

// buildMessage renders the HTTP v1 request body.
func (c *Client) buildMessage(in SendInput) string {
	data := make(map[string]string, len(in.Data)+1)
	for k, v := range in.Data {
		data[k] = v
	}
	data["notification_type"] = in.Type

	msg := fcmMessage{}
	msg.Message.Token = in.Token
	msg.Message.Notification = map[string]string{"title": in.Title, "body": in.Body}
	msg.Message.Data = data

	if in.Type == "incoming_call" {
		// Call notifications get a dedicated channel with sound and vibration.
		msg.Message.Android.Priority = "HIGH"
		msg.Message.Android.Notification.ChannelID = "incoming_call"
		msg.Message.Android.Notification.Sound = "default"
		msg.Message.Android.Notification.ClickAction = "OPEN_CHAT"

		// iOS: use a VoIP-style critical alert with sound.
		msg.Message.APNS = &fcmAPNS{
			Payload: fcmAPNSPayload{
				APS: fcmAPNSAps{
					Alert: &fcmAPNSAlert{Title: in.Title, Body: in.Body},
					Sound: &APNSSound{Critical: 1, Volume: 1.0, Name: "ringtone.caf"},
					ContentAvailable: true,
					MutableContent:   true,
				},
			},
		}
	} else {
		msg.Message.Android.Priority = "HIGH"
	}

	out, _ := json.Marshal(msg)
	return string(out)
}

// APNSSound supports both simple string and critical alert sound objects.
type APNSSound struct {
	Critical int     `json:"critical,omitempty"`
	Volume   float64 `json:"volume,omitempty"`
	Name     string  `json:"name,omitempty"`
}

// fcmAPNS wraps the APNS payload for HTTP v1 messages.
type fcmAPNS struct {
	Payload fcmAPNSPayload `json:"payload"`
}

type fcmAPNSPayload struct {
	APS fcmAPNSAps `json:"aps"`
}

type fcmAPNSAps struct {
	Alert            *fcmAPNSAlert `json:"alert"`
	Sound            *APNSSound    `json:"sound"`
	ContentAvailable bool          `json:"content-available"`
	MutableContent   bool          `json:"mutable-content"`
}

type fcmAPNSAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// fcmMessage is the top-level FCM HTTP v1 request body.
type fcmMessage struct {
	Message fcmMessageBody `json:"message"`
}

type fcmMessageBody struct {
	Token        string            `json:"token"`
	Notification map[string]string `json:"notification"`
	Data         map[string]string `json:"data"`
	Android      struct {
		Priority     string `json:"priority"`
		Notification struct {
			ChannelID   string `json:"channel_id"`
			Sound       string `json:"sound"`
			ClickAction string `json:"click_action"`
			BodyLocKey  string `json:"body_loc_key"`
		} `json:"notification"`
	} `json:"android"`
	APNS *fcmAPNS `json:"apns,omitempty"`
}

// MarshalJSON implements json.Marshaler for APNSSound.
func (s *APNSSound) MarshalJSON() ([]byte, error) {
	if s.Critical > 0 {
		return json.Marshal(struct {
			Critical int     `json:"critical"`
			Volume   float64 `json:"volume"`
			Name     string  `json:"name"`
		}{Critical: s.Critical, Volume: s.Volume, Name: s.Name})
	}
	if s.Name != "" {
		return json.Marshal(s.Name)
	}
	return json.Marshal("default")
}

// accessToken returns a cached OAuth2 access token for the Firebase scope,
// minting a new one when the cached token is missing or expired.
// Concurrent callers share a single token exchange (no thundering herd).
func (c *Client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	if c.cachedToken != "" && time.Now().Before(c.tokenExpiresAt.Add(-1*time.Minute)) {
		t := c.cachedToken
		c.mu.Unlock()
		return t, nil
	}
	// If another goroutine is already refreshing, wait for it.
	if c.tokenInFlight {
		wait := make(chan struct{})
		c.tokenWaiters = append(c.tokenWaiters, wait)
		c.mu.Unlock()
		select {
		case <-wait:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		// Re-check after wake.
		c.mu.Lock()
		if c.cachedToken != "" && time.Now().Before(c.tokenExpiresAt.Add(-1*time.Minute)) {
			t := c.cachedToken
			c.mu.Unlock()
			return t, nil
		}
		c.mu.Unlock()
		return "", errors.New("fcm token refresh failed while waiting")
	}
	c.tokenInFlight = true
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.tokenInFlight = false
		waiters := c.tokenWaiters
		c.tokenWaiters = nil
		c.mu.Unlock()
		for _, w := range waiters {
			close(w)
		}
	}()

	assertion, err := c.sa.assertion()
	if err != nil {
		return "", err
	}

	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", assertion)

	uri := c.sa.oauthTokenURI
	if uri == "" {
		uri = "https://oauth2.googleapis.com/token"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, uri, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	res, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(res.Body, 8192))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return "", fmt.Errorf("fcm token exchange failed: %d %s", res.StatusCode, strings.TrimSpace(string(b)))
	}

	var parsed struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(b, &parsed); err != nil {
		return "", err
	}
	if parsed.AccessToken == "" {
		return "", errors.New("fcm token exchange returned no access token")
	}

	c.mu.Lock()
	c.cachedToken = parsed.AccessToken
	c.tokenExpiresAt = time.Now().Add(time.Duration(parsed.ExpiresIn) * time.Second)
	t := c.cachedToken
	c.mu.Unlock()
	return t, nil
}

// assertion builds the signed JWT used to obtain an OAuth2 access token.
func (sa *ServiceAccount) assertion() (string, error) {
	if sa.privateKey == nil {
		return "", ErrNotConfigured
	}
	now := time.Now()
	claims := jwt.MapClaims{
		"iss":   sa.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   sa.oauthTokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(sa.privateKey)
}

func parseServiceAccount(pathOrJSON string) (*ServiceAccount, error) {
	var raw []byte
	var err error
	// If the value starts with '{', treat it as inline JSON (useful for
	// environments like Render where mounting files is inconvenient).
	if strings.HasPrefix(strings.TrimSpace(pathOrJSON), "{") {
		raw = []byte(pathOrJSON)
	} else {
		raw, err = os.ReadFile(pathOrJSON)
		if err != nil {
			return nil, err
		}
	}
	var sa ServiceAccount
	if err := json.Unmarshal(raw, &sa); err != nil {
		return nil, fmt.Errorf("parse service account: %w", err)
	}
	if sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("service account missing client_email or private_key")
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, errors.New("service account private key is not a PEM block")
	}
	key, err := parseRSAPrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse private key: %w", err)
	}
	sa.privateKey = key
	if sa.TokenURI == "" {
		sa.oauthTokenURI = "https://oauth2.googleapis.com/token"
	} else {
		sa.oauthTokenURI = sa.TokenURI
	}
	return &sa, nil
}

func parseRSAPrivateKey(der []byte) (*rsa.PrivateKey, error) {
	if k, err := x509.ParsePKCS8PrivateKey(der); err == nil {
		if rk, ok := k.(*rsa.PrivateKey); ok {
			return rk, nil
		}
	}
	if k, err := x509.ParsePKCS1PrivateKey(der); err == nil {
		return k, nil
	}
	return nil, errors.New("unsupported private key format")
}
