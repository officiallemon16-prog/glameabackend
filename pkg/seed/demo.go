package seed

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// DemoPassword is the shared password for every demo account created by
// DemoData (e.g. amara@demo.glamea, Zainab Adeyemi@demo.glamea).
const DemoPassword = "Password123!"

// DemoData seeds a realistic demo marketplace: customer + professional users,
// profiles, services with variants, availability, deals, portfolio, completed
// bookings, reviews, conversations and notifications. It is idempotent: any
// existing demo users (and everything cascaded from them) are removed first,
// so a partially-failed run can be safely re-run.
func DemoData(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `DELETE FROM users WHERE email LIKE '%@demo.glamea'`); err != nil {
		return fmt.Errorf("clear previous demo users: %w", err)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(DemoPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash demo password: %w", err)
	}
	ph := string(hash)

	pros, err := seedProfessionals(ctx, db, ph)
	if err != nil {
		return err
	}
	if err := seedCustomers(ctx, db, ph, pros); err != nil {
		return err
	}
	return nil
}

type demoPro struct {
	UserID         string
	ID             string
	CategoryID     string
	CategorySlug   string
	City           string
	Services       []demoService
	PolicyID       string
	PolicyName     string
	ReviewCount    int
	Rating         float64
	BookingCount   int
	CompletionRate float64
}

type demoService struct {
	ID         string
	Name       string
	Price      float64
	Duration   int
	Deposit    float64
	Home       bool
	PolicyID   string
	Variants   []demoVariant
	MediaURL   string
	Portfolio  []string
	DealCode   string
	DealName   string
	DealType   string
	DealValue  float64
	DealMin    float64
	DealEnds   int // days from now
}

type demoVariant struct {
	Name         string
	PriceDelta   float64
	DurationDelta int
}

