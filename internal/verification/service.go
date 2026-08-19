package verification

import (
	"context"

	"github.com/glamea/glamea-backend/internal/admin"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store    *Store
	proStore *professionals.Store
	audit    *admin.AuditStore
}

func NewService(store *Store, proStore *professionals.Store, audit *admin.AuditStore) *Service {
	return &Service{store: store, proStore: proStore, audit: audit}
}

type SubmitInput struct {
	Stage        string
	DocumentType string
	MediaAssetID *string
}

func (s *Service) Submit(ctx context.Context, userID string, in SubmitInput) (*Document, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	if !validStage(in.Stage) {
		return nil, httpx.BadRequest("invalid_stage", "stage must be one of IDENTITY, BUSINESS, LOCATION, CERTIFICATE")
	}
	if in.DocumentType == "" {
		return nil, httpx.BadRequest("document_type_required", "document type is required")
	}
	if in.MediaAssetID == nil || *in.MediaAssetID == "" {
		return nil, httpx.BadRequest("media_asset_required", "media_asset_id is required")
	}

	doc := &Document{
		ProfessionalID: prof.ID,
		Stage:          in.Stage,
		DocumentType:   in.DocumentType,
		MediaAssetID:   in.MediaAssetID,
		Status:         DocPending,
	}
	created, err := s.store.Create(ctx, doc)
	if err != nil {
		return nil, err
	}
	_ = s.store.AddEvent(ctx, prof.ID, in.Stage, "document.submitted", userID, nil)
	return created, nil
}

func (s *Service) GetOwn(ctx context.Context, userID string) ([]*Document, error) {
	prof, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return s.store.ListByProfessional(ctx, prof.ID)
}

func (s *Service) ListAll(ctx context.Context, onlyPending bool) ([]*Document, error) {
	if onlyPending {
		return s.store.ListPending(ctx, 100)
	}
	return s.store.ListPending(ctx, 1000)
}

type ReviewInput struct {
	Approve bool
	Note    string
}

func (s *Service) Review(ctx context.Context, adminID, docID string, in ReviewInput) (*Document, error) {
	doc, err := s.store.GetByID(ctx, docID)
	if err != nil {
		return nil, err
	}

	status := DocRejected
	action := "document.rejected"
	if in.Approve {
		status = DocApproved
		action = "document.approved"
	}

	updated, err := s.store.SetStatus(ctx, docID, status, adminID, in.Note)
	if err != nil {
		return nil, err
	}

	_ = s.store.AddEvent(ctx, doc.ProfessionalID, doc.Stage, action, adminID, map[string]any{
		"document_id": docID,
		"note":        in.Note,
	})

	if err := s.recomputeVerificationStatus(ctx, doc.ProfessionalID); err != nil {
		return nil, err
	}

	if err := s.audit.Log(ctx, admin.AuditEntry{
		ActorID:     adminID,
		ActorRole:   "ADMIN",
		Action:      action,
		EntityType:  "verification_document",
		EntityID:    docID,
		BeforeState: map[string]any{"status": doc.Status},
		AfterState:  map[string]any{"status": status, "note": in.Note},
	}); err != nil {
		return nil, err
	}
	return updated, nil
}

func (s *Service) recomputeVerificationStatus(ctx context.Context, professionalID string) error {
	docs, err := s.store.ListByProfessional(ctx, professionalID)
	if err != nil {
		return err
	}
	if len(docs) == 0 {
		return nil
	}

	allApproved := true
	for _, d := range docs {
		if d.Status == DocRejected {
			return s.proStore.SetVerificationStatus(ctx, professionalID, professionals.VerificationRejected)
		}
		if d.Status != DocApproved {
			allApproved = false
		}
	}
	if allApproved {
		return s.proStore.SetVerificationStatus(ctx, professionalID, professionals.VerificationVerified)
	}
	return s.proStore.SetVerificationStatus(ctx, professionalID, professionals.VerificationPending)
}

func validStage(stage string) bool {
	switch stage {
	case StageIdentity, StageBusiness, StageLocation, StageCertificate:
		return true
	}
	return false
}
