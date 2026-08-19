package analytics

import (
	"context"
	"database/sql"
	"time"
)

type Summary struct {
	TotalBookings   int64   `json:"total_bookings"`
	Completed       int64   `json:"completed"`
	Cancelled       int64   `json:"cancelled"`
	GrossRevenue    float64 `json:"gross_revenue"`
	PlatformFees    float64 `json:"platform_fees"`
	PayoutsPaid     float64 `json:"payouts_paid"`
	AvgBookingValue float64 `json:"avg_booking_value"`
	ConversionRate  float64 `json:"conversion_rate"`
}

type BookingTrend struct {
	Date    string  `json:"date"`
	Count   int64   `json:"count"`
	Revenue float64 `json:"revenue"`
}

type ServiceRevenue struct {
	ServiceID string  `json:"service_id"`
	Name      string  `json:"name"`
	Count     int64   `json:"count"`
	Revenue   float64 `json:"revenue"`
}

type ProPerformance struct {
	ProfessionalID string  `json:"professional_id"`
	BusinessName   string  `json:"business_name"`
	Bookings       int64   `json:"bookings"`
	Revenue        float64 `json:"revenue"`
	Rating         float64 `json:"rating"`
}

type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Summary(ctx context.Context, from, to string) (*Summary, error) {
	sum := &Summary{}
	var avg sql.NullFloat64

	where := " AND created_at >= ? AND created_at <= ?"
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE 1=1`+where, from, to).Scan(&sum.TotalBookings); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE status = 'COMPLETED'`+where, from, to).Scan(&sum.Completed); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM bookings WHERE status = 'CANCELLED'`+where, from, to).Scan(&sum.Cancelled); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status = 'COMPLETED'`+where, from, to).Scan(&sum.GrossRevenue); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(amount),0) FROM wallet_transactions WHERE category = 'PLATFORM_FEE' AND user_id = ?
		AND created_at >= ? AND created_at <= ?`,
		"00000000-0000-0000-0000-000000000000", from, to).Scan(&sum.PlatformFees); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(amount),0) FROM payouts WHERE status = 'PAID'
		AND paid_at >= ? AND paid_at <= ?`, from, to).Scan(&sum.PayoutsPaid); err != nil {
		return nil, err
	}
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(AVG(total_amount),0) FROM bookings WHERE status = 'COMPLETED'`+where, from, to).Scan(&avg); err != nil {
		return nil, err
	}
	sum.AvgBookingValue = avg.Float64
	if sum.TotalBookings > 0 {
		sum.ConversionRate = float64(sum.Completed) / float64(sum.TotalBookings) * 100
	}
	return sum, nil
}

func (s *Store) Trends(ctx context.Context, from, to string) ([]*BookingTrend, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT DATE(created_at), COUNT(*),
		COALESCE(SUM(CASE WHEN status = 'COMPLETED' THEN total_amount ELSE 0 END),0)
		FROM bookings WHERE created_at >= ? AND created_at <= ?
		GROUP BY DATE(created_at) ORDER BY DATE(created_at)`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*BookingTrend{}
	for rows.Next() {
		t := &BookingTrend{}
		if err := rows.Scan(&t.Date, &t.Count, &t.Revenue); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Store) RevenueByService(ctx context.Context, from, to string) ([]*ServiceRevenue, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT b.service_id, s.name, COUNT(*),
		COALESCE(SUM(CASE WHEN b.status = 'COMPLETED' THEN b.total_amount ELSE 0 END),0)
		FROM bookings b LEFT JOIN services s ON s.id = b.service_id
		WHERE b.created_at >= ? AND b.created_at <= ?
		GROUP BY b.service_id, s.name ORDER BY 4 DESC`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*ServiceRevenue{}
	for rows.Next() {
		r := &ServiceRevenue{}
		if err := rows.Scan(&r.ServiceID, &r.Name, &r.Count, &r.Revenue); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) TopProfessionals(ctx context.Context, from, to string, limit int) ([]*ProPerformance, error) {
	if limit <= 0 {
		limit = 10
	}
	rows, err := s.db.QueryContext(ctx, `SELECT p.id, COALESCE(p.business_name, p.display_name, ''), COUNT(*),
		COALESCE(SUM(CASE WHEN b.status = 'COMPLETED' THEN b.total_amount ELSE 0 END),0), COALESCE(p.rating,0)
		FROM bookings b JOIN professionals p ON p.id = b.professional_id
		WHERE b.created_at >= ? AND b.created_at <= ?
		GROUP BY p.id, p.business_name, p.display_name, p.rating ORDER BY 4 DESC LIMIT ?`, from, to, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*ProPerformance{}
	for rows.Next() {
		p := &ProPerformance{}
		if err := rows.Scan(&p.ProfessionalID, &p.BusinessName, &p.Bookings, &p.Revenue, &p.Rating); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func DefaultRange() (string, string) {
	to := time.Now().Add(24 * time.Hour).Format("2006-01-02")
	from := time.Now().AddDate(0, -1, 0).Format("2006-01-02")
	return from, to
}
