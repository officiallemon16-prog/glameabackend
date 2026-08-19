package posts

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/google/uuid"
)

type Post struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id"`
	CategoryID     *string   `json:"category_id,omitempty"`
	Caption        string    `json:"caption,omitempty"`
	Location       string    `json:"location,omitempty"`
	Sponsored      bool      `json:"sponsored"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type PostImage struct {
	URL string `json:"url"`
}

type PostAuthor struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	AvatarURL   string   `json:"avatar_url,omitempty"`
	City        string   `json:"city,omitempty"`
	Rating      float64  `json:"rating"`
	ReviewCount int      `json:"review_count"`
	Verified    bool     `json:"verified"`
	Latitude    *float64 `json:"latitude,omitempty"`
	Longitude   *float64 `json:"longitude,omitempty"`
}

type FeedPost struct {
	Post
	CategorySlug string      `json:"category_slug,omitempty"`
	CategoryName string      `json:"category_name,omitempty"`
	Images       []PostImage `json:"images"`
	Professional PostAuthor  `json:"professional"`
	LikeCount    int         `json:"like_count"`
	LikedByMe    bool        `json:"liked_by_me"`
	SavedByMe    bool        `json:"saved_by_me"`
}

type FeedFilter struct {
	CategoryID string
	Sponsored  *bool
	UserID     string
	Limit      int
	Offset     int
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Create(ctx context.Context, in Post) (*Post, error) {
	if in.ID == "" {
		in.ID = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO posts
		(id, professional_id, category_id, caption, location, sponsored, is_active)
		VALUES (?, ?, ?, ?, ?, ?, 1)`,
		in.ID, in.ProfessionalID, nullString(in.CategoryID), nullStr(in.Caption), nullStr(in.Location), in.Sponsored)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, in.ID)
}

func (s *Store) GetByID(ctx context.Context, id string) (*Post, error) {
	var p Post
	var cat, caption, loc sql.NullString
	err := s.db.QueryRowContext(ctx, `SELECT id, professional_id, category_id, caption, location, sponsored, created_at, updated_at
		FROM posts WHERE id = ? AND is_active = 1`, id).
		Scan(&p.ID, &p.ProfessionalID, &cat, &caption, &loc, &p.Sponsored, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("post_not_found", "post not found")
		}
		return nil, err
	}
	if cat.Valid {
		p.CategoryID = &cat.String
	}
	p.Caption = caption.String
	p.Location = loc.String
	return &p, nil
}

