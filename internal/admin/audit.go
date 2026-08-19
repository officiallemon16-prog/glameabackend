package admin

import (
	"context"
	"database/sql"
	"encoding/json"

	"github.com/google/uuid"
)

type AuditEntry struct {
	ActorID     string
	ActorRole   string
	Action      string
	EntityType  string
	EntityID    string
	BeforeState any
	AfterState  any
	IP          string
	UserAgent   string
}

type AuditStore struct {
	db *sql.DB
}

func NewAuditStore(db *sql.DB) *AuditStore {
	return &AuditStore{db: db}
}

func (s *AuditStore) Log(ctx context.Context, e AuditEntry) error {
	before, err := marshalJSON(e.BeforeState)
	if err != nil {
		return err
	}
	after, err := marshalJSON(e.AfterState)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO audit_logs
		(id, actor_id, actor_role, action, entity_type, entity_id, before_state, after_state, ip, user_agent)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), nullable(e.ActorID), e.ActorRole, e.Action, e.EntityType, nullable(e.EntityID),
		before, after, e.IP, e.UserAgent)
	return err
}

func marshalJSON(v any) (sql.NullString, error) {
	if v == nil {
		return sql.NullString{}, nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return sql.NullString{}, err
	}
	return sql.NullString{String: string(b), Valid: true}, nil
}

func nullable(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}
