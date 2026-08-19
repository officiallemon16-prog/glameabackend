package bookings

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/glamea/glamea-backend/internal/availability"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/services"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/redis/go-redis/v9"
)

type Service struct {
	store        *Store
	proStore     *professionals.Store
	serviceStore *services.Store
	availStore   *availability.Store
	rdb          *redis.Client
	slotLockTTL  time.Duration
	buffer       time.Duration
	travelTime   time.Duration
	hooks        *Hooks
}

type Options struct {
	Buffer     time.Duration
	TravelTime time.Duration
}

type Hooks struct {
	OnCreated   func(ctx context.Context, b *Booking) error
	OnConfirmed func(ctx context.Context, b *Booking) error
	OnStarted   func(ctx context.Context, b *Booking) error
	OnCompleted func(ctx context.Context, b *Booking) error
	OnCancelled func(ctx context.Context, b *Booking) error
}

func (s *Service) SetHooks(h *Hooks) {
	s.hooks = h
}

func (s *Service) fire(hook func(ctx context.Context, b *Booking) error, b *Booking) {
	if s.hooks == nil || hook == nil {
		return
	}
	_ = hook(context.Background(), b)
}

func NewService(store *Store, proStore *professionals.Store, serviceStore *services.Store,
	availStore *availability.Store, rdb *redis.Client, slotLockTTL time.Duration, opts Options) *Service {
	return &Service{
		store:        store,
		proStore:     proStore,
		serviceStore: serviceStore,
		availStore:   availStore,
		rdb:          rdb,
		slotLockTTL:  slotLockTTL,
		buffer:       opts.Buffer,
		travelTime:   opts.TravelTime,
	}
}

// acquireSlotLock atomically claims a slot in Redis. A nil client (Redis disabled)
// fails closed so a slot is never double-booked.
func (s *Service) acquireSlotLock(ctx context.Context, key, owner string) (bool, error) {
	if s.rdb == nil {
		return false, httpx.ServiceUnavailable("cache_unavailable", "booking is temporarily unavailable, please retry")
	}
	return s.rdb.SetNX(ctx, key, owner, s.slotLockTTL).Result()
}

func (s *Service) releaseSlotLock(ctx context.Context, key string) {
	if s.rdb != nil {
		_ = s.rdb.Del(ctx, key).Err()
	}
}

type CreateInput struct {
	ServiceID       string
	VariantID       *string
	StartAt         time.Time
	HomeService     bool
	LocationLat     *float64
	LocationLng     *float64
	LocationAddress string
	CustomerNotes   string
	IdempotencyKey  string
}

func (s *Service) Create(ctx context.Context, customerID string, in CreateInput) (*Booking, bool, error) {
	if in.ServiceID == "" {
		return nil, false, httpx.BadRequest("service_required", "service_id is required")
	}
	if in.StartAt.IsZero() {
		return nil, false, httpx.BadRequest("start_at_required", "start_at is required")
	}
	if in.StartAt.Before(time.Now().Add(-5 * time.Minute)) {
		return nil, false, httpx.BadRequest("start_at_past", "start_at cannot be in the past")
	}

	if in.IdempotencyKey != "" {
		existing, err := s.store.GetByIdempotencyKey(ctx, in.IdempotencyKey)
		if err == nil {
			return existing, false, nil
		}
		if err != sql.ErrNoRows {
			return nil, false, err
		}
	}

	svc, err := s.serviceStore.GetByID(ctx, in.ServiceID)
	if err != nil {
		return nil, false, err
	}
	if !svc.IsActive {
		return nil, false, httpx.Conflict("service_inactive", "this service is no longer available")
	}
	pro, err := s.proStore.GetByID(ctx, svc.ProfessionalID)
	if err != nil {
		return nil, false, err
	}
	if pro.Status != professionals.StatusActive {
		return nil, false, httpx.Conflict("professional_unavailable", "this professional is not available")
	}

	var variant *services.ServiceVariant
	if in.VariantID != nil && *in.VariantID != "" {
		for i := range svc.Variants {
			if svc.Variants[i].ID == *in.VariantID {
				variant = &svc.Variants[i]
				break
			}
		}
		if variant == nil {
			return nil, false, httpx.BadRequest("invalid_variant", "variant does not belong to this service")
		}
	}

	duration := svc.DurationMinutes
	if variant != nil {
		duration += variant.DurationDeltaMinutes
	}
	endAt := in.StartAt.Add(time.Duration(duration) * time.Minute)

	checkStart, checkEnd := s.checkBounds(in.StartAt, endAt, in.HomeService)
	ok, err := s.slotAvailable(ctx, pro, checkStart, checkEnd, "")
	if err != nil {
		return nil, false, err
	}
	if !ok {
		return nil, false, httpx.Conflict("slot_unavailable", "the requested time is not available")
	}

	lockKey := fmt.Sprintf("booking:slot:%s:%d", pro.ID, in.StartAt.Unix())
	acquired, err := s.acquireSlotLock(ctx, lockKey, customerID)
	if err != nil {
		return nil, false, err
	}
	if !acquired {
		return nil, false, httpx.Conflict("slot_just_booked", "this slot was just booked by someone else")
	}
	defer s.releaseSlotLock(ctx, lockKey)

	base := svc.BasePrice
	if variant != nil {
		base += variant.PriceDelta
	}
	deposit := roundMoney(base * svc.DepositPercentage / 100)

	created, err := s.store.CreateIfSlotFree(ctx, CreateData{
		ProfessionalID:       pro.ID,
		CustomerID:           customerID,
		ServiceID:            svc.ID,
		VariantID:            in.VariantID,
		StartAt:              in.StartAt,
		EndAt:                endAt,
		BaseAmount:           base,
		TotalAmount:          base,
		DepositAmount:        deposit,
		Currency:             svc.Currency,
		HomeService:          in.HomeService,
		LocationLat:          in.LocationLat,
		LocationLng:          in.LocationLng,
		LocationAddress:      in.LocationAddress,
		CustomerNotes:        in.CustomerNotes,
		CancellationPolicyID: svc.CancellationPolicyID,
		IdempotencyKey:       in.IdempotencyKey,
	}, checkStart, checkEnd)
	if err != nil {
		return nil, false, err
	}
	s.fire(s.hooks.OnCreated, created)
	return created, true, nil
}