func (s *Store) SetImages(ctx context.Context, postID string, urls []string) error {
	if _, err := s.db.ExecContext(ctx, `DELETE FROM post_media WHERE post_id = ?`, postID); err != nil {
		return err
	}
	for i, u := range urls {
		if _, err := s.db.ExecContext(ctx, `INSERT INTO post_media (id, post_id, secure_url, display_order)
			VALUES (?, ?, ?, ?)`, uuid.NewString(), postID, u, i); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) Update(ctx context.Context, id string, in Post) (*Post, error) {
	_, err := s.db.ExecContext(ctx, `UPDATE posts SET
		category_id = ?, caption = ?, location = ?, sponsored = ?
		WHERE id = ?`,
		nullString(in.CategoryID), nullStr(in.Caption), nullStr(in.Location), in.Sponsored, id)
	if err != nil {
		return nil, err
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Delete(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE posts SET is_active = 0 WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return httpx.NotFound("post_not_found", "post not found")
	}
	return nil
}

func (s *Store) ListMine(ctx context.Context, professionalID string) ([]*Post, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, professional_id, category_id, caption, location, sponsored, created_at, updated_at
		FROM posts WHERE professional_id = ? AND is_active = 1 ORDER BY created_at DESC`, professionalID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Post{}
	for rows.Next() {
		var p Post
		var cat, caption, loc sql.NullString
		if err := rows.Scan(&p.ID, &p.ProfessionalID, &cat, &caption, &loc, &p.Sponsored, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		if cat.Valid {
			p.CategoryID = &cat.String
		}
		p.Caption = caption.String
		p.Location = loc.String
		out = append(out, &p)
	}
	return out, rows.Err()
}

// ListFeed returns the Instagram-style feed of posts joined with professional
// and author profile info. Sponsored posts float to the top so adverts stay
// visible in Discovery.
func (s *Store) ListFeed(ctx context.Context, f FeedFilter) ([]*FeedPost, int64, error) {
	var total int64
	countQ := `SELECT COUNT(*) FROM posts p WHERE p.is_active = 1`
	args := []any{}
	if f.CategoryID != "" {
		countQ += ` AND p.category_id = ?`
		args = append(args, f.CategoryID)
	}
	if f.Sponsored != nil {
		countQ += ` AND p.sponsored = ?`
		args = append(args, *f.Sponsored)
	}
	if err := s.db.QueryRowContext(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	q := `SELECT
		p.id, p.professional_id, p.category_id, p.caption, p.location, p.sponsored, p.created_at,
		c.slug, c.name,
		pr.id, COALESCE(NULLIF(pr.display_name, ''), pr.business_name), u.first_name, u.last_name,
		COALESCE(pr.city, ''), pr.rating, pr.review_count, pr.verification_status,
		pr.latitude, pr.longitude,
		COALESCE(m.secure_url, ''),
		(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = p.id),
		EXISTS(SELECT 1 FROM post_likes l2 WHERE l2.post_id = p.id AND l2.user_id = ?),
		EXISTS(SELECT 1 FROM post_saves s2 WHERE s2.post_id = p.id AND s2.user_id = ?)
		FROM posts p
		JOIN professionals pr ON pr.id = p.professional_id AND pr.status = 'ACTIVE'
		JOIN users u ON u.id = pr.user_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN media_assets m ON m.id = u.avatar_media_id
		WHERE p.is_active = 1`
	qArgs := []any{f.UserID, f.UserID}
	if f.CategoryID != "" {
		q += ` AND p.category_id = ?`
		qArgs = append(qArgs, f.CategoryID)
	}
	if f.Sponsored != nil {
		q += ` AND p.sponsored = ?`
		qArgs = append(qArgs, *f.Sponsored)
	}
	q += ` ORDER BY p.sponsored DESC, p.created_at DESC`
	if f.Limit > 0 {
		q += ` LIMIT ? OFFSET ?`
		qArgs = append(qArgs, f.Limit, f.Offset)
	}

	rows, err := s.db.QueryContext(ctx, q, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	posts := []*FeedPost{}
	ids := []string{}
	for rows.Next() {
		var fp FeedPost
		var catID, slug, catName sql.NullString
		var caption, location, firstName, lastName, verification sql.NullString
		var lat, lng sql.NullFloat64
		if err := rows.Scan(
			&fp.ID, &fp.ProfessionalID, &catID, &caption, &location, &fp.Sponsored, &fp.CreatedAt,
			&slug, &catName,
			&fp.Professional.ID, &fp.Professional.Name, &firstName, &lastName,
			&fp.Professional.City, &fp.Professional.Rating, &fp.Professional.ReviewCount, &verification,
			&lat, &lng,
			&fp.Professional.AvatarURL,
			&fp.LikeCount, &fp.LikedByMe, &fp.SavedByMe,
		); err != nil {
			return nil, 0, err
		}
		if catID.Valid {
			fp.CategoryID = &catID.String
		}
		fp.CategorySlug = slug.String
		fp.CategoryName = catName.String
		fp.Caption = caption.String
		fp.Location = location.String
		fp.Professional.Verified = strings.EqualFold(verification.String, "VERIFIED")
		if lat.Valid {
			fp.Professional.Latitude = &lat.Float64
		}
		if lng.Valid {
			fp.Professional.Longitude = &lng.Float64
		}
		ids = append(ids, fp.ID)
		posts = append(posts, &fp)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if len(posts) > 0 {
		media, err := s.mediaForPosts(ctx, ids)
		if err != nil {
			return nil, 0, err
		}
		for _, fp := range posts {
			fp.Images = media[fp.ID]
		}
	}
	return posts, total, nil
}

func (s *Store) mediaForPosts(ctx context.Context, ids []string) (map[string][]PostImage, error) {
	if len(ids) == 0 {
		return map[string][]PostImage{}, nil
	}
	placeholders := strings.Repeat("?,", len(ids))
	placeholders = strings.TrimSuffix(placeholders, ",")
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	rows, err := s.db.QueryContext(ctx, `SELECT post_id, secure_url FROM post_media
		WHERE post_id IN (`+placeholders+`) ORDER BY display_order ASC`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string][]PostImage{}
	for rows.Next() {
		var postID, url string
		if err := rows.Scan(&postID, &url); err != nil {
			return nil, err
		}
		out[postID] = append(out[postID], PostImage{URL: url})
	}
	return out, rows.Err()
}

// FeedPostByID returns a single feed post with its author and images.
func (s *Store) FeedPostByID(ctx context.Context, id string) (*FeedPost, error) {
	q := `SELECT
		p.id, p.professional_id, p.category_id, p.caption, p.location, p.sponsored, p.created_at,
		c.slug, c.name,
		pr.id, COALESCE(NULLIF(pr.display_name, ''), pr.business_name), u.first_name, u.last_name,
		COALESCE(pr.city, ''), pr.rating, pr.review_count, pr.verification_status,
		pr.latitude, pr.longitude,
		COALESCE(m.secure_url, ''),
		(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = p.id),
		0,
		0
		FROM posts p
		JOIN professionals pr ON pr.id = p.professional_id AND pr.status = 'ACTIVE'
		JOIN users u ON u.id = pr.user_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN media_assets m ON m.id = u.avatar_media_id
		WHERE p.is_active = 1 AND p.id = ?`

	var fp FeedPost
	var catID, slug, catName sql.NullString
	var caption, location, firstName, lastName, verification sql.NullString
	var lat, lng sql.NullFloat64
	err := s.db.QueryRowContext(ctx, q, id).Scan(
		&fp.ID, &fp.ProfessionalID, &catID, &caption, &location, &fp.Sponsored, &fp.CreatedAt,
		&slug, &catName,
		&fp.Professional.ID, &fp.Professional.Name, &firstName, &lastName,
		&fp.Professional.City, &fp.Professional.Rating, &fp.Professional.ReviewCount, &verification,
		&lat, &lng,
		&fp.Professional.AvatarURL,
		&fp.LikeCount, &fp.LikedByMe, &fp.SavedByMe,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.NotFound("post_not_found", "post not found")
		}
		return nil, err
	}
	if catID.Valid {
		fp.CategoryID = &catID.String
	}
	fp.CategorySlug = slug.String
	fp.CategoryName = catName.String
	fp.Caption = caption.String
	fp.Location = location.String
	fp.Professional.Verified = strings.EqualFold(verification.String, "VERIFIED")
	if lat.Valid {
		fp.Professional.Latitude = &lat.Float64
	}
	if lng.Valid {
		fp.Professional.Longitude = &lng.Float64
	}

	media, err := s.mediaForPosts(ctx, []string{fp.ID})
	if err != nil {
		return nil, err
	}
	fp.Images = media[fp.ID]
	return &fp, nil
}

// Like adds a like/favorite by a user on a post. Idempotent.
func (s *Store) Like(ctx context.Context, userID, postID string) error {
	var id string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM posts WHERE id = ? AND is_active = 1`, postID).Scan(&id)
	if err != nil {
		if err == sql.ErrNoRows {
			return httpx.NotFound("post_not_found", "post not found")
		}
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)`, postID, userID)
	return err
}

// Unlike removes a like/favorite. Idempotent.
func (s *Store) Unlike(ctx context.Context, userID, postID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM post_likes WHERE post_id = ? AND user_id = ?`, postID, userID)
	return err
}

