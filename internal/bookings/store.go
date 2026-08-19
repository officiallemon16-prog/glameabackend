package bookings

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const bookingCols = `b.id, b.professional_id, b.customer_id, b.service_id, b.variant_id, b.status,
	b.start_at, b.end_at, b.base_amount, b.total_amount, b.deposit_amount, b.currency,
	b.home_service, b.location_lat, b.location_lng, b.location_address, b.customer_notes,
	b.cancellation_policy_id, b.cancelled_at, b.cancelled_by, b.cancel_reason,
	b.created_at, b.updated_at,
	s.name, p.business_name, u.first_name, u.last_name`

const bookingFrom = ` bookings b
	JOIN services s ON s.id = b.service_id
	JOIN professionals p ON p.id = b.professional_id
	JOIN users u ON u.id = b.customer_id`

func scanBooking(row interface{ Scan(...any) error }) (*Booking, error) {
	var b Booking
	var variant, policy sql.NullString
	var lat, lng sql.NullFloat64
	var address, notes sql.NullString
	var cancelledAt sql.NullTime
	var cancelledBy sql.NullString
	var cancelReason sql.NullString
	var home sql.NullBool
	var firstName, lastName sql.NullString
	var proName sql.NullString

	err := row.Scan(&b.ID, &b.ProfessionalID, &b.CustomerID, &b.ServiceID, &variant, &b.Status,
		&b.StartAt, &b.EndAt, &b.BaseAmount, &b.TotalAmount, &b.DepositAmount, &b.Currency,
		&home, &lat, &lng, &address, &notes,
		&policy, &cancelledAt, &cancelledBy, &cancelReason,
		&b.CreatedAt, &b.UpdatedAt,
		&b.ServiceName, &proName, &firstName, &lastName)
	if err != nil {
		return nil, err
	}
	if variant.Valid {
		b.VariantID = &variant.String
	}
	if policy.Valid {
		b.CancellationPolicyID = &policy.String
	}
	if lat.Valid {
		b.LocationLat = &lat.Float64
	}
	if lng.Valid {
		b.LocationLng = &lng.Float64
	}
	if address.Valid {
		b.LocationAddress = address.String
	}
	if notes.Valid {
		b.CustomerNotes = notes.String
	}
	if cancelledAt.Valid {
		b.CancelledAt = &cancelledAt.Time
	}
	if cancelledBy.Valid {
		b.CancelledBy = &cancelledBy.String
	}
	b.CancelReason = cancelReason.String
	b.HomeService = home.Valid && home.Bool
	b.ProfessionalName = proName.String
	b.CustomerName = firstName.String + " " + lastName.String
	return &b, nil
}

type CreateData struct {
	ID                   string
	ProfessionalID       string
	CustomerID           string
	ServiceID            string
	VariantID            *string
	StartAt              time.Time
	EndAt                time.Time
	BaseAmount           float64
	TotalAmount          float64
	DepositAmount        float64
	Currency             string
	HomeService          bool
	LocationLat          *float64
	LocationLng          *float64
	LocationAddress      string
	CustomerNotes        string
	CancellationPolicyID *string
	IdempotencyKey       string
}

