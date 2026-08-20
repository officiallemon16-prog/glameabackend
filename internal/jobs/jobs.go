package jobs

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/glamea/glamea-backend/internal/bookings"
	"github.com/glamea/glamea-backend/internal/notifications"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/email"
)

// Scheduler runs periodic background jobs. It is safe to start from main and is
// stopped by cancelling the context passed to Run.
type Scheduler struct {
	store        *Store
	bookingStore *bookings.Store
	notifier     *notifications.Service
	cfg          *config.Config
	logger       *slog.Logger
	emailer      email.Emailer
	userStore    *users.Store
}

func New(store *Store, bookingStore *bookings.Store, notifier *notifications.Service, cfg *config.Config, logger *slog.Logger) *Scheduler {
	return &Scheduler{store: store, bookingStore: bookingStore, notifier: notifier, cfg: cfg, logger: logger}
}

// SetEmailer wires the transactional email sender for reminder/review emails.
func (s *Scheduler) SetEmailer(e email.Emailer) {
	s.emailer = e
}

// SetUserStore wires the user store used to resolve email addresses.
func (s *Scheduler) SetUserStore(u *users.Store) {
	s.userStore = u
}

// Run executes all jobs immediately, then on every configured interval until ctx
// is cancelled.
func (s *Scheduler) Run(ctx context.Context) error {
	s.runAll(ctx)
	ticker := time.NewTicker(s.cfg.JobInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			s.runAll(ctx)
		}
	}
}

func (s *Scheduler) runAll(ctx context.Context) {
	s.runJob(ctx, "expire_stale_pending", s.ExpireStalePending)
	s.runJob(ctx, "booking_reminders", s.SendBookingReminders)
	s.runJob(ctx, "review_reminders", s.SendReviewReminders)
	s.runJob(ctx, "unread_nudges", s.SendUnreadNudges)
	s.runJob(ctx, "pending_expiry_nudges", s.SendPendingExpiryNudges)
	s.runJob(ctx, "inactive_nudges", s.SendInactiveNudges)
	s.runJob(ctx, "favorites_digest", s.SendFavoritesDigest)
}

func (s *Scheduler) runJob(ctx context.Context, name string, fn func(ctx context.Context) error) {
	defer func() {
		if rec := recover(); rec != nil {
			s.logger.Error("job panicked", "job", name, "panic", rec)
		}
	}()
	start := time.Now()
	if err := fn(ctx); err != nil {
		s.logger.Error("job failed", "job", name, "error", err)
		return
	}
	s.logger.Debug("job finished", "job", name, "duration_ms", time.Since(start).Milliseconds())
}

// ExpireStalePending auto-cancels PENDING booking requests that were never
// confirmed within the configured expiry window.
func (s *Scheduler) ExpireStalePending(ctx context.Context) error {
	stale, err := s.store.ListStalePending(ctx, int(s.cfg.PendingBookingExpiry.Minutes()))
	if err != nil {
		return err
	}
	for _, b := range stale {
		by := "system"
		updated, err := s.bookingStore.UpdateStatus(ctx, b.ID, bookings.StatusPending, bookings.StatusCancelled, &by, "auto-cancelled: booking request expired")
		if err != nil {
			s.logger.Warn("expire stale pending failed", "booking_id", b.ID, "error", err)
			continue
		}
		_ = s.notifier.Notify(ctx, updated.CustomerID, "booking", "Booking request expired",
			"Your booking request was cancelled because it was not confirmed in time.",
			map[string]any{"booking_id": updated.ID})
	}
	return nil
}

