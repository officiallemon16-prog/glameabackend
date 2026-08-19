package redis

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

func Open(ctx context.Context, redisURL string) (*redis.Client, error) {
	opts, err := ParseURL(redisURL)
	if err != nil {
		return nil, err
	}

	client := redis.NewClient(opts)
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx).Err(); err != nil {
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return client, nil
}

func ParseURL(raw string) (*redis.Options, error) {
	if !strings.HasPrefix(raw, "redis://") && !strings.HasPrefix(raw, "rediss://") {
		return nil, fmt.Errorf("invalid redis url (must be redis://): %s", raw)
	}

	u, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("parse redis url: %w", err)
	}

	password := ""
	if u.User != nil {
		password, _ = u.User.Password()
	}

	db := 0
	if len(u.Path) > 1 {
		db, err = strconv.Atoi(strings.TrimPrefix(u.Path, "/"))
		if err != nil {
			return nil, fmt.Errorf("parse redis db: %w", err)
		}
	}

	addr := u.Host
	if u.Port() == "" {
		addr += ":6379"
	}

	opts := &redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	}
	if strings.HasPrefix(raw, "rediss://") {
		opts.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}

	return opts, nil
}
