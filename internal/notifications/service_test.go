package notifications

import "testing"

func TestStringifyData(t *testing.T) {
	got := stringifyData(map[string]any{"booking_id": "b-1", "count": 3, "ok": true})
	if got["booking_id"] != "b-1" {
		t.Errorf("booking_id = %q", got["booking_id"])
	}
	if got["count"] != "3" {
		t.Errorf("count = %q", got["count"])
	}
	if got["ok"] != "true" {
		t.Errorf("ok = %q", got["ok"])
	}
	if got["notification_type"] != "" {
		t.Errorf("notification_type should not be injected here")
	}

	if stringifyData(map[string]string{"a": "1"})["a"] != "1" {
		t.Error("string maps should pass through unchanged")
	}
	if stringifyData(nil) != nil {
		t.Error("nil data should stay nil")
	}
}