func (s *Service) Get(ctx context.Context, userID string, bookingID string) (*Booking, error) {
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	ok, err := s.isParticipant(ctx, userID, b)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, httpx.Forbidden("not_your_booking", "you are not part of this booking")
	}
	if err := s.attachBalances(ctx, []*Booking{b}); err != nil {
		return nil, err
	}
	return b, nil
}

func (s *Service) ListForCustomer(ctx context.Context, customerID string, limit, offset int) ([]*Booking, error) {
	bookings, err := s.store.ListForCustomer(ctx, customerID, limit, offset)
	if err != nil {
		return nil, err
	}
	if err := s.attachBalances(ctx, bookings); err != nil {
		return nil, err
	}
	return bookings, nil
}

func (s *Service) ListForProfessional(ctx context.Context, userID string, limit, offset int) ([]*Booking, error) {
	pro, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	bookings, err := s.store.ListForProfessional(ctx, pro.ID, limit, offset)
	if err != nil {
		return nil, err
	}
	if err := s.attachBalances(ctx, bookings); err != nil {
		return nil, err
	}
	return bookings, nil
}

// attachBalances fills each booking's BalanceAmount from the sums of its
// SUCCEEDED payment intents, clamped at zero.
func (s *Service) attachBalances(ctx context.Context, bookings []*Booking) error {
	if len(bookings) == 0 {
		return nil
	}
	ids := make([]string, len(bookings))
	for i, b := range bookings {
		ids[i] = b.ID
	}
	paid, err := s.store.PaidAmounts(ctx, ids)
	if err != nil {
		return err
	}
	for _, b := range bookings {
		balance := roundMoney(b.TotalAmount - paid[b.ID])
		if balance < 0 {
			balance = 0
		}
		b.BalanceAmount = balance
	}
	return nil
}

func (s *Service) Confirm(ctx context.Context, userID, bookingID string) (*Booking, error) {
	pro, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if b.ProfessionalID != pro.ID {
		return nil, httpx.Forbidden("not_your_booking", "this booking belongs to another professional")
	}
	if b.DepositAmount > 0 {
		paid, err := s.store.HasSucceededDeposit(ctx, b.ID)
		if err != nil {
			return nil, err
		}
		if !paid {
			return nil, httpx.Conflict("deposit_required", "the customer must pay the deposit before this booking can be confirmed")
		}
	}
	updated, err := s.store.UpdateStatus(ctx, b.ID, b.Status, StatusConfirmed, &userID, "confirmed by professional")
	if err != nil {
		return nil, err
	}
	s.fire(s.hooks.OnConfirmed, updated)
	return updated, nil
}

func (s *Service) Start(ctx context.Context, userID, bookingID string) (*Booking, error) {
	pro, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if b.ProfessionalID != pro.ID {
		return nil, httpx.Forbidden("not_your_booking", "this booking belongs to another professional")
	}
	if b.Status != StatusConfirmed {
		return nil, httpx.Conflict("booking_not_confirmed", "only confirmed bookings can be started")
	}
	updated, err := s.store.UpdateStatus(ctx, b.ID, b.Status, StatusInProgress, &userID, "service started")
	if err != nil {
		return nil, err
	}
	s.fire(s.hooks.OnStarted, updated)
	return updated, nil
}

