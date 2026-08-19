package seed

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/google/uuid"
)

// BeautyPhotos are verified, working Unsplash CDN urls used to populate demo
// feed posts so the home page has content before real uploads exist.
var BeautyPhotos = map[string][]string{
	"hair": {
		"https://images.unsplash.com/photo-1562322140-8baeececf3df?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1580618672591-eb180b1a973f?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1595476108010-b4d1f102b1b1?w=900&q=80&auto=format&fit=crop",
	},
	"nails": {
		"https://images.unsplash.com/photo-1610992015732-2449b76344bc?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1600335895229-6e75511892c8?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1594736797933-d0501ba2fe65?w=900&q=80&auto=format&fit=crop",
	},
	"lashes": {
		"https://images.unsplash.com/photo-1620331311520-246422fd82f9?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1596462502278-27bfdc403348?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1600948836101-f9ffda59d250?w=900&q=80&auto=format&fit=crop",
	},
	"brows": {
		"https://images.unsplash.com/photo-1512036666432-2181c1f26420?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1519014816548-bf5fe059798b?w=900&q=80&auto=format&fit=crop",
	},
	"makeup": {
		"https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1487412947147-5cebf100ffc2?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1596704017254-9b121068fb31?w=900&q=80&auto=format&fit=crop",
	},
	"tattoos": {
		"https://images.unsplash.com/photo-1617038220319-276d3cfab638?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1596704017254-9b121068fb31?w=900&q=80&auto=format&fit=crop",
	},
	"spa": {
		"https://images.unsplash.com/photo-1544161515-4ab6ce6db874?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1526510747491-58f928ec870f?w=900&q=80&auto=format&fit=crop",
		"https://images.unsplash.com/photo-1583001931096-959e9a1a6223?w=900&q=80&auto=format&fit=crop",
	},
}

type PostSeed struct {
	ProfessionalID string
	CategorySlug   string
	CategoryID     string
	Caption        string
	Location       string
	Sponsored      bool
	Images         []string
}

// Posts seeds a demo Instagram-style feed from existing active professionals.
// It is a no-op when posts already exist.
func Posts(ctx context.Context, db *sql.DB) error {
	var existing int64
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM posts`).Scan(&existing); err != nil {
		return fmt.Errorf("count posts: %w", err)
	}
	if existing > 0 {
		return nil
	}

	type pro struct {
		ID     string
		City   sql.NullString
		Rating float64
	}
	pros := []pro{}
	rows, err := db.QueryContext(ctx, `SELECT id, city, rating FROM professionals
		WHERE status = 'ACTIVE' ORDER BY rating DESC LIMIT 8`)
	if err != nil {
		return fmt.Errorf("load professionals: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var p pro
		if err := rows.Scan(&p.ID, &p.City, &p.Rating); err != nil {
			return err
		}
		pros = append(pros, p)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(pros) == 0 {
		return fmt.Errorf("no active professionals to seed posts")
	}

	catIDs := map[string]string{}
	for _, slug := range []string{"hair", "nails", "lashes", "brows", "makeup", "tattoos", "spa"} {
		var id string
		if err := db.QueryRowContext(ctx, `SELECT id FROM categories WHERE slug = ?`, slug).Scan(&id); err == nil {
			catIDs[slug] = id
		}
	}

	posts := []PostSeed{
		{CategorySlug: "nails", Caption: "Chrome dream set — gel overlay with a soft French edge. Lasts 3+ weeks.", Location: "Lagos", Sponsored: true},
		{CategorySlug: "hair", Caption: "Knotless braids with beads done in one sitting. Tension-free install.", Location: "Lagos"},
		{CategorySlug: "makeup", Caption: "Soft glam for a bridal shower. Waterproof, flash-ready.", Location: "Abuja", Sponsored: true},
		{CategorySlug: "lashes", Caption: "Volume lash set, natural flare. Two-hour appointment.", Location: "Lagos"},
		{CategorySlug: "brows", Caption: "Microblading healing process — day 7. Hair strokes settled beautifully.", Location: "Port Harcourt"},
		{CategorySlug: "spa", Caption: "90-minute deep tissue + facial. Glow on arrival.", Location: "Lagos"},
		{CategorySlug: "hair", Caption: "Silk press + trim. Heat protected, ends sealed.", Location: "Abuja"},
		{CategorySlug: "nails", Caption: "Ombre French done in chrome. Client's favourite to date.", Location: "Lagos"},
		{CategorySlug: "tattoos", Caption: "Permanent liner look — healed at 6 weeks. Crisp and clean.", Location: "Lagos"},
	}

	for i, ps := range posts {
		catID, ok := catIDs[ps.CategorySlug]
		if !ok {
			continue
		}
		pro := pros[i%len(pros)]
		city := pro.City.String
		if city == "" {
			city = "Lagos"
		}

		postID := uuid.NewString()
		_, err := db.ExecContext(ctx, `INSERT INTO posts
			(id, professional_id, category_id, caption, location, sponsored, is_active)
			VALUES (?, ?, ?, ?, ?, ?, 1)`,
			postID, pro.ID, catID, ps.Caption, city, ps.Sponsored)
		if err != nil {
			return fmt.Errorf("seed post %d: %w", i, err)
		}

		images := BeautyPhotos[ps.CategorySlug]
		for j, url := range images {
			if _, err := db.ExecContext(ctx, `INSERT INTO post_media (id, post_id, secure_url, display_order)
				VALUES (?, ?, ?, ?)`, uuid.NewString(), postID, url, j); err != nil {
				return fmt.Errorf("seed post media %d/%d: %w", i, j, err)
			}
		}
	}
	return nil
}
