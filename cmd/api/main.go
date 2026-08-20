package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/glamea/glamea-backend/internal/admin"
	"github.com/glamea/glamea-backend/internal/analytics"
	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/availability"
	"github.com/glamea/glamea-backend/internal/bookings"
	"github.com/glamea/glamea-backend/internal/categories"
	"github.com/glamea/glamea-backend/internal/deals"
	"github.com/glamea/glamea-backend/internal/discovery"
	"github.com/glamea/glamea-backend/internal/disputes"
	"github.com/glamea/glamea-backend/internal/jobs"
	"github.com/glamea/glamea-backend/internal/media"
	"github.com/glamea/glamea-backend/internal/messaging"
	"github.com/glamea/glamea-backend/internal/notifications"
	"github.com/glamea/glamea-backend/internal/payments"
	"github.com/glamea/glamea-backend/internal/payouts"
	"github.com/glamea/glamea-backend/internal/platform"
	"github.com/glamea/glamea-backend/internal/portfolio"
	"github.com/glamea/glamea-backend/internal/posts"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/reports"
	"github.com/glamea/glamea-backend/internal/reviews"
	"github.com/glamea/glamea-backend/internal/services"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/internal/verification"
	cloudinarypkg "github.com/glamea/glamea-backend/pkg/cloudinary"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/database"
	"github.com/glamea/glamea-backend/pkg/email"
	fcmpkg "github.com/glamea/glamea-backend/pkg/fcm"
	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/glamea/glamea-backend/pkg/logging"
	"github.com/glamea/glamea-backend/pkg/redis"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	goredis "github.com/redis/go-redis/v9"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config", "error", err)
		os.Exit(1)
	}

	logger := logging.New(cfg.Env)
	ctx = logging.With(ctx, logger)

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("connect database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	var rdb *goredis.Client
	rdb, err = redis.Open(ctx, cfg.RedisURL)
	if err != nil {
		logger.Warn("redis unavailable, continuing without cache: " + err.Error())
		rdb = nil
	}
	if rdb != nil {
		defer rdb.Close()
	}

	if err := database.MigrateUp(ctx, db); err != nil {
		logger.Error("run migrations", "error", err)
		os.Exit(1)
	}
	logger.Info("migrations applied")

	userStore := users.NewStore(db)
	sessionStore := auth.NewSessionStore(db)
	tokenManager := auth.NewTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	authService := auth.NewService(userStore, sessionStore, rdb, tokenManager, cfg, logger)
	if cfg.ResendAPIKey != "" {
		resendSender := email.NewResendSender(cfg.ResendAPIKey, cfg.EmailFrom)
		authService.SetEmailDelivery(func(ctx context.Context, to, code string) error {
			return resendSender.SendOTP(to, code)
		})
		logger.Info("Resend email sender configured")
	} else {
		logger.Warn("RESEND_API_KEY not set, email verification codes will only be logged")
	}
	authHandler := auth.NewHandler(authService, cfg.AuthRateLimitPerMinute)
	authMiddleware := auth.AuthMiddleware(userStore, tokenManager)
	optionalAuthMiddleware := auth.OptionalAuthMiddleware(userStore, tokenManager)

	userService := users.NewService(userStore)
	userHandler := users.NewHandler(userService, authMiddleware)

	professionalStore := professionals.NewStore(db)
	professionalService := professionals.NewService(professionalStore, userStore)
	professionalHandler := professionals.NewHandler(professionalService, authMiddleware)

	categoryStore := categories.NewStore(db)
	categoryService := categories.NewService(categoryStore)
	categoryHandler := categories.NewHandler(categoryService, authMiddleware)

	serviceStore := services.NewStore(db)
	serviceService := services.NewService(serviceStore, professionalStore)
	serviceHandler := services.NewHandler(serviceService, authMiddleware)

	var cloudinaryClient *cloudinarypkg.Client
	if cfg.CloudinaryCloudName != "" {
		cloudinaryClient, err = cloudinarypkg.New(cloudinarypkg.Config{
			CloudName:    cfg.CloudinaryCloudName,
			APIKey:       cfg.CloudinaryAPIKey,
			APISecret:    cfg.CloudinaryAPISecret,
			UploadFolder: cfg.CloudinaryUploadFolder,
		})
		if err != nil {
			logger.Error("init cloudinary", "error", err)
			os.Exit(1)
		}
	} else {
		logger.Warn("Cloudinary not configured, uploads will be stored locally in " + cfg.LocalMediaDir)
		cloudinaryClient, _ = cloudinarypkg.New(cloudinarypkg.Config{})
	}

	mediaStore := media.NewStore(db)
	mediaService := media.NewService(mediaStore, cloudinaryClient, media.Options{
		UploadDir: cfg.LocalMediaDir,
		AppURL:    cfg.AppURL,
		MaxBytes:  cfg.MaxRequestBodyBytes,
	})
	mediaHandler := media.NewHandler(mediaService, authMiddleware)

	portfolioStore := portfolio.NewStore(db)
	portfolioService := portfolio.NewService(portfolioStore, professionalStore, mediaService)
	portfolioHandler := portfolio.NewHandler(portfolioService, authMiddleware)

	auditStore := admin.NewAuditStore(db)
	verificationStore := verification.NewStore(db)
	verificationService := verification.NewService(verificationStore, professionalStore, auditStore)
	verificationHandler := verification.NewHandler(verificationService, authMiddleware)

	availabilityStore := availability.NewStore(db)
	availabilityService := availability.NewService(availabilityStore, professionalStore)
	availabilityHandler := availability.NewHandler(availabilityService, authMiddleware)

	bookingStore := bookings.NewStore(db)
	bookingService := bookings.NewService(bookingStore, professionalStore, serviceStore, availabilityStore, rdb,
		cfg.BookingSlotLockTTL, bookings.Options{Buffer: cfg.BookingBuffer, TravelTime: cfg.TravelTime})
	bookingHandler := bookings.NewHandler(bookingService, authMiddleware)

	notificationStore := notifications.NewStore(db)
	var notificationPusher notifications.Pusher
	if cfg.FCMProjectID != "" && cfg.FCMServiceAccountFile != "" {
		fcmClient, err := fcmpkg.New(fcmpkg.Config{
			ProjectID:         cfg.FCMProjectID,
			ServiceAccountFile: cfg.FCMServiceAccountFile,
		})
		if err != nil {
			logger.Error("init fcm", "error", err)
			os.Exit(1)
		}
		notificationPusher = fcmClient
	} else {
		logger.Warn("FCM not configured, push notifications disabled")
	}
	notificationService := notifications.NewService(notificationStore, notificationPusher)
	notificationHandler := notifications.NewHandler(notificationService, authMiddleware)

	paymentStore := payments.NewStore(db)
	paymentService := payments.NewService(paymentStore, bookingStore, userStore, professionalStore, notificationService, cfg)
	paymentHandler := payments.NewHandler(paymentService, authMiddleware, cfg.WebhookRateLimitPerMin)

	payoutStore := payouts.NewStore(db)
	payoutService := payouts.NewService(payoutStore, professionalStore, paymentStore, cfg)
	payoutHandler := payouts.NewHandler(payoutService, authMiddleware)

	reviewStore := reviews.NewStore(db)
	reviewService := reviews.NewService(reviewStore, bookingStore, professionalStore, notificationService)
	reviewHandler := reviews.NewHandler(reviewService, authMiddleware)

	messagingStore := messaging.NewStore(db)
	messagingService := messaging.NewService(messagingStore, bookingStore, professionalStore, notificationService)
	messagingHub := messaging.NewHub(logger)
	messagingHub.SetNotifyFn(func(ctx context.Context, userID, title, body string, data map[string]string) {
		_ = notificationService.Notify(ctx, userID, data["notification_type"], title, body, data)
	})
	messagingService.SetHub(messagingHub)
	messagingHandler := messaging.NewHandler(messagingService, authMiddleware, messagingHub, userStore, tokenManager,
		cfg.TurnURL, cfg.TurnUsername, cfg.TurnCredential)

	disputeStore := disputes.NewStore(db)
	disputeService := disputes.NewService(disputeStore, bookingStore, professionalStore, notificationService)
	disputeHandler := disputes.NewHandler(disputeService, authMiddleware)

	dealStore := deals.NewStore(db)
	dealService := deals.NewService(dealStore, professionalStore)
	dealHandler := deals.NewHandler(dealService, authMiddleware)

	discoveryService := discovery.NewService(professionalStore, serviceStore, categoryStore, dealStore)
	discoveryHandler := discovery.NewHandler(discoveryService)

	postStore := posts.NewStore(db)
	postService := posts.NewService(postStore, professionalStore, categoryStore, mediaService)
	postHandler := posts.NewHandler(postService, authMiddleware, optionalAuthMiddleware)

	adminStore := admin.NewStore(db)
	adminService := admin.NewService(adminStore, auditStore, userStore, professionalStore)
	adminHandler := admin.NewHandler(adminService, authMiddleware)

	analyticsStore := analytics.NewStore(db)
	analyticsService := analytics.NewService(analyticsStore)
	analyticsHandler := analytics.NewHandler(analyticsService, authMiddleware)

	reportsStore := reports.NewStore(db)
	reportsService := reports.NewService(reportsStore)
	reportsHandler := reports.NewHandler(reportsService, authMiddleware)

	platformStore := platform.NewStore(db)
	platformService := platform.NewService(platformStore)
	platformHandler := platform.NewHandler(platformService, authMiddleware)

	bookingService.SetHooks(&bookings.Hooks{
		OnCreated: func(ctx context.Context, b *bookings.Booking) error {
			pro, err := professionalStore.GetByID(ctx, b.ProfessionalID)
			if err != nil {
				return err
			}
			return notificationService.Notify(ctx, pro.UserID, "booking", "New booking request",
				"A customer has requested a booking with you.", map[string]any{"booking_id": b.ID})
		},
		OnConfirmed: func(ctx context.Context, b *bookings.Booking) error {
			return notificationService.Notify(ctx, b.CustomerID, "booking", "Booking confirmed",
				"Your booking has been confirmed.", map[string]any{"booking_id": b.ID})
		},
		OnStarted: func(ctx context.Context, b *bookings.Booking) error {
			return notificationService.Notify(ctx, b.CustomerID, "booking", "Booking started",
				"Your professional has started the service.", map[string]any{"booking_id": b.ID})
		},
		OnCompleted: func(ctx context.Context, b *bookings.Booking) error {
			if err := notificationService.Notify(ctx, b.CustomerID, "booking", "Booking completed",
				"Your booking has been completed. Please leave a review.", map[string]any{"booking_id": b.ID}); err != nil {
				return err
			}
			return paymentService.SettleBooking(ctx, b)
		},
		OnCancelled: func(ctx context.Context, b *bookings.Booking) error {
			if b.CustomerID == "" {
				return nil
			}
			return notificationService.Notify(ctx, b.CustomerID, "booking", "Booking cancelled",
				"Your booking has been cancelled.", map[string]any{"booking_id": b.ID})
		},
	})

	router := chi.NewRouter()
	router.Use(middleware.RealIP)
	router.Use(middleware.RequestID)
	router.Use(httpx.RequestIDMiddleware)
	router.Use(httpx.RecoverMiddleware(logger))
	router.Use(httpx.LoggingMiddleware(logger))
	router.Use(httpx.RateLimitMiddleware(cfg.RateLimitPerMinute))
	router.Use(cors.Handler(cors.Options{
		AllowedOrigins:   cfg.CORSAllowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "Idempotency-Key", "X-Paystack-Signature", "Verif-Hash"},
		ExposedHeaders:   []string{"X-Request-ID"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	router.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]any{"status": "ok", "service": cfg.Name, "time": time.Now().UTC()})
	})
	router.Get("/ready", func(w http.ResponseWriter, r *http.Request) {
		dbErr := db.PingContext(r.Context())
		checks := map[string]string{"database": "ok", "redis": "ok"}
		if dbErr != nil {
			checks["database"] = "error"
		}
		if rdb != nil {
			if err := rdb.Ping(r.Context()).Err(); err != nil {
				checks["redis"] = "error"
			}
		} else {
			checks["redis"] = "disabled"
		}
		if dbErr != nil {
			httpx.JSON(w, http.StatusServiceUnavailable, map[string]any{"status": "error", "checks": checks})
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"status": "ok", "checks": checks})
	})

	authHandler.RegisterRoutes(router)
	userHandler.RegisterRoutes(router)
	categoryHandler.RegisterRoutes(router)
	professionalHandler.RegisterRoutes(router)
	serviceHandler.RegisterRoutes(router)
	mediaHandler.RegisterRoutes(router)
	if cfg.LocalMediaDir != "" {
		if err := os.MkdirAll(cfg.LocalMediaDir, 0o755); err != nil {
			logger.Error("create uploads directory", "error", err)
			os.Exit(1)
		}
		router.Handle("/uploads/*", http.StripPrefix("/uploads/", http.FileServer(http.Dir(cfg.LocalMediaDir))))
	}
	portfolioHandler.RegisterRoutes(router)
	verificationHandler.RegisterRoutes(router)
	availabilityHandler.RegisterRoutes(router)
	bookingHandler.RegisterRoutes(router)
	notificationHandler.RegisterRoutes(router)
	paymentHandler.RegisterRoutes(router)
	payoutHandler.RegisterRoutes(router)
	reviewHandler.RegisterRoutes(router)
	messagingHandler.RegisterRoutes(router)
	disputeHandler.RegisterRoutes(router)
	dealHandler.RegisterRoutes(router)
	postHandler.RegisterRoutes(router)
	discoveryHandler.RegisterRoutes(router)
	adminHandler.RegisterRoutes(router)
	analyticsHandler.RegisterRoutes(router)
	reportsHandler.RegisterRoutes(router)
	platformHandler.RegisterRoutes(router)

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	jobScheduler := jobs.New(jobs.NewStore(db), bookingStore, notificationService, cfg, logger)
	jobCtx, stopJobs := context.WithCancel(ctx)
	var jobsWG sync.WaitGroup
	jobsWG.Add(1)
	go func() {
		defer jobsWG.Done()
		if err := jobScheduler.Run(jobCtx); err != nil {
			logger.Warn("jobs scheduler stopped", "error", err)
		}
	}()
	logger.Info("jobs scheduler started", "interval", cfg.JobInterval.String())

	go func() {
		logger.Info("http server listening", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server error", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
	}
	stopJobs()
	jobsWG.Wait()
	messagingHub.Close()
	logger.Info("server stopped")
}
