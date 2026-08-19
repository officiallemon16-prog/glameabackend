package seed

import (
	"context"
	"database/sql"
	"fmt"
)

type CategorySeed struct {
	Slug        string
	Name        string
	Description string
	Order       int
	ImageURL    string
}

var DefaultCategories = []CategorySeed{
	{Slug: "hair", Name: "Hair", Description: "Braids, weaves, cuts, styling and more", Order: 1,
		ImageURL: "https://images.unsplash.com/photo-1562322140-8baeececf3df?w=600&q=80&auto=format&fit=crop"},
	{Slug: "nails", Name: "Nails", Description: "Manicures, pedicures, gel and acrylic nails", Order: 2,
		ImageURL: "https://images.unsplash.com/photo-1610992015732-2449b76344bc?w=600&q=80&auto=format&fit=crop"},
	{Slug: "lashes", Name: "Lashes", Description: "Classic, volume and hybrid lash extensions", Order: 3,
		ImageURL: "https://images.unsplash.com/photo-1620331311520-246422fd82f9?w=600&q=80&auto=format&fit=crop"},
	{Slug: "brows", Name: "Brows", Description: "Microblading, brow shaping and tinting", Order: 4,
		ImageURL: "https://images.unsplash.com/photo-1512036666432-2181c1f26420?w=600&q=80&auto=format&fit=crop"},
	{Slug: "makeup", Name: "Makeup", Description: "Bridal, party and everyday makeup", Order: 5,
		ImageURL: "https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=600&q=80&auto=format&fit=crop"},
	{Slug: "tattoos", Name: "Tattoos", Description: "Permanent makeup and beauty tattoos", Order: 6,
		ImageURL: "https://images.unsplash.com/photo-1617038220319-276d3cfab638?w=600&q=80&auto=format&fit=crop"},
	{Slug: "spa", Name: "Spa", Description: "Facials, body treatments and relaxation", Order: 7,
		ImageURL: "https://images.unsplash.com/photo-1544161515-4ab6ce6db874?w=600&q=80&auto=format&fit=crop"},
}

func Categories(ctx context.Context, db *sql.DB, cats []CategorySeed) error {
	for _, c := range cats {
		_, err := db.ExecContext(ctx, `INSERT INTO categories (id, slug, name, description, image_url, display_order, is_active)
			VALUES (UUID(), ?, ?, ?, ?, ?, 1)
			ON DUPLICATE KEY UPDATE
				name = VALUES(name),
				description = VALUES(description),
				image_url = VALUES(image_url),
				display_order = VALUES(display_order),
				is_active = 1`,
			c.Slug, c.Name, c.Description, c.ImageURL, c.Order)
		if err != nil {
			return fmt.Errorf("seed category %s: %w", c.Slug, err)
		}
	}

	// Clean up stray test categories.
	if _, err := db.ExecContext(ctx, `UPDATE categories SET is_active = 0 WHERE slug LIKE 'SweepCat%'`); err != nil {
		return fmt.Errorf("deactivate test categories: %w", err)
	}
	return nil
}