func seedProfessionals(ctx context.Context, db *sql.DB, ph string) ([]demoPro, error) {
	type cat struct{ slug, id string }
	cats := map[string]string{}
	for _, slug := range []string{"hair", "nails", "lashes", "brows", "makeup", "tattoos", "spa"} {
		var id string
		if err := db.QueryRowContext(ctx, `SELECT id FROM categories WHERE slug = ?`, slug).Scan(&id); err != nil {
			return nil, fmt.Errorf("load category %s: %w", slug, err)
		}
		cats[slug] = id
	}

	// city -> lat, lng
	coords := map[string][2]float64{
		"Lagos":          {6.5244, 3.3792},
		"Abuja":          {9.0765, 7.3986},
		"Port Harcourt":  {4.8156, 7.0498},
		"Ibadan":         {7.3775, 3.9470},
	}

	demos := []struct {
		name     string
		business string
		bio      string
		slug     string
		city     string
		exp      int
		services []demoService
	}{
		{
			name: "Zainab Adeyemi", business: "Zainab's Braid House",
			bio:  "Certified braider with 8 years of experience in knotless, box and cornrow styles. Known for tension-free installs that last up to 8 weeks.",
			slug: "hair", city: "Lagos", exp: 8,
			services: []demoService{
				{Name: "Knotless Braids", Price: 25000, Duration: 300, Deposit: 20, Home: true,
					MediaURL: "https://images.unsplash.com/photo-1595476108010-b4d1f102b1b1?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1562322140-8baeececf3df?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1580618672591-eb180b1a973f?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1595476108010-b4d1f102b1b1?w=900&q=80&auto=format&fit=crop",
					},
					Variants: []demoVariant{
						{Name: "Small size", PriceDelta: 5000, DurationDelta: 60},
						{Name: "Medium size", PriceDelta: 0, DurationDelta: 0},
					},
					DealCode: "ZAINAB20", DealName: "20% off all braids", DealType: "PERCENT",
					DealValue: 20, DealMin: 10000, DealEnds: 30},
				{Name: "Box Braids", Price: 18000, Duration: 240, Deposit: 20,
					MediaURL: "https://images.unsplash.com/photo-1580618672591-eb180b1a973f?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1595476108010-b4d1f102b1b1?w=900&q=80&auto=format&fit=crop",
					},
					Variants: []demoVariant{{Name: "With beads", PriceDelta: 2000, DurationDelta: 30}},
					DealCode: "ZAINAB20", DealName: "20% off all braids", DealType: "PERCENT",
					DealValue: 20, DealMin: 10000, DealEnds: 30},
				{Name: "Silk Press + Trim", Price: 12000, Duration: 120, Deposit: 15,
					MediaURL: "https://images.unsplash.com/photo-1600948836101-f9ffda59d250?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1562322140-8baeececf3df?w=900&q=80&auto=format&fit=crop",
					},
					DealCode: "ZAINAB20", DealName: "20% off all braids", DealType: "PERCENT",
					DealValue: 20, DealMin: 10000, DealEnds: 30},
			},
		},
		{
			name: "Simi Balogun", business: "NailArt by Simi",
			bio:  "Nail technician specializing in gel extensions, chrome and 3D nail art. 100+ five-star clients across Lagos.",
			slug: "nails", city: "Lagos", exp: 5,
			services: []demoService{
				{Name: "Gel Extension Set", Price: 20000, Duration: 150, Deposit: 30,
					MediaURL: "https://images.unsplash.com/photo-1610992015732-2449b76344bc?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1600335895229-6e75511892c8?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1610992015732-2449b76344bc?w=900&q=80&auto=format&fit=crop",
					},
					Variants: []demoVariant{
						{Name: "Chrome finish", PriceDelta: 3000, DurationDelta: 0},
						{Name: "3D art", PriceDelta: 5000, DurationDelta: 30},
					},
					DealCode: "SIMI10", DealName: "₦2000 off gel sets", DealType: "FIXED",
					DealValue: 2000, DealMin: 15000, DealEnds: 14},
				{Name: "Classic Manicure + Pedicure", Price: 12000, Duration: 90, Deposit: 20,
					MediaURL: "https://images.unsplash.com/photo-1594736797933-d0501ba2fe65?w=900&q=80&auto=format&fit=crop",
					Variants: []demoVariant{{Name: "With paraffin", PriceDelta: 2000, DurationDelta: 15}},
					DealCode: "SIMI10", DealName: "₦2000 off gel sets", DealType: "FIXED",
					DealValue: 2000, DealMin: 15000, DealEnds: 14},
			},
		},
		{
			name: "Tola Okafor", business: "Lash Loft Abuja",
			bio:  "Master lash artist for classic, volume and hybrid sets. Lash lifts and tinting for the natural look.",
			slug: "lashes", city: "Abuja", exp: 6,
			services: []demoService{
				{Name: "Volume Lash Extensions", Price: 35000, Duration: 120, Deposit: 25,
					MediaURL: "https://images.unsplash.com/photo-1620331311520-246422fd82f9?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1596462502278-27bfdc403348?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1620331311520-246422fd82f9?w=900&q=80&auto=format&fit=crop",
					},
					Variants: []demoVariant{
						{Name: "Hybrid", PriceDelta: 5000, DurationDelta: 0},
						{Name: "Classic", PriceDelta: -5000, DurationDelta: -15},
					},
					DealCode: "LASHLIFT", DealName: "Lash lift + tint bundle", DealType: "FIXED",
					DealValue: 5000, DealMin: 20000, DealEnds: 21},
				{Name: "Lash Lift + Tint", Price: 18000, Duration: 60, Deposit: 30,
					MediaURL: "https://images.unsplash.com/photo-1600948836101-f9ffda59d250?w=900&q=80&auto=format&fit=crop",
					DealCode: "LASHLIFT", DealName: "Lash lift + tint bundle", DealType: "FIXED",
					DealValue: 5000, DealMin: 20000, DealEnds: 21},
			},
		},
		{
			name: "Chidinma Eze", business: "BrowBar PH",
			bio:  "Microblading artist creating natural, hair-stroke brows. Certified by the Academy of Microblading.",
			slug: "brows", city: "Port Harcourt", exp: 4,
			services: []demoService{
				{Name: "Microblading", Price: 60000, Duration: 180, Deposit: 40,
					MediaURL: "https://images.unsplash.com/photo-1519014816548-bf5fe059798b?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1512036666432-2181c1f26420?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1519014816548-bf5fe059798b?w=900&q=80&auto=format&fit=crop",
					},
					DealCode: "BROW15", DealName: "15% off first microblade", DealType: "PERCENT",
					DealValue: 15, DealMin: 40000, DealEnds: 45},
				{Name: "Brow Shaping + Tint", Price: 8000, Duration: 45, Deposit: 20,
					MediaURL: "https://images.unsplash.com/photo-1512036666432-2181c1f26420?w=900&q=80&auto=format&fit=crop",
					DealCode: "BROW15", DealName: "15% off first microblade", DealType: "PERCENT",
					DealValue: 15, DealMin: 40000, DealEnds: 45},
			},
		},
		{
			name: "Ngozi Nwosu", business: "Glam by Ngozi",
			bio:  "Bridal and editorial makeup artist. Flash-proof, long-wear looks for every skin tone.",
			slug: "makeup", city: "Abuja", exp: 9,
			services: []demoService{
				{Name: "Bridal Makeup", Price: 80000, Duration: 180, Deposit: 50, Home: true,
					MediaURL: "https://images.unsplash.com/photo-1487412947147-5cebf100ffc2?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1487412947147-5cebf100ffc2?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1596704017254-9b121068fb31?w=900&q=80&auto=format&fit=crop",
					},
					Variants: []demoVariant{{Name: "+ lashes", PriceDelta: 5000, DurationDelta: 0}},
					DealCode: "GLAM10", DealName: "10% off bridal glam", DealType: "PERCENT",
					DealValue: 10, DealMin: 50000, DealEnds: 60},
				{Name: "Event Glam (Soft)", Price: 35000, Duration: 90, Deposit: 30,
					MediaURL: "https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=900&q=80&auto=format&fit=crop",
					DealCode: "GLAM10", DealName: "10% off bridal glam", DealType: "PERCENT",
					DealValue: 10, DealMin: 50000, DealEnds: 60},
			},
		},
		{
			name: "Yemi Akin", business: "Ink & Beauty",
			bio:  "Permanent makeup artist: lip blush, eyeliner and beauty marks. Sterile, numbed and comfortable sessions.",
			slug: "tattoos", city: "Lagos", exp: 7,
			services: []demoService{
				{Name: "Lip Blush", Price: 75000, Duration: 150, Deposit: 50,
					MediaURL: "https://images.unsplash.com/photo-1596704017254-9b121068fb31?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1617038220319-276d3cfab638?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1596704017254-9b121068fb31?w=900&q=80&auto=format&fit=crop",
					},
					DealCode: "INK20", DealName: "₦5000 off lip blush", DealType: "FIXED",
					DealValue: 5000, DealMin: 50000, DealEnds: 30},
				{Name: "Permanent Eyeliner", Price: 50000, Duration: 120, Deposit: 50,
					MediaURL: "https://images.unsplash.com/photo-1617038220319-276d3cfab638?w=900&q=80&auto=format&fit=crop",
					DealCode: "INK20", DealName: "₦5000 off lip blush", DealType: "FIXED",
					DealValue: 5000, DealMin: 50000, DealEnds: 30},
			},
		},
		{
			name: "Blessing Okon", business: "Serene Spa",
			bio:  "Licensed therapist for facials, deep-tissue massage and full-body glow treatments.",
			slug: "spa", city: "Lagos", exp: 10,
			services: []demoService{
				{Name: "Deep Tissue Massage (90min)", Price: 40000, Duration: 90, Deposit: 25, Home: true,
					MediaURL: "https://images.unsplash.com/photo-1544161515-4ab6ce6db874?w=900&q=80&auto=format&fit=crop",
					Portfolio: []string{
						"https://images.unsplash.com/photo-1544161515-4ab6ce6db874?w=900&q=80&auto=format&fit=crop",
						"https://images.unsplash.com/photo-1583001931096-959e9a1a6223?w=900&q=80&auto=format&fit=crop",
					},
					DealCode: "SPA15", DealName: "15% off spa day", DealType: "PERCENT",
					DealValue: 15, DealMin: 30000, DealEnds: 21},
				{Name: "Signature Facial", Price: 25000, Duration: 60, Deposit: 20,
					MediaURL: "https://images.unsplash.com/photo-1526510747491-58f928ec870f?w=900&q=80&auto=format&fit=crop",
					Variants: []demoVariant{{Name: "With LED therapy", PriceDelta: 5000, DurationDelta: 15}},
					DealCode: "SPA15", DealName: "15% off spa day", DealType: "PERCENT",
					DealValue: 15, DealMin: 30000, DealEnds: 21},
			},
		},
	}

	out := make([]demoPro, 0, len(demos))
	for i, d := range demos {
		userID := uuid.NewString()
		proID := uuid.NewString()
		city := d.city
		c := coords[city]
		policyID := uuid.NewString()

		if _, err := db.ExecContext(ctx, `INSERT INTO users
			(id, email, phone, first_name, last_name, role, status, password_hash, email_verified_at, phone_verified_at)
			VALUES (?, ?, ?, ?, ?, 'PROFESSIONAL', 'ACTIVE', ?, NOW(), NOW())`,
			userID, d.name+"@demo.glamea", demoPhone(i, "8"), firstName(d.name), lastName(d.name), ph); err != nil {
			return nil, fmt.Errorf("insert pro user %s: %w", d.name, err)
		}

		rating := 4.8 - float64(i%4)*0.1
		reviewCount := 8 + i*3
		bookingCount := 20 + i*6
		completionRate := 95 - float64(i%3)*2
		if _, err := db.ExecContext(ctx, `INSERT INTO professionals
			(id, user_id, business_name, display_name, bio, category_id, experience_years, rating, review_count,
			 booking_count, completion_rate, status, verification_status, trust_score, latitude, longitude,
			 address_line, city, country, timezone, home_service_enabled, service_radius_km, travel_fee_per_km)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', 'VERIFIED', ?, ?, ?, ?, ?, 'NG', 'Africa/Lagos', ?, ?, ?)`,
			proID, userID, d.business, d.name, d.bio, cats[d.slug], d.exp, rating, reviewCount,
			bookingCount, completionRate, trustScore(rating), c[0], c[1], d.business+" Studio", city,
			hasHomeService(d.services), 25, 250); err != nil {
			return nil, fmt.Errorf("insert professional %s: %w", d.name, err)
		}

		if _, err := db.ExecContext(ctx, `INSERT INTO cancellation_policies
			(id, professional_id, name, free_cancel_hours, cancel_fee_percent, is_default)
			VALUES (?, ?, 'Standard 24h', 24, 20, 1)`, policyID, proID); err != nil {
			return nil, fmt.Errorf("insert policy %s: %w", d.name, err)
		}

		pro := demoPro{
			UserID: userID, ID: proID, CategoryID: cats[d.slug], CategorySlug: d.slug,
			City: city, PolicyID: policyID, PolicyName: "Standard 24h",
			ReviewCount: reviewCount, Rating: rating, BookingCount: bookingCount, CompletionRate: completionRate,
		}

		for j, svc := range d.services {
			svcID := uuid.NewString()
			if _, err := db.ExecContext(ctx, `INSERT INTO services
				(id, professional_id, category_id, name, description, base_price, currency, duration_minutes,
				 deposit_percentage, home_service_available, cancellation_policy_id, display_order, is_active)
				VALUES (?, ?, ?, ?, ?, ?, 'NGN', ?, ?, ?, ?, ?, 1)`,
				svcID, proID, cats[d.slug], svc.Name, svc.Name+" by "+d.business,
				svc.Price, svc.Duration, svc.Deposit, svc.Home, policyID, j); err != nil {
				return nil, fmt.Errorf("insert service %s: %w", svc.Name, err)
			}
			svc.ID = svcID
			svc.PolicyID = policyID

			for k, v := range svc.Variants {
				if _, err := db.ExecContext(ctx, `INSERT INTO service_variants
					(id, service_id, name, price_delta, duration_delta_minutes, is_active)
					VALUES (?, ?, ?, ?, ?, 1)`,
					uuid.NewString(), svcID, v.Name, v.PriceDelta, v.DurationDelta); err != nil {
					return nil, fmt.Errorf("insert variant %s/%s: %w", svc.Name, v.Name, err)
				}
				_ = k
			}
			pro.Services = append(pro.Services, svc)
		}

		if err := seedProMedia(ctx, db, proID, userID, pro); err != nil {
			return nil, err
		}

		if err := seedWindows(ctx, db, proID); err != nil {
			return nil, err
		}

		if err := seedDeals(ctx, db, proID, pro); err != nil {
			return nil, err
		}

		out = append(out, pro)
	}
	return out, nil
}