func (s *Store) Create(ctx context.Context, in CreateData) (*Booking, error) {
	id := in.ID
	if id == "" {
		id = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO bookings
		(id, professional_id, customer_id, service_id, variant_id, status, start_at, end_at,
		 base_amount, total_amount, deposit_amount, currency, home_service, location_lat, location_lng,
		 location_address, customer_notes, cancellation_policy_id, idempotency_key)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, in.ProfessionalID, in.CustomerID, in.ServiceID, nullString(in.VariantID), StatusPending,
		in.StartAt.UTC(), in.EndAt.UTC(),
		in.BaseAmount, in.TotalAmount, in.DepositAmount, in.Currency, in.HomeService,
		nullFloatPtr(in.LocationLat), nullFloatPtr(in.LocationLng), in.LocationAddress, in.CustomerNotes,
		nullString(in.CancellationPolicyID), nullStringOrNil(in.IdempotencyKey))
	if err != nil {
		return nil, err
	}
	if err := s.AddStatusEvent(ctx, id, "", StatusPending, nil, "created"); err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

// CreateIfSlotFree inserts a booking only when no other active booking overlaps.
// The professional row is locked for the duration of the transaction so concurrent
// creates for the same professional serialize against each other, closing the
// check-then-insert race even when bookings start at different times.
func (s *Store) CreateIfSlotFree(ctx context.Context, in CreateData, start, end time.Time) (*Booking, error) {
	id := in.ID
	if id == "" {
		id = uuid.NewString()
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var lock int
	if err := tx.QueryRowContext(ctx, `SELECT 1 FROM professionals WHERE id = ? FOR UPDATE`, in.ProfessionalID).Scan(&lock); err != nil {
		return nil, err
	}

	var conflictID string
	err = tx.QueryRowContext(ctx, `SELECT id FROM bookings
		WHERE professional_id = ? AND status IN (?, ?, ?)
		AND start_at < ? AND end_at > ?
		AND id <> ?
		LIMIT 1`,
		in.ProfessionalID, StatusPending, StatusConfirmed, StatusInProgress,
		end.UTC(), start.UTC(), id).Scan(&conflictID)
	if err == nil {
		return nil, httpx.Conflict("slot_unavailable", "the requested time is not available")
	}
	if err != sql.ErrNoRows {
		return nil, err
	}

	if _, err := tx.ExecContext(ctx, `INSERT INTO bookings
		(id, professional_id, customer_id, service_id, variant_id, status, start_at, end_at,
		 base_amount, total_amount, deposit_amount, currency, home_service, location_lat, location_lng,
		 location_address, customer_notes, cancellation_policy_id, idempotency_key)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, in.ProfessionalID, in.CustomerID, in.ServiceID, nullString(in.VariantID), StatusPending,
		in.StartAt.UTC(), in.EndAt.UTC(),
		in.BaseAmount, in.TotalAmount, in.DepositAmount, in.Currency, in.HomeService,
		nullFloatPtr(in.LocationLat), nullFloatPtr(in.LocationLng), in.LocationAddress, in.CustomerNotes,
		nullString(in.CancellationPolicyID), nullStringOrNil(in.IdempotencyKey)); err != nil {
		return nil, err
	}

	if _, err := tx.ExecContext(ctx, `INSERT INTO booking_status_history
		(id, booking_id, from_status, to_status, changed_by, note)
		VALUES (?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), id, nil, StatusPending, nil, "created"); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Booking, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+bookingCols+` FROM`+bookingFrom+` WHERE b.id = ?`, id)
	b, err := scanBooking(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, httpx.NotFound("booking_not_found", "booking not found")
		}
		return nil, err
	}
	return b, nil
}

func (s *Store) GetByIdempotencyKey(ctx context.Context, key string) (*Booking, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+bookingCols+` FROM`+bookingFrom+` WHERE b.idempotency_key = ?`, key)
	b, err := scanBooking(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	return b, nil
}

// PaidAmounts returns, per booking, the sum of amounts from SUCCEEDED payment
// intents. Payments that succeeded and were later refunded are still counted;
// a refund lowers the wallet, not the amount owed for the service.
func (s *Store) PaidAmounts(ctx context.Context, bookingIDs []string) (map[string]float64, error) {
	paid := map[string]float64{}
	if len(bookingIDs) == 0 {
		return paid, nil
	}
	placeholders := strings.Repeat("?,", len(bookingIDs)-1) + "?"
	args := make([]any, len(bookingIDs))
	for i, id := range bookingIDs {
		args[i] = id
	}
	rows, err := s.db.QueryContext(ctx, `SELECT booking_id, IFNULL(SUM(amount), 0)
		FROM payment_intents
		WHERE booking_id IN (`+placeholders+`) AND status = 'SUCCEEDED'
		GROUP BY booking_id`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var sum float64
		if err := rows.Scan(&id, &sum); err != nil {
			return nil, err
		}
		paid[id] = sum
	}
	return paid, rows.Err()
}

// HasSucceededDeposit reports whether the booking has a SUCCEEDED DEPOSIT
// payment intent. It is used to gate confirmation: a booking cannot become
// CONFIRMED until the deposit (when required) has actually been paid.
func (s *Store) HasSucceededDeposit(ctx context.Context, bookingID string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payment_intents
		WHERE booking_id = ? AND amount_type = 'DEPOSIT' AND status = 'SUCCEEDED'`, bookingID).Scan(&n)
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

func (s *Store) ListForCustomer(ctx context.Context, customerID string, limit, offset int) ([]*Booking, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+bookingCols+` FROM`+bookingFrom+
		` WHERE b.customer_id = ? ORDER BY b.start_at DESC LIMIT ? OFFSET ?`, customerID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.scanBookings(rows)
}

func (s *Store) ListForProfessional(ctx context.Context, professionalID string, limit, offset int) ([]*Booking, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+bookingCols+` FROM`+bookingFrom+
		` WHERE b.professional_id = ?
		AND (b.status != 'PENDING' OR b.deposit_amount <= 0
			OR EXISTS (SELECT 1 FROM payment_intents pi WHERE pi.booking_id = b.id AND pi.amount_type = 'DEPOSIT' AND pi.status = 'SUCCEEDED'))
		ORDER BY b.start_at DESC LIMIT ? OFFSET ?`, professionalID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.scanBookings(rows)
}

func (s *Store) scanBookings(rows *sql.Rows) ([]*Booking, error) {
	out := []*Booking{}
	for rows.Next() {
		b, err := scanBooking(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (s *Store) ListOverlapping(ctx context.Context, professionalID string, start, end time.Time, excludeID string) ([]*Booking, error) {
	statuses := "('" + StatusPending + "','" + StatusConfirmed + "','" + StatusInProgress + "')"
	q := `SELECT ` + bookingCols + ` FROM` + bookingFrom +
		` WHERE b.professional_id = ? AND b.status IN ` + statuses +
		` AND b.start_at < ? AND b.end_at > ?`
	args := []any{professionalID, end.UTC(), start.UTC()}
	if excludeID != "" {
		q += ` AND b.id <> ?`
		args = append(args, excludeID)
	}
	q += ` ORDER BY b.start_at ASC`
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.scanBookings(rows)
}

func (s *Store) UpdateStatus(ctx context.Context, id, from, to string, changedBy *string, note string) (*Booking, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE bookings SET status = ?,
		cancelled_at = IF(? = 'CANCELLED', NOW(), cancelled_at),
		cancelled_by = IF(? = 'CANCELLED', ?, cancelled_by),
		cancel_reason = IF(? = 'CANCELLED', ?, cancel_reason)
		WHERE id = ? AND status = ?`,
		to, to, to, nullStringOrNilPtr(changedBy), to, note, id, from)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, httpx.Conflict("invalid_status_transition", "booking status does not allow this transition")
	}
	if err := s.AddStatusEvent(ctx, id, from, to, changedBy, note); err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