func (s *Service) Complete(ctx context.Context, userID, bookingID string) (*Booking, error) {
	pro, err := s.requireProfessional(ctx, userID)
	if err != nil {
		return nil, err
	}
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if b.ProfessionalID != pro.ID {
		return nil, httpx.Forbidden("not_your_booking", "this booking belongs to another professional")
	}
	if b.Status != StatusInProgress && b.Status != StatusConfirmed {
		return nil, httpx.Conflict("booking_not_active", "only in-progress or confirmed bookings can be completed")
	}
	updated, err := s.store.CompleteStatus(ctx, b.ID, b.Status, pro.ID, &userID, "service completed")
	if err != nil {
		return nil, err
	}
	s.fire(s.hooks.OnCompleted, updated)
	return updated, nil
}

func (s *Service) Cancel(ctx context.Context, userID, bookingID, reason string) (*Booking, error) {
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	ok, err := s.isParticipant(ctx, userID, b)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, httpx.Forbidden("not_your_booking", "you are not part of this booking")
	}
	if b.Status == StatusCancelled || b.Status == StatusCompleted || b.Status == StatusNoShow {
		return nil, httpx.Conflict("cannot_cancel", "this booking can no longer be cancelled")
	}
	updated, err := s.store.UpdateStatus(ctx, b.ID, b.Status, StatusCancelled, &userID, reason)
	if err != nil {
		return nil, err
	}
	s.fire(s.hooks.OnCancelled, updated)
	return updated, nil
}

func (s *Service) Reschedule(ctx context.Context, userID, bookingID string, newStart time.Time) (*Booking, error) {
	b, err := s.store.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if b.CustomerID != userID {
		return nil, httpx.Forbidden("not_your_booking", "only the customer can reschedule a booking")
	}
	if b.Status != StatusPending && b.Status != StatusConfirmed {
		return nil, httpx.Conflict("cannot_reschedule", "this booking can no longer be rescheduled")
	}
	if newStart.IsZero() {
		return nil, httpx.BadRequest("start_at_required", "start_at is required")
	}
	if newStart.Before(time.Now().Add(-5 * time.Minute)) {
		return nil, httpx.BadRequest("start_at_past", "start_at cannot be in the past")
	}

	pro, err := s.proStore.GetByID(ctx, b.ProfessionalID)
	if err != nil {
		return nil, err
	}
	duration := int(b.EndAt.Sub(b.StartAt).Minutes())
	endAt := newStart.Add(time.Duration(duration) * time.Minute)

	checkStart, checkEnd := s.checkBounds(newStart, endAt, b.HomeService)
	ok, err := s.slotAvailable(ctx, pro, checkStart, checkEnd, b.ID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, httpx.Conflict("slot_unavailable", "the requested time is not available")
	}

	lockKey := fmt.Sprintf("booking:slot:%s:%d", pro.ID, newStart.Unix())
	acquired, err := s.acquireSlotLock(ctx, lockKey, userID)
	if err != nil {
		return nil, err
	}
	if !acquired {
		return nil, httpx.Conflict("slot_just_booked", "this slot was just booked by someone else")
	}
	defer s.releaseSlotLock(ctx, lockKey)

	updated, err := s.store.Reschedule(ctx, b.ID, newStart, endAt, &userID, b.Status)
	if err != nil {
		return nil, err
	}
	return updated, nil
}

func (s *Service) StatusEvents(ctx context.Context, userID, bookingID string) ([]*StatusEvent, error) {
	b, err := s.Get(ctx, userID, bookingID)
	if err != nil {
		return nil, err
	}
	return s.store.ListStatusEvents(ctx, b.ID)
}

type AvailableSlotsInput struct {
	ProfessionalID string
	Date           string
	Duration       int
	Step           int
}

func (s *Service) AvailableSlots(ctx context.Context, in AvailableSlotsInput) ([]Slot, error) {
	pro, err := s.proStore.GetByID(ctx, in.ProfessionalID)
	if err != nil {
		return nil, err
	}
	loc := locationFor(pro)
	// Parse the requested date in the professional's own timezone. Parsing it as
	// UTC then converting can land on the previous day for timezones west of UTC,
	// which would mis-match the weekday for recurring availability windows.
	date, err := time.ParseInLocation("2006-01-02", in.Date, loc)
	if err != nil {
		return nil, httpx.BadRequest("invalid_date", "date must be in YYYY-MM-DD format")
	}
	duration := in.Duration
	if duration <= 0 {
		duration = 60
	}
	step := in.Step
	if step <= 0 {
		step = 30
	}

	windows, err := s.effectiveWindows(ctx, pro.ID, date, loc)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	bufferMin := int(s.buffer.Minutes())
	var slots []Slot
	for _, w := range windows {
		for m := w.start; m+duration+bufferMin <= w.end; m += step {
			st := minutesToTime(date, m, loc)
			en := st.Add(time.Duration(duration) * time.Minute)
			if st.Before(now) {
				continue
			}
			overlaps, err := s.store.ListOverlapping(ctx, pro.ID, st, en.Add(s.buffer), "")
			if err != nil {
				return nil, err
			}
			if len(overlaps) > 0 {
				continue
			}
			slots = append(slots, Slot{Start: st, End: en})
		}
	}
	return slots, nil
}