func seedCustomers(ctx context.Context, db *sql.DB, ph string, pros []demoPro) error {
	customers := []struct {
		email     string
		first, last string
	}{
		{"amara@demo.glamea", "Amara", "Okafor"},
		{"kemi@demo.glamea", "Kemi", "Adeyemi"},
		{"emeka@demo.glamea", "Emeka", "Obi"},
		{"halima@demo.glamea", "Halima", "Yusuf"},
		{"femi@demo.glamea", "Femi", "Adetola"},
	}
	ids := []string{}
	for i, c := range customers {
		userID := uuid.NewString()
		if _, err := db.ExecContext(ctx, `INSERT INTO users
			(id, email, phone, first_name, last_name, role, status, password_hash, email_verified_at, phone_verified_at)
			VALUES (?, ?, ?, ?, ?, 'CUSTOMER', 'ACTIVE', ?, NOW(), NOW())`,
			userID, c.email, demoPhone(i, "9"), c.first, c.last, ph); err != nil {
			return fmt.Errorf("insert customer %s: %w", c.email, err)
		}
		ids = append(ids, userID)
	}

	// Completed bookings + reviews for every professional.
	if err := seedBookingsAndReviews(ctx, db, pros, ids); err != nil {
		return err
	}

	// Conversations + messages on a couple of bookings.
	if err := seedConversations(ctx, db, pros, ids); err != nil {
		return err
	}

	// Notifications for the first customer.
	if err := seedNotifications(ctx, db, ids[0]); err != nil {
		return err
	}

	return nil
}

