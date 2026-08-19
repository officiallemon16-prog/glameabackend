package messaging

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

// Message types supported by the chat (mirrors the DB enum).
const (
	TypeText     = "TEXT"
	TypeImage    = "IMAGE"
	TypeVoice    = "VOICE"
	TypeVideo    = "VIDEO"
	TypeLocation = "LOCATION"
	TypeCall     = "CALL"
)

type Conversation struct {
	ID             string     `json:"id"`
	BookingID      string     `json:"booking_id"`
	CustomerID     string     `json:"customer_id"`
	ProfessionalID string     `json:"professional_id"`
	// ProfessionalUserID is the professional's account (users.id), used to
	// address messages/calls to the right party.
	ProfessionalUserID string     `json:"professional_user_id"`
	LastMessage        string     `json:"last_message,omitempty"`
	LastMessageAt      *time.Time `json:"last_message_at,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`

	ProfessionalName string `json:"professional_name,omitempty"`
	CustomerName     string `json:"customer_name,omitempty"`
	ServiceName      string `json:"service_name,omitempty"`
	// Avatar URLs of both parties, resolved from users.avatar_media_id.
	ProfessionalAvatarURL string `json:"professional_avatar_url,omitempty"`
	CustomerAvatarURL     string `json:"customer_avatar_url,omitempty"`
	UnreadCount           int    `json:"unread_count"`
}