// Save bookmarks a post for the user. Idempotent.
func (s *Store) Save(ctx context.Context, userID, postID string) error {
	var id string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM posts WHERE id = ? AND is_active = 1`, postID).Scan(&id)
	if err != nil {
		if err == sql.ErrNoRows {
			return httpx.NotFound("post_not_found", "post not found")
		}
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT IGNORE INTO post_saves (post_id, user_id) VALUES (?, ?)`, postID, userID)
	return err
}

// Unsave removes a bookmark. Idempotent.
func (s *Store) Unsave(ctx context.Context, userID, postID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM post_saves WHERE post_id = ? AND user_id = ?`, postID, userID)
	return err
}

// ListLiked returns feed posts the user has liked, newest like first.
func (s *Store) ListLiked(ctx context.Context, userID string, f FeedFilter) ([]*FeedPost, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM post_likes pl
		JOIN posts p ON p.id = pl.post_id
		WHERE pl.user_id = ? AND p.is_active = 1`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}

	q := `SELECT
		p.id, p.professional_id, p.category_id, p.caption, p.location, p.sponsored, p.created_at,
		c.slug, c.name,
		pr.id, COALESCE(NULLIF(pr.display_name, ''), pr.business_name), u.first_name, u.last_name,
		COALESCE(pr.city, ''), pr.rating, pr.review_count, pr.verification_status,
		pr.latitude, pr.longitude,
		COALESCE(m.secure_url, ''),
		(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = p.id),
		1,
		EXISTS(SELECT 1 FROM post_saves s WHERE s.post_id = p.id AND s.user_id = ?)
		FROM posts p
		JOIN professionals pr ON pr.id = p.professional_id AND pr.status = 'ACTIVE'
		JOIN users u ON u.id = pr.user_id
		JOIN post_likes pl ON pl.post_id = p.id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN media_assets m ON m.id = u.avatar_media_id
		WHERE p.is_active = 1 AND pl.user_id = ?
		ORDER BY pl.created_at DESC`
	qArgs := []any{userID, userID}
	if f.Limit > 0 {
		q += ` LIMIT ? OFFSET ?`
		qArgs = append(qArgs, f.Limit, f.Offset)
	}

	rows, err := s.db.QueryContext(ctx, q, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	posts := []*FeedPost{}
	ids := []string{}
	for rows.Next() {
		var fp FeedPost
		var catID, slug, catName sql.NullString
		var caption, location, firstName, lastName, verification sql.NullString
		var lat, lng sql.NullFloat64
		if err := rows.Scan(
			&fp.ID, &fp.ProfessionalID, &catID, &caption, &location, &fp.Sponsored, &fp.CreatedAt,
			&slug, &catName,
			&fp.Professional.ID, &fp.Professional.Name, &firstName, &lastName,
			&fp.Professional.City, &fp.Professional.Rating, &fp.Professional.ReviewCount, &verification,
			&lat, &lng,
			&fp.Professional.AvatarURL,
			&fp.LikeCount, &fp.LikedByMe, &fp.SavedByMe,
		); err != nil {
			return nil, 0, err
		}
		if catID.Valid {
			fp.CategoryID = &catID.String
		}
		fp.CategorySlug = slug.String
		fp.CategoryName = catName.String
		fp.Caption = caption.String
		fp.Location = location.String
		fp.Professional.Verified = strings.EqualFold(verification.String, "VERIFIED")
		if lat.Valid {
			fp.Professional.Latitude = &lat.Float64
		}
		if lng.Valid {
			fp.Professional.Longitude = &lng.Float64
		}
		ids = append(ids, fp.ID)
		posts = append(posts, &fp)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if len(posts) > 0 {
		media, err := s.mediaForPosts(ctx, ids)
		if err != nil {
			return nil, 0, err
		}
		for _, fp := range posts {
			fp.Images = media[fp.ID]
		}
	}
	return posts, total, nil
}

// ListSaved returns feed posts the user has bookmarked, newest save first.
func (s *Store) ListSaved(ctx context.Context, userID string, f FeedFilter) ([]*FeedPost, int64, error) {
	var total int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM post_saves ps
		JOIN posts p ON p.id = ps.post_id
		WHERE ps.user_id = ? AND p.is_active = 1`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}

	q := `SELECT
		p.id, p.professional_id, p.category_id, p.caption, p.location, p.sponsored, p.created_at,
		c.slug, c.name,
		pr.id, COALESCE(NULLIF(pr.display_name, ''), pr.business_name), u.first_name, u.last_name,
		COALESCE(pr.city, ''), pr.rating, pr.review_count, pr.verification_status,
		pr.latitude, pr.longitude,
		COALESCE(m.secure_url, ''),
		(SELECT COUNT(*) FROM post_likes l WHERE l.post_id = p.id),
		EXISTS(SELECT 1 FROM post_likes l2 WHERE l2.post_id = p.id AND l2.user_id = ?),
		1
		FROM posts p
		JOIN professionals pr ON pr.id = p.professional_id AND pr.status = 'ACTIVE'
		JOIN users u ON u.id = pr.user_id
		JOIN post_saves ps ON ps.post_id = p.id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN media_assets m ON m.id = u.avatar_media_id
		WHERE p.is_active = 1 AND ps.user_id = ?
		ORDER BY ps.created_at DESC`
	qArgs := []any{userID, userID}
	if f.Limit > 0 {
		q += ` LIMIT ? OFFSET ?`
		qArgs = append(qArgs, f.Limit, f.Offset)
	}

	rows, err := s.db.QueryContext(ctx, q, qArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	posts := []*FeedPost{}
	ids := []string{}
	for rows.Next() {
		var fp FeedPost
		var catID, slug, catName sql.NullString
		var caption, location, firstName, lastName, verification sql.NullString
		var lat, lng sql.NullFloat64
		if err := rows.Scan(
			&fp.ID, &fp.ProfessionalID, &catID, &caption, &location, &fp.Sponsored, &fp.CreatedAt,
			&slug, &catName,
			&fp.Professional.ID, &fp.Professional.Name, &firstName, &lastName,
			&fp.Professional.City, &fp.Professional.Rating, &fp.Professional.ReviewCount, &verification,
			&lat, &lng,
			&fp.Professional.AvatarURL,
			&fp.LikeCount, &fp.LikedByMe, &fp.SavedByMe,
		); err != nil {
			return nil, 0, err
		}
		if catID.Valid {
			fp.CategoryID = &catID.String
		}
		fp.CategorySlug = slug.String
		fp.CategoryName = catName.String
		fp.Caption = caption.String
		fp.Location = location.String
		fp.Professional.Verified = strings.EqualFold(verification.String, "VERIFIED")
		if lat.Valid {
			fp.Professional.Latitude = &lat.Float64
		}
		if lng.Valid {
			fp.Professional.Longitude = &lng.Float64
		}
		ids = append(ids, fp.ID)
		posts = append(posts, &fp)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if len(posts) > 0 {
		media, err := s.mediaForPosts(ctx, ids)
		if err != nil {
			return nil, 0, err
		}
		for _, fp := range posts {
			fp.Images = media[fp.ID]
		}
	}
	return posts, total, nil
}

func nullString(v *string) sql.NullString {
	if v == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *v, Valid: true}
}
func nullStr(v string) sql.NullString {
	if v == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: v, Valid: true}
}
