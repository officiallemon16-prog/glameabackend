package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/glamea/glamea-backend/internal/auth"
	"github.com/glamea/glamea-backend/internal/users"
	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/database"
)

func main() {
	ctx := context.Background()

	email := getenv("ADMIN_EMAIL", "admin@glamea.com")
	password := getenv("ADMIN_PASSWORD", "Admin@12345")
	firstName := getenv("ADMIN_FIRST", "Glamea")
	lastName := getenv("ADMIN_LAST", "Admin")

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal("open db: ", err)
	}
	defer db.Close()

	userStore := users.NewStore(db)

	existing, err := userStore.GetByEmail(ctx, email)
	if err == nil {
		hash, err := auth.HashPassword(password)
		if err != nil {
			log.Fatal("hash: ", err)
		}
		if err := userStore.SetPasswordHash(ctx, existing.ID, hash); err != nil {
			log.Fatal("update password: ", err)
		}
		if err := userStore.SetRole(ctx, existing.ID, users.RoleAdmin); err != nil {
			log.Fatal("update role: ", err)
		}
		if err := userStore.SetStatus(ctx, existing.ID, users.StatusActive); err != nil {
			log.Fatal("update status: ", err)
		}
		fmt.Printf("updated admin %s (role=ADMIN)\n", existing.ID)
		return
	}

	hash, err := auth.HashPassword(password)
	if err != nil {
		log.Fatal("hash: ", err)
	}

	u := &users.User{
		Email:     &email,
		FirstName: firstName,
		LastName:  lastName,
		Role:      users.RoleAdmin,
		Status:    users.StatusActive,
	}
	created, err := userStore.Create(ctx, u, hash)
	if err != nil {
		log.Fatal("create: ", err)
	}
	fmt.Printf("created admin %s\n", created.ID)
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
