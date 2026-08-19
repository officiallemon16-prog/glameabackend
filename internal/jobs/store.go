package jobs

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
)

type ReminderBooking struct {
	ID         string
	CustomerID string
	ProUserID  string
	StartAt    time.Time
}

type SimpleBooking struct {
	ID         string
	CustomerID string
}

// UnreadConvo is one user with unread messages older than the nudge threshold.
// One row per user+booking (the chat deep-link target).
type UnreadConvo struct {
	UserID     string
	BookingID  string
	SenderName sql.NullString
}

// PendingBooking is a user's soon-to-expire (or oldest pending) request.
type PendingBooking struct {
	ID           string
	BusinessName string
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

// ListConfirmedUpcoming returns CONFIRMED bookings starting within the next
// withinMinutes minutes. The professional's user_id is joined for notification.
func (s *Store) ListConfirmedUpcoming(ctx context.Context, withinMinutes int) ([]ReminderBooking, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT b.id, b.customer_id, p.user_id, b.start_at
		FROM bookings b
		JOIN professionals p ON p.id = b.professional_id
		WHERE b.status = 'CONFIRMED'
		  AND b.start_at > NOW()
		  AND b.start_at <= DATE_ADD(NOW(), INTERVAL ? MINUTE)
		ORDER BY b.start_at ASC`, withinMinutes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ReminderBooking{}
	for rows.Next() {
		var r ReminderBooking
		if err := rows.Scan(&r.ID, &r.CustomerID, &r.ProUserID, &r.StartAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ListStalePending returns PENDING bookings created more than olderThanMinutes ago.
func (s *Store) ListStalePending(ctx context.Context, olderThanMinutes int) ([]SimpleBooking, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, customer_id FROM bookings
		WHERE status = 'PENDING'
		  AND created_at <= DATE_SUB(NOW(), INTERVAL ? MINUTE)
		ORDER BY created_at ASC`, olderThanMinutes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []SimpleBooking{}
	for rows.Next() {
		var b SimpleBooking
		if err := rows.Scan(&b.ID, &b.CustomerID); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// ListCompletedWithoutReview returns COMPLETED bookings finished at least
// olderThanMinutes ago that still have no review.
func (s *Store) ListCompletedWithoutReview(ctx context.Context, olderThanMinutes int) ([]SimpleBooking, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT b.id, b.customer_id FROM bookings b
		LEFT JOIN reviews r ON r.booking_id = b.id
		WHERE b.status = 'COMPLETED'
		  AND r.id IS NULL
		  AND b.end_at <= DATE_SUB(NOW(), INTERVAL ? MINUTE)
		ORDER BY b.end_at ASC`, olderThanMinutes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []SimpleBooking{}
	for rows.Next() {
		var b SimpleBooking
		if err := rows.Scan(&b.ID, &b.CustomerID); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// InsertReminder records that a reminder was sent. Returns true when newly inserted.
func (s *Store) InsertReminder(ctx context.Context, bookingID, kind string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO booking_reminders (id, booking_id, kind) VALUES (?, ?, ?)`,
		uuid.NewString(), bookingID, kind)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ClaimSend reserves a re-engagement push for (userID, capType). It returns true
// only when no send of that type happened within cooldown. Uses an atomic
// INSERT ... SELECT pattern to prevent double-sends under concurrent ticks.
func (s *Store) ClaimSend(ctx context.Context, userID, capType string, cooldown time.Duration) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		INSERT INTO push_caps (id, user_id, cap_type, claimed_at)
		SELECT ?, ?, ?, NOW()
		FROM DUAL
		WHERE NOT EXISTS (
			SELECT 1 FROM push_caps
			WHERE user_id = ? AND cap_type = ? AND claimed_at > DATE_SUB(NOW(), INTERVAL ? SECOND)
		)`,
		uuid.NewString(), userID, capType,
		userID, capType, int(cooldown.Seconds()))
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ListUnreadConvos returns users with unread messages at least olderThanMinutes
// old, newest first, one row per user+booking (deduplicated by the job).
func (s *Store) ListUnreadConvos(ctx context.Context, olderThanMinutes int) ([]UnreadConvo, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT m.recipient_id,
		       c.booking_id,
		       CASE WHEN m.recipient_id = c.customer_id THEN p.business_name
		            ELSE CONCAT(u2.first_name, ' ', u2.last_name) END AS sender_name
		FROM messages m
		JOIN conversations c ON c.id = m.conversation_id
		JOIN professionals p ON p.id = c.professional_id
		JOIN users u2 ON u2.id = c.customer_id
		WHERE m.is_read = 0
		  AND m.created_at <= DATE_SUB(NOW(), INTERVAL ? MINUTE)
		GROUP BY m.recipient_id, c.booking_id, c.customer_id, p.business_name, u2.first_name, u2.last_name
		ORDER BY MAX(m.created_at) DESC`, olderThanMinutes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []UnreadConvo{}
	for rows.Next() {
		var c UnreadConvo
		if err := rows.Scan(&c.UserID, &c.BookingID, &c.SenderName); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ListInactiveUsers returns active non-admin users with a live device token who
// have not been seen (login or signup) for at least olderThanHours hours.
func (s *Store) ListInactiveUsers(ctx context.Context, olderThanHours int) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT u.id
		FROM users u
		WHERE u.status = 'ACTIVE'
		  AND u.role <> 'ADMIN'
		  AND EXISTS (SELECT 1 FROM device_tokens dt WHERE dt.user_id = u.id AND dt.disabled = 0)
		  AND COALESCE(u.last_login_at, u.created_at) <= DATE_SUB(NOW(), INTERVAL ? HOUR)
		ORDER BY u.last_login_at ASC`, olderThanHours)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// ListPendingExpiring returns PENDING bookings whose request window (created_at
// + expiryMinutes) is within the next withinMinutes and not yet past.
func (s *Store) ListPendingExpiring(ctx context.Context, expiryMinutes, withinMinutes int) ([]ReminderBooking, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT b.id, b.customer_id, p.user_id, b.start_at
		FROM bookings b
		JOIN professionals p ON p.id = b.professional_id
		WHERE b.status = 'PENDING'
		  AND DATE_ADD(b.created_at, INTERVAL ? MINUTE) > NOW()
		  AND DATE_ADD(b.created_at, INTERVAL ? MINUTE) <= DATE_ADD(NOW(), INTERVAL ? MINUTE)
		ORDER BY b.created_at ASC`, expiryMinutes, withinMinutes)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ReminderBooking{}
	for rows.Next() {
		var r ReminderBooking
		if err := rows.Scan(&r.ID, &r.CustomerID, &r.ProUserID, &r.StartAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ListPendingForUser returns the user's oldest future PENDING booking, if any.
func (s *Store) ListPendingForUser(ctx context.Context, userID string) (*PendingBooking, error) {
	var b PendingBooking
	err := s.db.QueryRowContext(ctx, `
		SELECT b.id, p.business_name
		FROM bookings b
		JOIN professionals p ON p.id = b.professional_id
		WHERE b.customer_id = ? AND b.status = 'PENDING' AND b.start_at > NOW()
		ORDER BY b.start_at ASC LIMIT 1`, userID).Scan(&b.ID, &b.BusinessName)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &b, nil
}

// UnreadCountForUser counts the user's unread messages.
func (s *Store) UnreadCountForUser(ctx context.Context, userID string) (int, error) {
	var n int
	if err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM messages WHERE recipient_id = ? AND is_read = 0`, userID).Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

// ListDigestUsers returns active non-admin users who liked or saved any post.
func (s *Store) ListDigestUsers(ctx context.Context) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT u.id
		FROM users u
		WHERE u.status = 'ACTIVE'
		  AND u.role <> 'ADMIN'
		  AND (EXISTS (SELECT 1 FROM post_likes l WHERE l.user_id = u.id)
		       OR EXISTS (SELECT 1 FROM post_saves s WHERE s.user_id = u.id))
		ORDER BY u.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// NewContentCountForUser counts posts published within the last withinHours that
// come from professionals the user liked or saved posts from.
func (s *Store) NewContentCountForUser(ctx context.Context, userID string, withinHours int) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM posts p
		WHERE p.is_active = 1
		  AND p.created_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)
		  AND EXISTS (
		      SELECT 1
		      FROM posts p2
		      WHERE p2.professional_id = p.professional_id
		        AND (EXISTS (SELECT 1 FROM post_likes l WHERE l.post_id = p2.id AND l.user_id = ?)
		             OR EXISTS (SELECT 1 FROM post_saves s WHERE s.post_id = p2.id AND s.user_id = ?))
		  )`, withinHours, userID, userID).Scan(&n)
	if err != nil {
		return 0, err
	}
	return n, nil
}
