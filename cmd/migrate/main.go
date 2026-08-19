package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/database"
	"github.com/glamea/glamea-backend/pkg/logging"
)

func main() {
	action := flag.String("action", "up", "migration action: up, down, status")
	steps := flag.Int("steps", 0, "number of migrations to roll back (down only, 0 = all)")
	flag.Parse()

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

	switch *action {
	case "up":
		if err := database.MigrateUp(ctx, db); err != nil {
			logger.Error("migrate up", "error", err)
			os.Exit(1)
		}
		fmt.Println("all migrations applied")
	case "down":
		if err := database.MigrateDown(ctx, db, *steps); err != nil {
			logger.Error("migrate down", "error", err)
			os.Exit(1)
		}
		if *steps > 0 {
			fmt.Printf("rolled back %d migration(s)\n", *steps)
		} else {
			fmt.Println("all migrations rolled back")
		}
	case "status":
		rows, err := database.MigrationStatus(ctx, db)
		if err != nil {
			logger.Error("migration status", "error", err)
			os.Exit(1)
		}
		for _, row := range rows {
			status := "pending"
			if row.Applied {
				status = "applied"
			}
			fmt.Printf("%04d  %-40s  %s\n", row.Version, row.Name, status)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown action %q\n", *action)
		os.Exit(1)
	}
}
