package media

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/pkg/cloudinary"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	modeCloudinary = "cloudinary"
	modeLocal      = "local"
)

// Options configures how media is stored.
type Options struct {
	// UploadDir is the directory where local uploads are written.
	UploadDir string
	// AppURL is the public base URL used to build secure_url for local uploads.
	AppURL string
	// MaxBytes is the maximum accepted upload size in bytes.
	MaxBytes int64
}

type Asset struct {
	ID           string    `json:"id"`
	UploaderID   string    `json:"uploader_id"`
	Provider     string    `json:"provider"`
	PublicID     string    `json:"public_id"`
	ResourceType string    `json:"resource_type"`
	Format       *string   `json:"format,omitempty"`
	Width        *int      `json:"width,omitempty"`
	Height       *int      `json:"height,omitempty"`
	DurationMs   *int      `json:"duration_ms,omitempty"`
	Bytes        *int64    `json:"bytes,omitempty"`
	SecureURL    *string   `json:"secure_url,omitempty"`
	Folder       string    `json:"folder,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type Service struct {
	store *Store
	cld   *cloudinary.Client
	opts  Options
}

func NewService(store *Store, cld *cloudinary.Client, opts Options) *Service {
	return &Service{store: store, cld: cld, opts: opts}
}

// UploadMode reports the active upload strategy. When Cloudinary is not
// configured the service falls back to storing files on disk.
func (s *Service) UploadMode() string {
	if s.cld != nil && s.cld.Configured() {
		return modeCloudinary
	}
	return modeLocal
}

// MaxBytes returns the maximum accepted upload size in bytes.
func (s *Service) MaxBytes() int64 {
	if s.opts.MaxBytes <= 0 {
		return 10 * 1024 * 1024
	}
	return s.opts.MaxBytes
}

type UploadSignatureInput struct {
	Folder       string
	PublicID     string
	ResourceType string
}

func (s *Service) UploadSignature(in UploadSignatureInput) (*cloudinary.Signature, error) {
	if s.cld == nil || !s.cld.Configured() {
		return nil, httpx.ServiceUnavailable("cloudinary_not_configured", "cloudinary is not configured")
	}
	return s.cld.UploadSignature(in.Folder, in.PublicID, in.ResourceType)
}

type RegisterAssetInput struct {
	Provider     string
	PublicID     string
	ResourceType string
	Format       *string
	Width        *int
	Height       *int
	DurationMs   *int
	Bytes        *int64
	SecureURL    *string
	Folder       string
}

func (s *Service) RegisterAsset(ctx context.Context, uploaderID string, in RegisterAssetInput) (*Asset, error) {
	if in.PublicID == "" {
		return nil, httpx.BadRequest("public_id_required", "public_id is required")
	}
	if in.Provider == "" {
		in.Provider = "cloudinary"
	}
	if in.ResourceType == "" {
		in.ResourceType = "image"
	}
	return s.store.Create(ctx, uploaderID, in)
}

func (s *Service) Get(ctx context.Context, id string) (*Asset, error) {
	return s.store.GetByID(ctx, id)
}

// SaveLocalUpload stores an image on disk and registers it as a media asset.
// The stored file is served at AppURL + /uploads/<name>.
func (s *Service) SaveLocalUpload(ctx context.Context, uploaderID, filename string, data []byte) (*Asset, error) {
	if s.opts.UploadDir == "" {
		return nil, httpx.ServiceUnavailable("local_media_not_configured", "local media storage is not configured")
	}
	ext, ok := imageExt(filename)
	if !ok {
		return nil, httpx.BadRequest("unsupported_file_type", "only jpg, png, webp, gif, heic and heif images are supported")
	}
	if len(data) == 0 || int64(len(data)) > s.MaxBytes() {
		return nil, httpx.BadRequest("file_too_large", "file exceeds the maximum allowed size")
	}
	if err := os.MkdirAll(s.opts.UploadDir, 0o755); err != nil {
		return nil, err
	}
	name := uuid.NewString() + ext
	if err := os.WriteFile(filepath.Join(s.opts.UploadDir, name), data, 0o644); err != nil {
		return nil, err
	}
	url := strings.TrimRight(s.opts.AppURL, "/") + "/uploads/" + name
	format := strings.TrimPrefix(ext, ".")
	bytes := int64(len(data))
	return s.store.Create(ctx, uploaderID, RegisterAssetInput{
		Provider:     "local",
		PublicID:     name,
		ResourceType: "image",
		Format:       &format,
		Bytes:        &bytes,
		SecureURL:    &url,
		Folder:       "uploads",
	})
}

func imageExt(filename string) (string, bool) {
	switch strings.ToLower(strings.TrimPrefix(filepath.Ext(filename), ".")) {
	case "jpg", "jpeg":
		return ".jpg", true
	case "png":
		return ".png", true
	case "webp":
		return ".webp", true
	case "gif":
		return ".gif", true
	case "heic", "heif":
		return ".heic", true
	}
	return "", false
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (st *Store) Create(ctx context.Context, uploaderID string, in RegisterAssetInput) (*Asset, error) {
	id := uuid.NewString()
	_, err := st.db.ExecContext(ctx, `INSERT INTO media_assets
		(id, uploader_id, provider, public_id, resource_type, format, width, height, duration_ms, bytes, secure_url, folder)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, uploaderID, in.Provider, in.PublicID, in.ResourceType,
		nullString(in.Format), nullInt(in.Width), nullInt(in.Height), nullInt(in.DurationMs),
		nullInt64(in.Bytes), nullString(in.SecureURL), in.Folder)
	if err != nil {
		return nil, err
	}
	return st.GetByID(ctx, id)
}

func (st *Store) GetByID(ctx context.Context, id string) (*Asset, error) {
	var a Asset
	var format, url, folder sql.NullString
	var width, height, duration sql.NullInt64
	var bytes sql.NullInt64
	err := st.db.QueryRowContext(ctx, `SELECT id, uploader_id, provider, public_id, resource_type,
		format, width, height, duration_ms, bytes, secure_url, folder, created_at
		FROM media_assets WHERE id = ?`, id).
		Scan(&a.ID, &a.UploaderID, &a.Provider, &a.PublicID, &a.ResourceType,
			&format, &width, &height, &duration, &bytes, &url, &folder, &a.CreatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("media_not_found", "media asset not found")
		}
		return nil, err
	}
	if format.Valid {
		a.Format = &format.String
	}
	if width.Valid {
		w := int(width.Int64)
		a.Width = &w
	}
	if height.Valid {
		h := int(height.Int64)
		a.Height = &h
	}
	if duration.Valid {
		d := int(duration.Int64)
		a.DurationMs = &d
	}
	if bytes.Valid {
		a.Bytes = &bytes.Int64
	}
	if url.Valid {
		a.SecureURL = &url.String
	}
	a.Folder = folder.String
	return &a, nil
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}

func nullInt(v *int) sql.NullInt64 {
	if v == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*v), Valid: true}
}

func nullInt64(v *int64) sql.NullInt64 {
	if v == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: *v, Valid: true}
}
