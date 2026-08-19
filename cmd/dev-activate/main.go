// Temporary dev helper: flips a professional's status to ACTIVE so a demo
// booking can be created. Usage: go run ./cmd/dev-activate <professional_id>
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/glamea/glamea-backend/pkg/config"
	"github.com/glamea/glamea-backend/pkg/database"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: dev-activate <professional_id>")
		os.Exit(2)
	}
	cfg, err := config.Load()
	if err != nil {
		panic(err)
	}
	db, err := database.Open(context.Background(), cfg.DatabaseURL)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	res, err := db.ExecContext(context.Background(),
		`UPDATE professionals SET status = 'ACTIVE' WHERE id = ?`, os.Args[1])
	if err != nil {
		panic(err)
	}
	n, _ := res.RowsAffected()
	fmt.Printf("activated %d professional(s)\n", n)
}