// SendBookingReminders notifies both parties once per booking before the start time.
func (s *Scheduler) SendBookingReminders(ctx context.Context) error {
	upcoming, err := s.store.ListConfirmedUpcoming(ctx, int(s.cfg.ReminderBeforeStart.Minutes()))
	if err != nil {
		return err
	}
	for _, b := range upcoming {
		inserted, err := s.store.InsertReminder(ctx, b.ID, "pre_start")
		if err != nil {
			s.logger.Warn("booking reminder insert failed", "booking_id", b.ID, "error", err)
			continue
		}
		if !inserted {
			continue
		}
		when := b.StartAt.Format("Mon 2 Jan 15:04")
		if b.CustomerID != "" {
			_ = s.notifier.Notify(ctx, b.CustomerID, "booking", "Upcoming appointment",
				"Reminder: your appointment is scheduled for "+when+".", map[string]any{"booking_id": b.ID})
		}
		if b.ProUserID != "" {
			_ = s.notifier.Notify(ctx, b.ProUserID, "booking", "Upcoming appointment",
				"Reminder: you have an appointment at "+when+".", map[string]any{"booking_id": b.ID})
		}
		if s.emailer != nil && s.userStore != nil && b.CustomerID != "" {
			if full, err := s.bookingStore.GetByID(ctx, b.ID); err == nil {
				if c, err := s.userStore.GetByID(ctx, b.CustomerID); err == nil && c.Email != nil && *c.Email != "" {
					if e := s.emailer.SendBookingReminder(*c.Email, c.FirstName, when, full.ProfessionalName, full.ServiceName); e != nil {
						s.logger.Error("booking reminder email failed", "email", *c.Email, "error", e)
					}
				}
				if p, err := s.userStore.GetByID(ctx, b.ProUserID); err == nil && p.Email != nil && *p.Email != "" {
					if e := s.emailer.SendBookingReminder(*p.Email, p.FirstName, when, full.CustomerName, full.ServiceName); e != nil {
						s.logger.Error("pro booking reminder email failed", "email", *p.Email, "error", e)
					}
				}
			}
		}
	}
	return nil
}

// SendReviewReminders prompts customers once to review completed bookings.
func (s *Scheduler) SendReviewReminders(ctx context.Context) error {
	old, err := s.store.ListCompletedWithoutReview(ctx, int(s.cfg.ReviewReminderAfter.Minutes()))
	if err != nil {
		return err
	}
	for _, b := range old {
		inserted, err := s.store.InsertReminder(ctx, b.ID, "review")
		if err != nil {
			s.logger.Warn("review reminder insert failed", "booking_id", b.ID, "error", err)
			continue
		}
		if !inserted || b.CustomerID == "" {
			continue
		}
		_ = s.notifier.Notify(ctx, b.CustomerID, "review", "How was your appointment?",
			"You haven't reviewed your recent appointment yet. Your feedback helps others.",
			map[string]any{"booking_id": b.ID})
		if s.emailer != nil && s.userStore != nil {
			if full, err := s.bookingStore.GetByID(ctx, b.ID); err == nil {
				if c, err := s.userStore.GetByID(ctx, b.CustomerID); err == nil && c.Email != nil && *c.Email != "" {
					if e := s.emailer.SendReviewRequest(*c.Email, c.FirstName, full.ProfessionalName, full.ServiceName); e != nil {
						s.logger.Error("review email failed", "email", *c.Email, "error", e)
					}
				}
			}
		}
	}
	return nil
}

// SendUnreadNudges re-engages users who left messages unread for a while. One
// nudge per user, capped by UnreadNudgeCooldown.
func (s *Scheduler) SendUnreadNudges(ctx context.Context) error {
	convos, err := s.store.ListUnreadConvos(ctx, int(s.cfg.UnreadNudgeAfter.Minutes()))
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, c := range convos {
		if seen[c.UserID] {
			continue
		}
		seen[c.UserID] = true

		ok, err := s.store.ClaimSend(ctx, c.UserID, "unread", s.cfg.UnreadNudgeCooldown)
		if err != nil {
			s.logger.Warn("unread nudge claim failed", "user_id", c.UserID, "error", err)
			continue
		}
		if !ok {
			continue
		}

		body := "You have unread messages waiting."
		if c.SenderName.Valid && c.SenderName.String != "" {
			body = "You have unread messages from " + c.SenderName.String + "."
		}
		_ = s.notifier.Notify(ctx, c.UserID, "message", "You have unread messages", body,
			map[string]any{"booking_id": c.BookingID})
	}
	return nil
}

