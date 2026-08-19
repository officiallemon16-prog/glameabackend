package verification

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

const (
	StageIdentity    = "IDENTITY"
	StageBusiness    = "BUSINESS"
	StageLocation    = "LOCATION"
	StageCertificate = "CERTIFICATE"
)

const (
	DocPending   = "PENDING"
	DocReviewing = "REVIEWING"
	DocApproved  = "APPROVED"
	DocRejected  = "REJECTED"
)

type Document struct {
	ID             string     `json:"id"`
	ProfessionalID string     `json:"professional_id"`
	Stage          string     `json:"stage"`
	DocumentType   string     `json:"document_type"`
	MediaAssetID   *string    `json:"media_asset_id,omitempty"`
	Status         string     `json:"status"`
	ReviewerID     *string    `json:"reviewer_id,omitempty"`
	ReviewNote     string     `json:"review_note,omitempty"`
	SubmittedAt    time.Time  `json:"submitted_at"`
	ReviewedAt     *time.Time `json:"reviewed_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Create(ctx context.Context, d *Document) (*Document, error) {
	if d.ID == "" {
		d.ID = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO verification_documents
		(id, professional_id, stage, document_type, media_asset_id, status, submitted_at)
		VALUES (?, ?, ?, ?, ?, ?, NOW())`,
		d.ID, d.ProfessionalID, d.Stage, d.DocumentType, nullString(d.MediaAssetID), d.Status)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, d.ID)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Document, error) {
	return s.scanOne(ctx, `SELECT `+cols()+` FROM verification_documents WHERE id = ?`, id)
}

func (s *Store) ListByProfessional(ctx context.Context, professionalID string) ([]*Document, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols()+` FROM verification_documents
		WHERE professional_id = ? ORDER BY created_at DESC`, professionalID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.scanMany(rows)
}

func (s *Store) ListPending(ctx context.Context, limit int) ([]*Document, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+cols()+` FROM verification_documents
		WHERE status IN ('PENDING','REVIEWING') ORDER BY submitted_at ASC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.scanMany(rows)
}

func (s *Store) SetStatus(ctx context.Context, id, status string, reviewerID string, note string) (*Document, error) {
	_, err := s.db.ExecContext(ctx, `UPDATE verification_documents SET
		status = ?, reviewer_id = ?, review_note = ?, reviewed_at = NOW() WHERE id = ?`,
		status, nullString(&reviewerID), note, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) AddEvent(ctx context.Context, professionalID, stage, action, actorID string, metadata map[string]any) error {
	var metaJSON sql.NullString
	if metadata != nil {
		b, err := json.Marshal(metadata)
		if err != nil {
			return err
		}
		metaJSON = sql.NullString{String: string(b), Valid: true}
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO verification_events
		(id, professional_id, stage, action, actor_id, metadata)
		VALUES (?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), professionalID, stage, action, nullString(&actorID), metaJSON)
	return err
}

func cols() string {
	return `id, professional_id, stage, document_type, media_asset_id, status, reviewer_id, review_note,
		submitted_at, reviewed_at, created_at, updated_at`
}

func (s *Store) scanOne(ctx context.Context, q string, args ...any) (*Document, error) {
	row := s.db.QueryRowContext(ctx, q, args...)
	var d Document
	var media, reviewer, note sql.NullString
	var reviewed sql.NullTime
	err := row.Scan(&d.ID, &d.ProfessionalID, &d.Stage, &d.DocumentType, &media, &d.Status, &reviewer,
		&note, &d.SubmittedAt, &reviewed, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("document_not_found", "verification document not found")
		}
		return nil, err
	}
	if media.Valid {
		d.MediaAssetID = &media.String
	}
	if reviewer.Valid {
		d.ReviewerID = &reviewer.String
	}
	if note.Valid {
		d.ReviewNote = note.String
	}
	if reviewed.Valid {
		d.ReviewedAt = &reviewed.Time
	}
	return &d, nil
}

func (s *Store) scanMany(rows *sql.Rows) ([]*Document, error) {
	defer rows.Close()
	out := []*Document{}
	for rows.Next() {
		var d Document
		var media, reviewer, note sql.NullString
		var reviewed sql.NullTime
		if err := rows.Scan(&d.ID, &d.ProfessionalID, &d.Stage, &d.DocumentType, &media, &d.Status, &reviewer,
			&note, &d.SubmittedAt, &reviewed, &d.CreatedAt, &d.UpdatedAt); err != nil {
			return nil, err
		}
		if media.Valid {
			d.MediaAssetID = &media.String
		}
		if reviewer.Valid {
			d.ReviewerID = &reviewer.String
		}
		if note.Valid {
			d.ReviewNote = note.String
		}
		if reviewed.Valid {
			d.ReviewedAt = &reviewed.Time
		}
		out = append(out, &d)
	}
	return out, rows.Err()
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}
