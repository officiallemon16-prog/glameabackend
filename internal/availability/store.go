package availability

import (
	"context"
	"database/sql"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const windowCols = `id, professional_id, day_of_week, start_minutes, end_minutes, is_active, created_at, updated_at`

func scanWindow(row interface{ Scan(...any) error }) (*Window, error) {
	var w Window
	err := row.Scan(&w.ID, &w.ProfessionalID, &w.DayOfWeek, &w.StartMinutes, &w.EndMinutes,
		&w.IsActive, &w.CreatedAt, &w.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &w, nil
}

func (s *Store) ReplaceWindows(ctx context.Context, professionalID string, in []WindowInput) ([]*Window, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `DELETE FROM availability_windows WHERE professional_id = ?`, professionalID); err != nil {
		return nil, err
	}
	for _, w := range in {
		if _, err := tx.ExecContext(ctx, `INSERT INTO availability_windows
			(id, professional_id, day_of_week, start_minutes, end_minutes, is_active)
			VALUES (?, ?, ?, ?, ?, 1)`,
			uuid.NewString(), professionalID, w.DayOfWeek, w.StartMinutes, w.EndMinutes); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return s.ListWindows(ctx, professionalID, true)
}

func (s *Store) ListWindows(ctx context.Context, professionalID string, includeInactive bool) ([]*Window, error) {
	q := `SELECT ` + windowCols + ` FROM availability_windows WHERE professional_id = ?`
	if !includeInactive {
		q += ` AND is_active = 1`
	}
	q += ` ORDER BY day_of_week ASC, start_minutes ASC`

	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []*Window{}
	for rows.Next() {
		w, err := scanWindow(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

const exceptionCols = `id, professional_id, exception_date, start_minutes, end_minutes, is_available, note, created_at`

func scanException(row interface{ Scan(...any) error }) (*Exception, error) {
	var e Exception
	var start, end sql.NullInt64
	var note sql.NullString
	var dateRaw []byte
	err := row.Scan(&e.ID, &e.ProfessionalID, &dateRaw, &start, &end, &e.IsAvailable, &note, &e.CreatedAt)
	if err != nil {
		return nil, err
	}
	e.Date = string(dateRaw)
	if start.Valid {
		v := int(start.Int64)
		e.StartMinutes = &v
	}
	if end.Valid {
		v := int(end.Int64)
		e.EndMinutes = &v
	}
	e.Note = note.String
	return &e, nil
}

func (s *Store) CreateException(ctx context.Context, professionalID string, in ExceptionInput) (*Exception, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO availability_exceptions
		(id, professional_id, exception_date, start_minutes, end_minutes, is_available, note)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, professionalID, in.Date, nullIntPtr(in.StartMinutes), nullIntPtr(in.EndMinutes), in.IsAvailable, in.Note)
	if err != nil {
		return nil, err
	}
	return s.GetException(ctx, id)
}

func (s *Store) GetException(ctx context.Context, id string) (*Exception, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+exceptionCols+` FROM availability_exceptions WHERE id = ?`, id)
	e, err := scanException(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("exception_not_found", "availability exception not found")
		}
		return nil, err
	}
	return e, nil
}

func (s *Store) ListExceptions(ctx context.Context, professionalID string, fromDate string) ([]*Exception, error) {
	q := `SELECT ` + exceptionCols + ` FROM availability_exceptions WHERE professional_id = ?`
	args := []any{professionalID}
	if fromDate != "" {
		q += ` AND exception_date >= ?`
		args = append(args, fromDate)
	}
	q += ` ORDER BY exception_date ASC`

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []*Exception{}
	for rows.Next() {
		e, err := scanException(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) DeleteException(ctx context.Context, professionalID, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM availability_exceptions WHERE id = ? AND professional_id = ?`, id, professionalID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("exception_not_found", "availability exception not found")
	}
	return nil
}

func nullIntPtr(v *int) sql.NullInt64 {
	if v == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*v), Valid: true}
}
