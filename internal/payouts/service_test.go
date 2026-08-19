package payouts

import (
	"testing"
	"time"
)

func TestStartOfWeek(t *testing.T) {
	// Wednesday 2026-08-12 -> Monday 2026-08-10.
	wed := time.Date(2026, 8, 12, 15, 30, 0, 0, time.UTC)
	want := time.Date(2026, 8, 10, 0, 0, 0, 0, time.UTC)
	if got := startOfWeek(wed); !got.Equal(want) {
		t.Errorf("startOfWeek(Wed) = %v, want %v", got, want)
	}

	// Monday stays on Monday.
	mon := time.Date(2026, 8, 10, 1, 0, 0, 0, time.UTC)
	if got := startOfWeek(mon); !got.Equal(want) {
		t.Errorf("startOfWeek(Mon) = %v, want %v", got, want)
	}

	// Sunday 2026-08-09 -> Monday 2026-08-03.
	sun := time.Date(2026, 8, 9, 23, 0, 0, 0, time.UTC)
	if got := startOfWeek(sun); !got.Equal(time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("startOfWeek(Sun) = %v, want 2026-08-03", got)
	}
}

func TestStartOfMonth(t *testing.T) {
	got := startOfMonth(time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC))
	want := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("startOfMonth = %v, want %v", got, want)
	}
}