func seedProMedia(ctx context.Context, db *sql.DB, proID, userID string, pro demoPro) error {
	for _, svc := range pro.Services {
		for _, url := range svc.Portfolio {
			mediaID := uuid.NewString()
			if _, err := db.ExecContext(ctx, `INSERT INTO media_assets
				(id, uploader_id, provider, public_id, resource_type, format, secure_url)
				VALUES (?, ?, 'seed', ?, 'image', 'jpg', ?)`,
				mediaID, userID, uuid.NewString(), url); err != nil {
				return fmt.Errorf("insert media for %s: %w", pro.CategorySlug, err)
			}
			if _, err := db.ExecContext(ctx, `INSERT INTO portfolio_items
				(id, professional_id, media_asset_id, service_id, caption, is_featured, display_order, is_active)
				VALUES (?, ?, ?, ?, ?, 0, 0, 1)`,
				uuid.NewString(), proID, mediaID, svc.ID, svc.Name); err != nil {
				return fmt.Errorf("insert portfolio for %s: %w", pro.CategorySlug, err)
			}
		}
	}
	return nil
}

func seedWindows(ctx context.Context, db *sql.DB, proID string) error {
	// Mon-Fri 9am-5pm, Sat 9am-2pm.
	windows := []struct {
		day, start, end int
	}{
		{1, 540, 1020}, {2, 540, 1020}, {3, 540, 1020}, {4, 540, 1020}, {5, 540, 1020}, {6, 540, 840},
	}
	for _, w := range windows {
		if _, err := db.ExecContext(ctx, `INSERT INTO availability_windows
			(id, professional_id, day_of_week, start_minutes, end_minutes, is_active)
			VALUES (?, ?, ?, ?, ?, 1)`,
			uuid.NewString(), proID, w.day, w.start, w.end); err != nil {
			return fmt.Errorf("insert window: %w", err)
		}
	}
	return nil
}

