package media

import (
	"testing"

	"github.com/glamea/glamea-backend/pkg/cloudinary"
)

func TestImageExt(t *testing.T) {
	tests := []struct {
		filename string
		ext      string
		ok       bool
	}{
		{"photo.jpg", ".jpg", true},
		{"photo.JPEG", ".jpg", true},
		{"photo.jpeg", ".jpg", true},
		{"photo.png", ".png", true},
		{"photo.webp", ".webp", true},
		{"photo.gif", ".gif", true},
		{"photo.heic", ".heic", true},
		{"photo.heif", ".heic", true},
		{"photo.txt", "", false},
		{"noext", "", false},
	}
	for _, tt := range tests {
		ext, ok := imageExt(tt.filename)
		if ext != tt.ext || ok != tt.ok {
			t.Errorf("imageExt(%q) = (%q, %v), want (%q, %v)", tt.filename, ext, ok, tt.ext, tt.ok)
		}
	}
}

func TestUploadMode(t *testing.T) {
	svc := NewService(nil, &cloudinary.Client{}, Options{})
	if got := svc.UploadMode(); got != modeLocal {
		t.Errorf("unconfigured cloudinary UploadMode = %q, want %q", got, modeLocal)
	}
}

func TestMaxBytesDefault(t *testing.T) {
	svc := NewService(nil, nil, Options{})
	if got := svc.MaxBytes(); got != 10*1024*1024 {
		t.Errorf("default MaxBytes = %d, want %d", got, 10*1024*1024)
	}
	svc = NewService(nil, nil, Options{MaxBytes: 2048})
	if got := svc.MaxBytes(); got != 2048 {
		t.Errorf("MaxBytes = %d, want 2048", got)
	}
}

func TestSaveLocalUploadErrors(t *testing.T) {
	svc := NewService(nil, nil, Options{})
	_, err := svc.SaveLocalUpload(t.Context(), "u1", "photo.jpg", []byte("data"))
	if err == nil {
		t.Fatal("expected error when UploadDir is empty")
	}
	svc = NewService(nil, nil, Options{UploadDir: t.TempDir(), AppURL: "http://localhost:8080"})
	_, err = svc.SaveLocalUpload(t.Context(), "u1", "photo.txt", []byte("data"))
	if err == nil {
		t.Fatal("expected error for unsupported file type")
	}
}
