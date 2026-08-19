package database

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
)

func Open(ctx context.Context, databaseURL string) (*sql.DB, error) {
	dsn, err := ToDSN(databaseURL)
	if err != nil {
		return nil, err
	}

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	db.SetMaxOpenConns(100)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(30 * time.Minute)

	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}

	return db, nil
}

func ToDSN(databaseURL string) (string, error) {
	if !strings.HasPrefix(databaseURL, "mysql://") {
		if _, err := mysql.ParseDSN(databaseURL); err == nil {
			return databaseURL, nil
		}
	}

	u, err := url.Parse(databaseURL)
	if err != nil {
		return "", fmt.Errorf("parse database url: %w", err)
	}

	password, _ := u.User.Password()
	user := u.User.Username()

	host := u.Host
	if u.Port() == "" {
		host += ":4000"
	}

	dbName := strings.TrimPrefix(u.Path, "/")
	if dbName == "" {
		dbName = "glamea"
	}

	cfg := mysql.NewConfig()
	cfg.User = user
	cfg.Passwd = password
	cfg.Net = "tcp"
	cfg.Addr = host
	cfg.DBName = dbName
	cfg.ParseTime = true
	cfg.MultiStatements = true
	cfg.Loc = time.UTC

	params := u.Query()
	cfg.Params = map[string]string{}
	for k, v := range params {
		if k == "tls" {
			cfg.TLSConfig = v[0]
			continue
		}
		cfg.Params[k] = v[0]
	}
	if len(params) == 0 {
		cfg.Params = nil
	}

	return cfg.FormatDSN(), nil
}