type Message struct {
	ID             string     `json:"id"`
	ConversationID string     `json:"conversation_id"`
	SenderID       string     `json:"sender_id"`
	RecipientID    string     `json:"recipient_id"`
	Body           string     `json:"body"`
	Type           string     `json:"type"`
	MediaAssetID   *string    `json:"media_asset_id,omitempty"`
	MediaURL       string     `json:"media_url,omitempty"`
	MimeType       string     `json:"mime_type,omitempty"`
	DurationMs     *int       `json:"duration_ms,omitempty"`
	Width          *int       `json:"width,omitempty"`
	Height         *int       `json:"height,omitempty"`
	Latitude       *float64   `json:"latitude,omitempty"`
	Longitude      *float64   `json:"longitude,omitempty"`
	Address        string     `json:"address,omitempty"`
	CallType       string     `json:"call_type,omitempty"`
	CallStatus     string     `json:"call_status,omitempty"`
	IsRead         bool       `json:"is_read"`
	ReadAt         *time.Time `json:"read_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
}

// NewMessage is the insert payload for a single message plus the preview used
// to update the conversation's `last_message`.
type NewMessage struct {
	ConversationID string
	SenderID       string
	RecipientID    string
	Body           string
	Type           string
	MediaAssetID   *string
	MediaURL       string
	MimeType       string
	DurationMs     *int
	Width          *int
	Height         *int
	Latitude       *float64
	Longitude      *float64
	Address        string
	CallType       string
	CallStatus     string
	Preview        string
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

const convCols = `c.id, c.booking_id, c.customer_id, c.professional_id, c.last_message, c.last_message_at, c.created_at, c.updated_at,
	p.business_name, p.user_id, CONCAT(u.first_name, ' ', u.last_name), s.name, pm.secure_url, cm.secure_url`

const convFrom = ` conversations c
	JOIN professionals p ON p.id = c.professional_id
	JOIN users u ON u.id = c.customer_id
	JOIN users pu ON pu.id = p.user_id
	LEFT JOIN media_assets pm ON pm.id = pu.avatar_media_id
	LEFT JOIN media_assets cm ON cm.id = u.avatar_media_id
	JOIN bookings b ON b.id = c.booking_id
	JOIN services s ON s.id = b.service_id
	LEFT JOIN (
		SELECT conversation_id, COUNT(*) AS cnt
		FROM messages WHERE is_read = 0
		GROUP BY conversation_id
	) unread ON unread.conversation_id = c.id`

// convForUserSuffix is no longer needed — unread count is in the LEFT JOIN above.

const messageCols = `id, conversation_id, sender_id, recipient_id, body, type, media_asset_id, media_url, mime_type,
	duration_ms, width, height, latitude, longitude, address, call_type, call_status, is_read, read_at, created_at`

func scanConv(row interface{ Scan(...any) error }) (*Conversation, error) {
	var c Conversation
	var lastMessage sql.NullString
	var lastAt sql.NullTime
	var proUserID sql.NullString
	var proName, custName, svcName sql.NullString
	var proAvatar, custAvatar sql.NullString
	err := row.Scan(&c.ID, &c.BookingID, &c.CustomerID, &c.ProfessionalID, &lastMessage, &lastAt,
		&c.CreatedAt, &c.UpdatedAt, &proName, &proUserID, &custName, &svcName, &proAvatar, &custAvatar)
	if err != nil {
		return nil, err
	}
	c.LastMessage = lastMessage.String
	if lastAt.Valid {
		c.LastMessageAt = &lastAt.Time
	}
	c.ProfessionalUserID = proUserID.String
	c.ProfessionalName = proName.String
	c.CustomerName = custName.String
	c.ServiceName = svcName.String
	c.ProfessionalAvatarURL = proAvatar.String
	c.CustomerAvatarURL = custAvatar.String
	return &c, nil
}

func scanConvWithUnread(row interface{ Scan(...any) error }) (*Conversation, error) {
	var c Conversation
	var lastMessage sql.NullString
	var lastAt sql.NullTime
	var proUserID sql.NullString
	var proName, custName, svcName sql.NullString
	var proAvatar, custAvatar sql.NullString
	var unread int
	err := row.Scan(&c.ID, &c.BookingID, &c.CustomerID, &c.ProfessionalID, &lastMessage, &lastAt,
		&c.CreatedAt, &c.UpdatedAt, &proName, &proUserID, &custName, &svcName, &proAvatar, &custAvatar, &unread)
	if err != nil {
		return nil, err
	}
	c.LastMessage = lastMessage.String
	if lastAt.Valid {
		c.LastMessageAt = &lastAt.Time
	}
	c.ProfessionalUserID = proUserID.String
	c.ProfessionalName = proName.String
	c.CustomerName = custName.String
	c.ServiceName = svcName.String
	c.ProfessionalAvatarURL = proAvatar.String
	c.CustomerAvatarURL = custAvatar.String
	c.UnreadCount = unread
	return &c, nil
}

func scanMessage(row interface{ Scan(...any) error }) (*Message, error) {
	var m Message
	var mediaAssetID, mediaURL, mimeType sql.NullString
	var durationMs, width, height sql.NullInt64
	var latitude, longitude sql.NullFloat64
	var address, callType, callStatus sql.NullString
	var readAt sql.NullTime
	err := row.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.RecipientID, &m.Body, &m.Type,
		&mediaAssetID, &mediaURL, &mimeType, &durationMs, &width, &height, &latitude, &longitude,
		&address, &callType, &callStatus, &m.IsRead, &readAt, &m.CreatedAt)
	if err != nil {
		return nil, err
	}
	if mediaAssetID.Valid {
		v := mediaAssetID.String
		m.MediaAssetID = &v
	}
	m.MediaURL = mediaURL.String
	m.MimeType = mimeType.String
	if durationMs.Valid {
		v := int(durationMs.Int64)
		m.DurationMs = &v
	}
	if width.Valid {
		v := int(width.Int64)
		m.Width = &v
	}
	if height.Valid {
		v := int(height.Int64)
		m.Height = &v
	}
	if latitude.Valid {
		v := latitude.Float64
		m.Latitude = &v
	}
	if longitude.Valid {
		v := longitude.Float64
		m.Longitude = &v
	}
	m.Address = address.String
	m.CallType = callType.String
	m.CallStatus = callStatus.String
	if readAt.Valid {
		m.ReadAt = &readAt.Time
	}
	return &m, nil
}

func (s *Store) GetOrCreate(ctx context.Context, bookingID, customerID, professionalID string) (*Conversation, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT IGNORE INTO conversations (id, booking_id, customer_id, professional_id)
		VALUES (?, ?, ?, ?)`, id, bookingID, customerID, professionalID)
	if err != nil {
		return nil, err
	}
	return s.GetByBookingID(ctx, bookingID)
}