func seedDeals(ctx context.Context, db *sql.DB, proID string, pro demoPro) error {
	seen := map[string]bool{}
	for _, svc := range pro.Services {
		if svc.DealCode == "" || seen[svc.DealCode] {
			continue
		}
		seen[svc.DealCode] = true
		dealID := uuid.NewString()
		starts := time.Now().Add(-7 * 24 * time.Hour).UTC().Truncate(time.Second)
		ends := time.Now().Add(time.Duration(svc.DealEnds) * 24 * time.Hour).UTC().Truncate(time.Second)
		if _, err := db.ExecContext(ctx, `INSERT INTO deals
			(id, professional_id, code, name, description, discount_type, discount_value, min_order_amount,
			 usage_limit, times_used, starts_at, ends_at, is_active)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
			dealID, proID, svc.DealCode, svc.DealName, svc.DealName+" by "+pro.City+" professional",
			svc.DealType, svc.DealValue, svc.DealMin, 100, 3, starts, ends); err != nil {
			return fmt.Errorf("insert deal %s: %w", svc.DealCode, err)
		}
		for _, s := range pro.Services {
			if s.DealCode == svc.DealCode {
				if _, err := db.ExecContext(ctx,
					`INSERT IGNORE INTO deal_services (deal_id, service_id) VALUES (?, ?)`, dealID, s.ID); err != nil {
					return fmt.Errorf("link deal service: %w", err)
				}
			}
		}
	}
	return nil
}

func seedBookingsAndReviews(ctx context.Context, db *sql.DB, pros []demoPro, customerIDs []string) error {
	// A few completed bookings + reviews for every professional so their
	// profiles show recent, realistic social proof.
	reviews := []struct {
		pro      int
		customer int
		daysAgo  int
		rating   int
		comment  string
		response string
	}{
		{0, 0, 21, 5, "Knotless braids came out perfectly, lasted 7 weeks with zero tension. Highly recommend!", "Thank you Amara! So glad you loved them."},
		{0, 1, 14, 5, "Best braider in Lagos, hands down. She even matched my hair texture perfectly.", ""},
		{0, 2, 6, 4, "Gorgeous install, ran a little late but worth the wait.", ""},
		{1, 2, 12, 5, "Chrome gel set is still flawless after 3 weeks. My new favourite nail tech.", ""},
		{1, 3, 9, 4, "Lovely work, though the appointment ran a little over. Gorgeous finish.", ""},
		{1, 4, 3, 5, "Booked a pedicure and left with a full set. So friendly!", "Come back anytime!"},
		{2, 4, 18, 5, "Volume lashes are so light I forgot I had them on. Two hours, zero pain.", "Glad you love them! See you in 3 weeks."},
		{2, 0, 7, 5, "My lash lift lasted over 6 weeks. Best money I've spent this year.", ""},
		{2, 1, 2, 5, "Incredible attention to detail. My natural lashes are fully intact.", ""},
		{3, 1, 30, 5, "Microblading healing went exactly as she explained. Brows look so natural.", ""},
		{3, 2, 16, 4, "Really happy with the shaping. Tint could be a touch stronger next time.", ""},
		{3, 3, 5, 5, "Gentle, hygienic and the results are stunning. Worth every naira.", ""},
		{4, 3, 25, 5, "Bridal glam survived 12 hours of dancing and photos. Flawless.", "It was an honour to do your bridal makeup!"},
		{4, 4, 11, 5, "Soft glam for a work event, so elegant. Booked again for my sister's wedding.", ""},
		{4, 0, 4, 5, "Tried a new lip colour and Ngozi nailed the tone for my skin.", ""},
		{5, 0, 28, 5, "Lip blush healed beautifully, very natural colour payoff.", "Thanks! Enjoy your new glow."},
		{5, 2, 19, 5, "Felt zero pain and the aftercare guide was super clear.", ""},
		{5, 4, 8, 4, "Great result, though the consultation ran longer than planned.", ""},
		{6, 1, 22, 5, "The deep tissue massage fixed a knot I'd had for months.", ""},
		{6, 3, 13, 5, "Serene is the right name — I fell asleep twice. Glow is unreal.", "Sleep is the best review!"},
		{6, 0, 5, 5, "Signature facial + LED therapy. My skin has never looked better.", ""},
	}

	for i, r := range reviews {
		pro := pros[r.pro%len(pros)]
		cust := customerIDs[r.customer%len(customerIDs)]
		svc := pro.Services[0]
		start := time.Now().Add(-time.Duration(r.daysAgo) * 24 * time.Hour).UTC().Truncate(time.Second)
		end := start.Add(time.Duration(svc.Duration) * time.Minute)
		bookingID := uuid.NewString()

		if _, err := db.ExecContext(ctx, `INSERT INTO bookings
			(id, professional_id, customer_id, service_id, status, start_at, end_at, base_amount,
			 total_amount, deposit_amount, currency, home_service)
			VALUES (?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, 'NGN', ?)`,
			bookingID, pro.ID, cust, svc.ID, start, end, svc.Price, svc.Price,
			svc.Price*svc.Deposit/100, svc.Home); err != nil {
			return fmt.Errorf("insert booking %d: %w", i, err)
		}

		var response, respondedAt any
		if r.response != "" {
			response = r.response
			respondedAt = time.Now().UTC()
		}
		revID := uuid.NewString()
		if _, err := db.ExecContext(ctx, `INSERT INTO reviews
			(id, booking_id, professional_id, customer_id, service_id, rating, comment, response,
			 responded_at, is_published, created_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, DATE_SUB(NOW(), INTERVAL ? DAY))`,
			revID, bookingID, pro.ID, cust, svc.ID, r.rating, r.comment, response, respondedAt, r.daysAgo); err != nil {
			return fmt.Errorf("insert review %d: %w", i, err)
		}
	}

	// Recompute each professional's aggregate rating/counts so the profile
	// card matches the reviews actually seeded.
	for _, pro := range pros {
		var rating, count float64
		if err := db.QueryRowContext(ctx, `SELECT COALESCE(AVG(rating),0), COUNT(*) FROM reviews
			WHERE professional_id = ? AND is_published = 1`, pro.ID).Scan(&rating, &count); err != nil {
			return fmt.Errorf("recompute rating for %s: %w", pro.CategorySlug, err)
		}
		var bookings int64
		if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE professional_id = ?`, pro.ID).Scan(&bookings); err != nil {
			return fmt.Errorf("recompute bookings for %s: %w", pro.CategorySlug, err)
		}
		pro.Rating = math.Round(rating*20) / 20
		pro.ReviewCount = int(count)
		pro.BookingCount = int(bookings)
		pro.CompletionRate = 100
		if _, err := db.ExecContext(ctx, `UPDATE professionals
			SET rating = ?, review_count = ?, booking_count = ?, completion_rate = ?
			WHERE id = ?`, pro.Rating, pro.ReviewCount, pro.BookingCount, pro.CompletionRate, pro.ID); err != nil {
			return fmt.Errorf("update aggregates for %s: %w", pro.CategorySlug, err)
		}
	}
	return nil
}

