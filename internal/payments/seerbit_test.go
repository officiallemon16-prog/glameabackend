package payments

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// newTestSeerbitClient spins up a fake SeerBit API and returns a client
// pointed at it together with the request log for assertions.
func newTestSeerbitClient(t *testing.T, handler http.HandlerFunc) (*seerbitClient, *[]string) {
	t.Helper()
	var calls []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, r.Method+" "+r.URL.Path+" auth="+r.Header.Get("Authorization"))
		handler(w, r)
	}))
	t.Cleanup(srv.Close)
	return newSeerbitClient(srv.URL, "PUBK_test", "SECK_test"), &calls
}

func TestSeerbitBearerToken(t *testing.T) {
	client, calls := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/encrypt/keys" {
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
		var body struct{ Key string `json:"key"` }
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Key != "SECK_test.PUBK_test" {
			t.Fatalf("expected concatenated keys, got %q", body.Key)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncryptedSecKey":{"encryptedKey":"tok123"},"message":"Successful"}}`))
	})

	ctx := context.Background()
	tok, err := client.bearerToken(ctx)
	if err != nil {
		t.Fatalf("bearerToken: %v", err)
	}
	if tok != "tok123" {
		t.Fatalf("expected tok123, got %q", tok)
	}

	// Second call must reuse the cache (no new /encrypt/keys request).
	time.Sleep(5 * time.Millisecond)
	tok2, err := client.bearerToken(ctx)
	if err != nil {
		t.Fatalf("bearerToken cached: %v", err)
	}
	if tok2 != "tok123" {
		t.Fatalf("expected cached tok123, got %q", tok2)
	}
	if len(*calls) != 1 {
		t.Fatalf("expected 1 auth request, got %d (%v)", len(*calls), *calls)
	}
}

func TestSeerbitBearerTokenSpecTypo(t *testing.T) {
	// The OpenAPI spec documents the field as "EncrytedSecKey" (missing 'p').
	client, _ := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncrytedSecKey":{"encryptedKey":"typoTok"}}}`))
	})
	tok, err := client.bearerToken(context.Background())
	if err != nil {
		t.Fatalf("bearerToken: %v", err)
	}
	if tok != "typoTok" {
		t.Fatalf("expected typoTok, got %q", tok)
	}
}

func TestSeerbitInitializeRedirectLinkObject(t *testing.T) {
	client, calls := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/encrypt/keys":
			w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncryptedSecKey":{"encryptedKey":"tok"}}}`))
		case "/payments":
			if r.Header.Get("Authorization") != "Bearer tok" {
				t.Fatalf("missing bearer token")
			}
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body["amount"] != "1250.50" {
				t.Fatalf("expected amount 1250.50, got %v", body["amount"])
			}
			if body["paymentReference"] != "SEER_ref1" {
				t.Fatalf("unexpected reference %v", body["paymentReference"])
			}
			w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","message":"Successful","payments":{"redirectLink":"https://checkout.seerbitapi.com/#/?ref=SEER_ref1"}}}`))
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	})

	link, err := client.initialize(context.Background(), seerbitInitializeInput{
		amount:    1250.50,
		currency:  "NGN",
		reference: "SEER_ref1",
		email:     "a@b.com",
		fullName:  "Ada Obi",
	})
	if err != nil {
		t.Fatalf("initialize: %v", err)
	}
	if !strings.Contains(link, "checkout.seerbitapi.com") {
		t.Fatalf("unexpected link %q", link)
	}
	if len(*calls) != 2 {
		t.Fatalf("expected 2 requests, got %v", *calls)
	}
}

func TestSeerbitInitializeRedirectLinkArray(t *testing.T) {
	client, _ := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/encrypt/keys" {
			w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncryptedSecKey":{"encryptedKey":"tok"}}}`))
			return
		}
		w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","message":"Successful","payments":[{"redirectLink":"https://checkout.seerbitapi.com/#/arr"}]}}`))
	})
	link, err := client.initialize(context.Background(), seerbitInitializeInput{amount: 100, currency: "NGN", reference: "SEER_r2"})
	if err != nil {
		t.Fatalf("initialize: %v", err)
	}
	if link != "https://checkout.seerbitapi.com/#/arr" {
		t.Fatalf("unexpected link %q", link)
	}
}

func TestSeerbitInitializeRejected(t *testing.T) {
	client, _ := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/encrypt/keys" {
			w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncryptedSecKey":{"encryptedKey":"tok"}}}`))
			return
		}
		w.Write([]byte(`{"status":"FAILED","data":{"code":"V01","message":"Validation failed"}}`))
	})
	_, err := client.initialize(context.Background(), seerbitInitializeInput{amount: 100, currency: "NGN", reference: "SEER_r3"})
	if err == nil {
		t.Fatal("expected error on rejected initialization")
	}
}

func TestSeerbitVerifyStatus(t *testing.T) {
	cases := []struct {
		name       string
		payload    string
		succeeded  bool
		failed     bool
		wantErrNil bool
	}{
		{
			name:       "success",
			payload:    `{"status":"SUCCESS","data":{"code":"00","message":"APPROVED","payments":{"gatewayCode":"00","gatewayMessage":"Successful"}}}`,
			succeeded:  true,
			wantErrNil: true,
		},
		{
			name:       "pending",
			payload:    `{"status":"SUCCESS","data":{"code":"S20","message":"APPROVED","payments":{"gatewayCode":"S20","gatewayMessage":"Transaction is pending"}}}`,
			succeeded:  false,
			failed:     false,
			wantErrNil: true,
		},
		{
			name:       "declined",
			payload:    `{"status":"SUCCESS","data":{"code":"F01","message":"DECLINED","payments":{"gatewayCode":"F01","gatewayMessage":"Declined"}}}`,
			succeeded:  false,
			failed:     true,
			wantErrNil: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := newTestSeerbitClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/encrypt/keys" {
					w.Write([]byte(`{"status":"SUCCESS","data":{"code":"00","EncryptedSecKey":{"encryptedKey":"tok"}}}`))
					return
				}
				if r.URL.Path != "/payments/query/SEER_q1" {
					t.Fatalf("unexpected path %s", r.URL.Path)
				}
				if r.Header.Get("Authorization") != "Bearer tok" {
					t.Fatalf("missing bearer token")
				}
				w.Write([]byte(tc.payload))
			})
			succ, failed, _, err := client.verifyStatus(context.Background(), "SEER_q1")
			if (err == nil) != tc.wantErrNil {
				t.Fatalf("err = %v, wantErrNil = %v", err, tc.wantErrNil)
			}
			if succ != tc.succeeded || failed != tc.failed {
				t.Fatalf("got succeeded=%v failed=%v, want %v/%v", succ, failed, tc.succeeded, tc.failed)
			}
		})
	}
}

func TestExtractRedirectLinkEmpty(t *testing.T) {
	if link := extractRedirectLink(nil); link != "" {
		t.Fatalf("expected empty, got %q", link)
	}
	if link := extractRedirectLink(json.RawMessage(`[]`)); link != "" {
		t.Fatalf("expected empty for empty array, got %q", link)
	}
}
