package admin

import (
	"context"

	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/httpx"
)

type Service struct {
	store     *AdminStore
	audit     *AuditStore
	userStore *users.Store
	proStore  *professionals.Store
}

func NewService(store *AdminStore, audit *AuditStore, userStore *users.Store, proStore *professionals.Store) *Service {
	return &Service{store: store, audit: audit, userStore: userStore, proStore: proStore}
}

func (s *Service) Dashboard(ctx context.Context) (*DashboardStats, error) {
	return s.store.Dashboard(ctx)
}

func (s *Service) DailyMetrics(ctx context.Context, from, to string) ([]*DailyMetric, error) {
	return s.store.DailyMetrics(ctx, from, to)
}

func (s *Service) ListUsers(ctx context.Context, limit, offset int) ([]*users.User, int64, error) {
	return s.userStore.List(ctx, limit, offset)
}

func (s *Service) SetUserStatus(ctx context.Context, actorID, userID, status string) error {
	switch status {
	case users.StatusActive, users.StatusSuspended, users.StatusDisabled:
	default:
		return httpx.BadRequest("invalid_status", "status must be ACTIVE, SUSPENDED or DISABLED")
	}
	if err := s.userStore.SetStatus(ctx, userID, status); err != nil {
		return err
	}
	return s.audit.Log(ctx, AuditEntry{
		ActorID: actorID, ActorRole: users.RoleAdmin, Action: "set_user_status",
		EntityType: "user", EntityID: userID, AfterState: map[string]string{"status": status},
	})
}

func (s *Service) SetUserRole(ctx context.Context, actorID, userID, role string) error {
	switch role {
	case users.RoleCustomer, users.RoleProfessional, users.RoleAdmin:
	default:
		return httpx.BadRequest("invalid_role", "role must be CUSTOMER, PROFESSIONAL or ADMIN")
	}
	if err := s.userStore.SetRole(ctx, userID, role); err != nil {
		return err
	}
	return s.audit.Log(ctx, AuditEntry{
		ActorID: actorID, ActorRole: users.RoleAdmin, Action: "set_user_role",
		EntityType: "user", EntityID: userID, AfterState: map[string]string{"role": role},
	})
}

func (s *Service) SetProfessionalStatus(ctx context.Context, actorID, proID, status string) error {
	if status != professionals.StatusActive && status != professionals.StatusSuspended &&
		status != professionals.StatusPending {
		return httpx.BadRequest("invalid_status", "invalid professional status")
	}
	if err := s.proStore.SetStatus(ctx, proID, status); err != nil {
		return err
	}
	return s.audit.Log(ctx, AuditEntry{
		ActorID: actorID, ActorRole: users.RoleAdmin, Action: "set_professional_status",
		EntityType: "professional", EntityID: proID, AfterState: map[string]string{"status": status},
	})
}

func (s *Service) ListProfessionals(ctx context.Context, status string, limit, offset int) ([]*professionals.Professional, int64, error) {
	return s.proStore.ListAdmin(ctx, status, limit, offset)
}

func (s *Service) ListAudit(ctx context.Context, entityType, entityID string, limit, offset int) ([]*AuditedEntry, int64, error) {
	return s.store.ListAudit(ctx, entityType, entityID, limit, offset)
}