func seedConversations(ctx context.Context, db *sql.DB, pros []demoPro, customerIDs []string) error {
	// Conversations need a booking. Reuse the most recent completed booking
	// by grabbing one per professional from the reviews we just seeded.
	for i := 0; i < 4 && i < len(pros); i++ {
		pro := pros[i]
		cust := customerIDs[i%len(customerIDs)]
		var bookingID, serviceName string
		var startAt time.Time
		if err := db.QueryRowContext(ctx, `SELECT b.id, s.name, b.start_at FROM bookings b
			JOIN services s ON s.id = b.service_id
			WHERE b.professional_id = ? AND b.status = 'COMPLETED'
			ORDER BY b.start_at DESC LIMIT 1`, pro.ID).Scan(&bookingID, &serviceName, &startAt); err != nil {
			if err == sql.ErrNoRows {
				continue
			}
			return fmt.Errorf("load booking for conversation: %w", err)
		}

		convID := uuid.NewString()
		lastMsg := "Hello! Just confirming your appointment for " + serviceName + ". See you soon!"
		if _, err := db.ExecContext(ctx, `INSERT INTO conversations
			(id, booking_id, customer_id, professional_id, last_message, last_message_at)
			VALUES (?, ?, ?, ?, ?, ?)`,
			convID, bookingID, cust, pro.ID, lastMsg, startAt.Add(2*time.Hour).UTC()); err != nil {
			return fmt.Errorf("insert conversation: %w", err)
		}

		msgs := [][3]string{
			{pro.UserID, cust, "Hi! I just booked " + serviceName + ". Can't wait!"},
			{cust, pro.UserID, "Thank you for booking! Please arrive 10 minutes early."},
			{pro.UserID, cust, lastMsg},
		}
		for j, m := range msgs {
			if _, err := db.ExecContext(ctx, `INSERT INTO messages
				(id, conversation_id, sender_id, recipient_id, body, is_read, created_at)
				VALUES (?, ?, ?, ?, ?, 1, DATE_SUB(NOW(), INTERVAL ? HOUR))`,
				uuid.NewString(), convID, m[0], m[1], m[2], 2+j); err != nil {
				return fmt.Errorf("insert message: %w", err)
			}
		}
	}
	return nil
}

