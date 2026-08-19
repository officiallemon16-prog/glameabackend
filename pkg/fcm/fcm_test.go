package fcm

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeServiceAccount writes a minimal-but-valid service account JSON using a
// fresh RSA key and returns the file path.
func writeServiceAccount(t *testing.T, tokenURI string) string {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der := x509.MarshalPKCS1PrivateKey(key)
	block := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: der})

	sa := map[string]any{
		"project_id":   "glamea-dev",
		"client_email": "glamea-dev@appspot.gserviceaccount.com",
		"private_key":  string(block),
		"token_uri":    tokenURI,
	}
	raw, _ := json.Marshal(sa)
	path := filepath.Join(t.TempDir(), "service-account.json")
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatalf("write sa: %v", err)
	}
	return path
}

func TestNewAndConfigured(t *testing.T) {
	c, err := New(Config{ServiceAccountFile: writeServiceAccount(t, "https://oauth2.googleapis.com/token")})
	if err != nil {
		t.Fatalf("new: %v", err)
	}
	if !c.Configured() {
		t.Fatal("expected configured client")
	}
	if _, err := New(Config{ServiceAccountFile: filepath.Join(t.TempDir(), "missing.json")}); err == nil {
		t.Fatal("expected error for missing file")
	}
	if _, err := New(Config{}); err == nil {
		t.Fatal("expected error when no service account file")
	}
}

func TestParseServiceAccountRejectsBadKey(t *testing.T) {
	raw := `{"project_id":"p","client_email":"a@b.c","private_key":"not-a-pem"}`
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := parseServiceAccount(path); err == nil {
		t.Fatal("expected error for invalid private key")
	}
}

func TestBuildMessage(t *testing.T) {
	c, err := New(Config{ServiceAccountFile: writeServiceAccount(t, "https://oauth2.googleapis.com/token")})
	if err != nil {
		t.Fatal(err)
	}
	body := c.buildMessage(SendInput{
		Token: "tok-1",
		Title: "New booking",
		Body:  "You have a new request",
		Type:  "booking",
		Data:  map[string]string{"booking_id": "b-1"},
	})
	var parsed struct {
		Message struct {
			Token        string            `json:"token"`
			Notification map[string]string `json:"notification"`
			Data         map[string]string `json:"data"`
			Android      map[string]string `json:"android"`
		} `json:"message"`
	}
	if err := json.Unmarshal([]byte(body), &parsed); err != nil {
		t.Fatalf("body should be valid JSON: %v", err)
	}
	if parsed.Message.Token != "tok-1" {
		t.Errorf("token = %q, want tok-1", parsed.Message.Token)
	}
	if parsed.Message.Notification["title"] != "New booking" {
		t.Errorf("title = %q", parsed.Message.Notification["title"])
	}
	if parsed.Message.Data["notification_type"] != "booking" {
		t.Errorf("notification_type = %q", parsed.Message.Data["notification_type"])
	}
	if parsed.Message.Data["booking_id"] != "b-1" {
		t.Errorf("booking_id = %q", parsed.Message.Data["booking_id"])
	}
	if parsed.Message.Android["priority"] != "HIGH" {
		t.Errorf("android priority = %q", parsed.Message.Android["priority"])
	}
}

// newTestClient spins up one mock server handling both the OAuth2 token
// exchange (POST /token) and the FCM send endpoint, wiring a fully functional
// Client to it.
func newTestClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	c, err := New(Config{ServiceAccountFile: writeServiceAccount(t, srv.URL+"/token")})
	if err != nil {
		t.Fatal(err)
	}
	c.sendURL = srv.URL + "/send"
	c.http = srv.Client()
	return c
}

func TestSendExchangesTokenAndPostsMessage(t *testing.T) {
	var sentBody string
	var authHeader string
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/token"):
			if r.Method != http.MethodPost {
				t.Errorf("token method = %s", r.Method)
			}
			if err := r.ParseForm(); err != nil {
				t.Errorf("parse form: %v", err)
			}
			if r.Form.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" {
				t.Errorf("grant_type = %q", r.Form.Get("grant_type"))
			}
			if !strings.Contains(r.Form.Get("assertion"), ".") {
				t.Errorf("assertion is not a JWT")
			}
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"access_token":"access-123","expires_in":3600}`)
		default:
			authHeader = r.Header.Get("Authorization")
			b, _ := io.ReadAll(r.Body)
			sentBody = string(b)
			w.WriteHeader(http.StatusOK)
		}
	})

	err := c.Send(context.Background(), SendInput{
		Token: "tok-1",
		Title: "Hi",
		Body:  "Body",
		Type:  "message",
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if authHeader != "Bearer access-123" {
		t.Errorf("authorization = %q, want Bearer access-123", authHeader)
	}
	if !strings.Contains(sentBody, `"token":"tok-1"`) {
		t.Errorf("send body = %s", sentBody)
	}
}

func TestSendNotConfigured(t *testing.T) {
	c := &Client{}
	if err := c.Send(context.Background(), SendInput{Token: "t"}); err != ErrNotConfigured {
		t.Fatalf("err = %v, want ErrNotConfigured", err)
	}
}

func TestSendUnregisteredToken(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"access_token":"access-123","expires_in":3600}`)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	})
	if err := c.Send(context.Background(), SendInput{Token: "stale", Title: "x", Body: "y"}); err != ErrTokenUnregistered {
		t.Fatalf("err = %v, want ErrTokenUnregistered", err)
	}
}