type effWindow struct{ start, end int }

func (s *Service) effectiveWindows(ctx context.Context, proID string, date time.Time, loc *time.Location) ([]effWindow, error) {
	regWindows, err := s.availStore.ListWindows(ctx, proID, false)
	if err != nil {
		return nil, err
	}
	exceptions, err := s.availStore.ListExceptions(ctx, proID, date.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}

	dateStr := date.Format("2006-01-02")
	dayOfWeek := int(date.In(loc).Weekday())

	var effs []effWindow
	for _, w := range regWindows {
		if w.DayOfWeek == dayOfWeek {
			effs = append(effs, effWindow{start: w.StartMinutes, end: w.EndMinutes})
		}
	}

	for _, e := range exceptions {
		if e.Date != dateStr {
			continue
		}
		if !e.IsAvailable {
			bs, be := 0, 1440
			if e.StartMinutes != nil {
				bs = *e.StartMinutes
			}
			if e.EndMinutes != nil {
				be = *e.EndMinutes
			}
			effs = removeCovered(effs, bs, be)
		} else {
			es, ee := 0, 1440
			if e.StartMinutes != nil {
				es = *e.StartMinutes
			}
			if e.EndMinutes != nil {
				ee = *e.EndMinutes
			}
			effs = append(effs, effWindow{start: es, end: ee})
		}
	}
	sort.Slice(effs, func(i, j int) bool { return effs[i].start < effs[j].start })
	return effs, nil
}

func removeCovered(windows []effWindow, from, to int) []effWindow {
	out := windows[:0]
	for _, w := range windows {
		// keep window pieces not covered by [from,to]
		if to <= w.start || from >= w.end {
			out = append(out, w)
			continue
		}
		if w.start < from {
			out = append(out, effWindow{start: w.start, end: from})
		}
		if w.end > to {
			out = append(out, effWindow{start: to, end: w.end})
		}
	}
	return out
}

func (s *Service) slotAvailable(ctx context.Context, pro *professionals.Professional, start, end time.Time, excludeID string) (bool, error) {
	overlaps, err := s.store.ListOverlapping(ctx, pro.ID, start, end, excludeID)
	if err != nil {
		return false, err
	}
	if len(overlaps) > 0 {
		return false, nil
	}

	loc := locationFor(pro)
	windows, err := s.effectiveWindows(ctx, pro.ID, start.In(loc), loc)
	if err != nil {
		return false, err
	}
	slotStart := minutesOfDay(start.In(loc))
	slotEnd := minutesOfDay(end.In(loc))
	for _, w := range windows {
		if slotStart >= w.start && slotEnd <= w.end {
			return true, nil
		}
	}
	return false, nil
}

// checkBounds extends a booking's [start, end] with the configured post-service
// buffer and, for home-service bookings, the professional's travel time before arrival.
func (s *Service) checkBounds(start, end time.Time, homeService bool) (time.Time, time.Time) {
	if homeService {
		start = start.Add(-s.travelTime)
	}
	end = end.Add(s.buffer)
	return start, end
}

func (s *Service) isParticipant(ctx context.Context, userID string, b *Booking) (bool, error) {
	if b.CustomerID == userID {
		return true, nil
	}
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		if apiErr, ok := err.(*httpx.APIError); ok && apiErr.Code == "professional_not_found" {
			return false, nil
		}
		return false, err
	}
	return pro.ID == b.ProfessionalID, nil
}

func (s *Service) requireProfessional(ctx context.Context, userID string) (*professionals.Professional, error) {
	pro, err := s.proStore.GetByUserID(ctx, userID)
	if err != nil {
		return nil, httpx.Forbidden("professional_profile_required", "create a professional profile first")
	}
	return pro, nil
}

func locationFor(pro *professionals.Professional) *time.Location {
	if pro.Timezone != "" {
		if loc, err := time.LoadLocation(pro.Timezone); err == nil {
			return loc
		}
	}
	return time.UTC
}

func minutesOfDay(t time.Time) int {
	return t.Hour()*60 + t.Minute()
}

func minutesToTime(date time.Time, minutes int, loc *time.Location) time.Time {
	return time.Date(date.Year(), date.Month(), date.Day(), minutes/60, minutes%60, 0, 0, loc)
}

func roundMoney(v float64) float64 {
	return math.Round(v*100) / 100
}