func seedNotifications(ctx context.Context, db *sql.DB, customerID string) error {
	notifs := []struct {
		type_ string
		title string
		body  string
		days  int
	}{
		{"BOOKING_CONFIRMED", "Booking confirmed", "Zainab Adeyemi confirmed your Knotless Braids appointment.", 5},
		{"NEW_DEAL", "New deal available", "20% off all braids at Zainab's Braid House. Ends soon.", 3},
		{"REVIEW_REPLY", "A professional replied to your review", "Zainab Adeyemi: 'Thank you Amara! So glad you loved them.'", 2},
	}
	for _, n := range notifs {
		if _, err := db.ExecContext(ctx, `INSERT INTO notifications
			(id, user_id, type, title, body, is_read, created_at)
			VALUES (?, ?, ?, ?, ?, 0, DATE_SUB(NOW(), INTERVAL ? DAY))`,
			uuid.NewString(), customerID, n.type_, n.title, n.body, n.days); err != nil {
			return fmt.Errorf("insert notification: %w", err)
		}
	}
	return nil
}

func demoPhone(i int, prefix string) string {
	return fmt.Sprintf("+234%s%010d", prefix, 7012345000+i)
}

func firstName(full string) string {
	for i := 0; i < len(full); i++ {
		if full[i] == ' ' {
			return full[:i]
		}
	}
	return full
}

func lastName(full string) string {
	for i := 0; i < len(full); i++ {
		if full[i] == ' ' {
			return full[i+1:]
		}
	}
	return ""
}

func trustScore(rating float64) float64 {
	if rating >= 4.8 {
		return 98
	}
	return 90 + (rating-4.0)*10
}

func hasHomeService(services []demoService) bool {
	for _, s := range services {
		if s.Home {
			return true
		}
	}
	return false
}