// SendPendingExpiryNudges reminds professionals to confirm a pending booking
// request before its window expires. Capped by PendingExpiryNudgeCooldown.
func (s *Scheduler) SendPendingExpiryNudges(ctx context.Context) error {
	expiring, err := s.store.ListPendingExpiring(ctx,
		int(s.cfg.PendingBookingExpiry.Minutes()), int(s.cfg.PendingExpiryNudgeBefore.Minutes()))
	if err != nil {
		return err
	}
	for _, b := range expiring {
		if b.ProUserID == "" {
			continue
		}
		ok, err := s.store.ClaimSend(ctx, b.ProUserID, "pending_expiry", s.cfg.PendingExpiryNudgeCooldown)
		if err != nil {
			s.logger.Warn("pending expiry claim failed", "booking_id", b.ID, "error", err)
			continue
		}
		if !ok {
			continue
		}
		_ = s.notifier.Notify(ctx, b.ProUserID, "booking", "A booking request is waiting",
			"You have a booking request awaiting your confirmation. Confirm it before it expires.",
			map[string]any{"booking_id": b.ID})
	}
	return nil
}

// SendInactiveNudges reaches out to users who have not visited in a while,
// picking the most compelling reason per user: a pending booking, then unread
// messages, then new content from favorites, then a generic discover nudge.
// Capped by InactiveNudgeCooldown.
func (s *Scheduler) SendInactiveNudges(ctx context.Context) error {
	users, err := s.store.ListInactiveUsers(ctx, int(s.cfg.InactiveNudgeAfter.Hours()))
	if err != nil {
		return err
	}
	for _, uid := range users {
		ok, err := s.store.ClaimSend(ctx, uid, "inactive", s.cfg.InactiveNudgeCooldown)
		if err != nil {
			s.logger.Warn("inactive claim failed", "user_id", uid, "error", err)
			continue
		}
		if !ok {
			continue
		}

		pb, err := s.store.ListPendingForUser(ctx, uid)
		if err != nil {
			s.logger.Warn("inactive pending lookup failed", "user_id", uid, "error", err)
			continue
		}
		if pb != nil {
			_ = s.notifier.Notify(ctx, uid, "booking", "Your booking request is still pending",
				"We're still waiting on "+pb.BusinessName+" to confirm. Tap to check the status.",
				map[string]any{"booking_id": pb.ID})
			continue
		}

		if n, err := s.store.UnreadCountForUser(ctx, uid); err == nil && n > 0 {
			_ = s.notifier.Notify(ctx, uid, "message", "You have unread messages",
				"Some professionals are waiting to hear from you.",
				map[string]any{})
			continue
		}

		if n, err := s.store.NewContentCountForUser(ctx, uid, int(s.cfg.DigestNewContentWindow.Hours())); err == nil && n > 0 {
			_ = s.notifier.Notify(ctx, uid, "digest", "New looks from artists you love",
				fmt.Sprintf("There are %d new looks on GLAMEA waiting for you.", n),
				map[string]any{})
			continue
		}

		_ = s.notifier.Notify(ctx, uid, "digest", "Fresh inspiration is waiting",
			"Discover new beauty professionals and styles near you.",
			map[string]any{})
	}
	return nil
}

// SendFavoritesDigest sends a weekly-ish digest to users who follow (liked/saved)
// posts, but only when their favorites posted something new in the window.
// Capped by DigestInterval.
func (s *Scheduler) SendFavoritesDigest(ctx context.Context) error {
	users, err := s.store.ListDigestUsers(ctx)
	if err != nil {
		return err
	}
	within := int(s.cfg.DigestNewContentWindow.Hours())
	for _, uid := range users {
		ok, err := s.store.ClaimSend(ctx, uid, "digest", s.cfg.DigestInterval)
		if err != nil {
			s.logger.Warn("digest claim failed", "user_id", uid, "error", err)
			continue
		}
		if !ok {
			continue
		}
		n, err := s.store.NewContentCountForUser(ctx, uid, within)
		if err != nil {
			s.logger.Warn("digest count failed", "user_id", uid, "error", err)
			continue
		}
		if n == 0 {
			continue
		}
		_ = s.notifier.Notify(ctx, uid, "digest", "New looks from artists you love",
			fmt.Sprintf("Your favorites posted %d new look%s this week.", n, plural(n)),
			map[string]any{})
	}
	return nil
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}