func (s *Store) GetByBookingID(ctx context.Context, bookingID string) (*Conversation, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+convCols+` FROM`+convFrom+` WHERE c.booking_id = ?`, bookingID)
	c, err := scanConv(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("conversation_not_found", "conversation not found")
		}
		return nil, err
	}
	return c, nil
}

func (s *Store) GetByID(ctx context.Context, id string) (*Conversation, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+convCols+` FROM`+convFrom+` WHERE c.id = ?`, id)
	c, err := scanConv(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("conversation_not_found", "conversation not found")
		}
		return nil, err
	}
	return c, nil
}

func (s *Store) ListForUser(ctx context.Context, userID, proUserID string, limit, offset int) ([]*Conversation, int64, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+convCols+`, COALESCE(unread.cnt, 0)`+` FROM`+convFrom+
		` WHERE c.customer_id = ? OR c.professional_id IN (SELECT id FROM professionals WHERE user_id = ?)
		ORDER BY COALESCE(c.last_message_at, c.created_at) DESC LIMIT ? OFFSET ?`,
		userID, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Conversation{}
	for rows.Next() {
		c, err := scanConvWithUnread(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, c)
	}
	return out, 0, rows.Err()
}

// UnreadTotal returns how many messages addressed to the user are still unread.
func (s *Store) UnreadTotal(ctx context.Context, userID string) (int64, error) {
	var n int64
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM messages m
		WHERE m.recipient_id = ? AND m.is_read = 0`, userID).Scan(&n)
	return n, err
}

func (s *Store) AddMessage(ctx context.Context, in NewMessage) (*Message, error) {
	id := uuid.NewString()
	_, err := s.db.ExecContext(ctx, `INSERT INTO messages
		(id, conversation_id, sender_id, recipient_id, body, type, media_asset_id, media_url, mime_type,
		 duration_ms, width, height, latitude, longitude, address, call_type, call_status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, in.ConversationID, in.SenderID, in.RecipientID, in.Body, in.Type,
		in.MediaAssetID, nullIfEmpty(in.MediaURL), nullIfEmpty(in.MimeType),
		in.DurationMs, in.Width, in.Height, in.Latitude, in.Longitude,
		nullIfEmpty(in.Address), nullIfEmpty(in.CallType), nullIfEmpty(in.CallStatus))
	if err != nil {
		return nil, err
	}
	_, err = s.db.ExecContext(ctx, `UPDATE conversations SET last_message = ?, last_message_at = NOW() WHERE id = ?`,
		in.Preview, in.ConversationID)
	if err != nil {
		return nil, err
	}
	return s.GetMessageByID(ctx, id)
}

func nullIfEmpty(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

func (s *Store) GetMessageByID(ctx context.Context, id string) (*Message, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+messageCols+` FROM messages WHERE id = ?`, id)
	m, err := scanMessage(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("message_not_found", "message not found")
		}
		return nil, err
	}
	return m, nil
}

// ListMessages returns messages newest-first. When [before] is non-nil it uses
// keyset pagination on (created_at, id) - stable and index-friendly even while
// new messages arrive. Otherwise it falls back to offset pagination.
func (s *Store) ListMessages(ctx context.Context, conversationID string, limit, offset int, before *time.Time, beforeID string) ([]*Message, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM messages WHERE conversation_id = ?`,
		conversationID).Scan(&total); err != nil {
		return nil, 0, err
	}

	var rows *sql.Rows
	var err error
	if before != nil {
		rows, err = s.db.QueryContext(ctx, `SELECT `+messageCols+` FROM messages
			WHERE conversation_id = ? AND (created_at < ? OR (created_at = ? AND id < ?))
			ORDER BY created_at DESC, id DESC LIMIT ?`,
			conversationID, *before, *before, beforeID, limit)
	} else {
		rows, err = s.db.QueryContext(ctx, `SELECT `+messageCols+` FROM messages
			WHERE conversation_id = ? ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?`,
			conversationID, limit, offset)
	}
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := []*Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan message: %w", err)
		}
		out = append(out, m)
	}
	return out, total, rows.Err()
}

func (s *Store) MarkRead(ctx context.Context, conversationID, userID string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE messages SET is_read = 1, read_at = NOW()
		WHERE conversation_id = ? AND recipient_id = ? AND is_read = 0`, conversationID, userID)
	return err
}