// CompleteStatus atomically marks a booking completed and increments the
// professional's completed-booking count, so the two can never diverge.
func (s *Store) CompleteStatus(ctx context.Context, id, from, professionalID string, changedBy *string, note string) (*Booking, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `UPDATE bookings SET status = ? WHERE id = ? AND status = ?`,
		StatusCompleted, id, from)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, httpx.Conflict("invalid_status_transition", "booking status does not allow this transition")
	}
	if _, err := tx.ExecContext(ctx, `UPDATE professionals SET booking_count = booking_count + 1 WHERE id = ?`,
		professionalID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO booking_status_history
		(id, booking_id, from_status, to_status, changed_by, note)
		VALUES (?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), id, nullOrEmpty(from), StatusCompleted, nullStringOrNilPtr(changedBy), note); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Reschedule(ctx context.Context, id string, start, end time.Time, by *string, toStatus string) (*Booking, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE bookings SET start_at = ?, end_at = ? WHERE id = ?`,
		start.UTC(), end.UTC(), id)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, httpx.NotFound("booking_not_found", "booking not found")
	}
	if err := s.AddStatusEvent(ctx, id, "", toStatus, by, "rescheduled"); err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) AddStatusEvent(ctx context.Context, bookingID, from, to string, changedBy *string, note string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO booking_status_history
		(id, booking_id, from_status, to_status, changed_by, note)
		VALUES (?, ?, ?, ?, ?, ?)`,
		uuid.NewString(), bookingID, nullOrEmpty(from), nullOrEmpty(to), nullStringOrNilPtr(changedBy), note)
	return err
}

func (s *Store) ListStatusEvents(ctx context.Context, bookingID string) ([]*StatusEvent, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, booking_id, from_status, to_status, changed_by, note, created_at
		FROM booking_status_history WHERE booking_id = ? ORDER BY created_at ASC`, bookingID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*StatusEvent{}
	for rows.Next() {
		var e StatusEvent
		var from, note, changedBy sql.NullString
		if err := rows.Scan(&e.ID, &e.BookingID, &from, &e.ToStatus, &changedBy, &note, &e.CreatedAt); err != nil {
			return nil, err
		}
		e.FromStatus = from.String
		e.Note = note.String
		if changedBy.Valid {
			e.ChangedBy = &changedBy.String
		}
		out = append(out, &e)
	}
	return out, rows.Err()
}

type CancellationPolicy struct {
	ID               string  `json:"id"`
	Name             string  `json:"name"`
	FreeCancelHours  int     `json:"free_cancel_hours"`
	CancelFeePercent float64 `json:"cancel_fee_percent"`
}

func (s *Store) GetCancellationPolicy(ctx context.Context, id string) (*CancellationPolicy, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, free_cancel_hours, cancel_fee_percent
		FROM cancellation_policies WHERE id = ?`, id)
	var p CancellationPolicy
	err := row.Scan(&p.ID, &p.Name, &p.FreeCancelHours, &p.CancelFeePercent)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}

func nullString(v *string) any {
	if v == nil {
		return nil
	}
	return *v
}

func nullStringOrNil(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func nullStringOrNilPtr(v *string) any {
	if v == nil || *v == "" {
		return nil
	}
	return *v
}

func nullFloatPtr(v *float64) any {
	if v == nil {
		return nil
	}
	return *v
}

func nullOrEmpty(v string) any {
	if v == "" {
		return nil
	}
	return v
}
