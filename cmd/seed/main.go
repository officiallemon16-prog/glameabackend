package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/database"
	"github.com/glamea/glamea-backend/pkg/logging"
	"github.com/glamea/glamea-backend/pkg/redis"
	"github.com/glamea/glamea-backend/pkg/seed"
)

func main() {
	logger := logging.New("development")
	cfg, err := config.Load()
	if err != nil {
		logger.Error("load config", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("connect database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	rdb, err := redis.Open(ctx, cfg.RedisURL)
	if err != nil {
		logger.Error("connect redis", "error", err)
		os.Exit(1)
	}
	defer rdb.Close()
	_ = rdb

	if err := seed.Categories(ctx, db, seed.DefaultCategories); err != nil {
		logger.Error("seed categories", "error", err)
		os.Exit(1)
	}

	if err := seed.DemoData(ctx, db); err != nil {
		logger.Error("seed demo data", "error", err)
		os.Exit(1)
	}

	if err := seed.Posts(ctx, db); err != nil {
		logger.Error("seed posts", "error", err)
		os.Exit(1)
	}

	logger.Info("seed complete")
}
