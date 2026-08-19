package database

import (
	"context"
	"database/sql"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"

	glameamigrations "github.com/glamea/glamea-backend/migrations"
)

type Migration struct {
	Version int64
	Name    string
	UpSQL   string
	DownSQL string
}

func LoadMigrations() ([]Migration, error) {
	entries, err := fs.ReadDir(glameamigrations.FS, ".")
	if err != nil {
		return nil, fmt.Errorf("read migrations dir: %w", err)
	}

	byVersion := map[int64]Migration{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		parts := strings.SplitN(e.Name(), "_", 2)
		if len(parts) != 2 {
			continue
		}
		version, err := strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			continue
		}
		content, err := glameamigrations.FS.ReadFile(e.Name())
		if err != nil {
			return nil, fmt.Errorf("read migration %s: %w", e.Name(), err)
		}
		name := strings.TrimSuffix(parts[1], ".sql")

		m := byVersion[version]
		m.Version = version
		m.Name = name
		if strings.HasSuffix(name, ".up") {
			m.Name = strings.TrimSuffix(name, ".up")
			m.UpSQL = string(content)
		}
		if strings.HasSuffix(name, ".down") {
			m.Name = strings.TrimSuffix(name, ".down")
			m.DownSQL = string(content)
		}
		byVersion[version] = m
	}

	migs := make([]Migration, 0, len(byVersion))
	for _, m := range byVersion {
		migs = append(migs, m)
	}
	sort.Slice(migs, func(i, j int) bool { return migs[i].Version < migs[j].Version })
	return migs, nil
}

func ensureSchemaMigrationsTable(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version BIGINT PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`)
	return err
}

func appliedVersions(ctx context.Context, db *sql.DB) (map[int64]bool, error) {
	rows, err := db.QueryContext(ctx, `SELECT version FROM schema_migrations`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	applied := map[int64]bool{}
	for rows.Next() {
		var v int64
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		applied[v] = true
	}
	return applied, rows.Err()
}

func MigrateUp(ctx context.Context, db *sql.DB) error {
	if err := ensureSchemaMigrationsTable(ctx, db); err != nil {
		return fmt.Errorf("ensure migrations table: %w", err)
	}

	migs, err := LoadMigrations()
	if err != nil {
		return err
	}

	applied, err := appliedVersions(ctx, db)
	if err != nil {
		return err
	}

	for _, m := range migs {
		if applied[m.Version] {
			continue
		}
		if m.UpSQL == "" {
			return fmt.Errorf("migration %d has no up sql", m.Version)
		}
		if err := applyMigration(ctx, db, m); err != nil {
			return fmt.Errorf("apply migration %d (%s): %w", m.Version, m.Name, err)
		}
	}
	return nil
}

// MigrateDown rolls back the most recent `steps` applied migrations.
// steps <= 0 rolls back all applied migrations.
func MigrateDown(ctx context.Context, db *sql.DB, steps int) error {
	if err := ensureSchemaMigrationsTable(ctx, db); err != nil {
		return fmt.Errorf("ensure migrations table: %w", err)
	}

	migs, err := LoadMigrations()
	if err != nil {
		return err
	}

	applied, err := appliedVersions(ctx, db)
	if err != nil {
		return err
	}

	var appliedOrder []Migration
	for _, m := range migs {
		if applied[m.Version] {
			appliedOrder = append(appliedOrder, m)
		}
	}
	for i, j := 0, len(appliedOrder)-1; i < j; i, j = i+1, j-1 {
		appliedOrder[i], appliedOrder[j] = appliedOrder[j], appliedOrder[i]
	}

	if steps <= 0 || steps > len(appliedOrder) {
		steps = len(appliedOrder)
	}
	if steps == 0 {
		return nil
	}

	for _, m := range appliedOrder[:steps] {
		if err := rollbackMigration(ctx, db, m); err != nil {
			return fmt.Errorf("rollback migration %d (%s): %w", m.Version, m.Name, err)
		}
	}
	return nil
}

func rollbackMigration(ctx context.Context, db *sql.DB, m Migration) error {
	if m.DownSQL == "" {
		return fmt.Errorf("migration %d has no down sql", m.Version)
	}
	// DDL is non-transactional on MySQL/TiDB; execute directly.
	if _, err := db.ExecContext(ctx, m.DownSQL); err != nil {
		return err
	}
	_, err := db.ExecContext(ctx, `DELETE FROM schema_migrations WHERE version = ?`, m.Version)
	return err
}

func MigrationStatus(ctx context.Context, db *sql.DB) ([]MigrationStatusRow, error) {
	if err := ensureSchemaMigrationsTable(ctx, db); err != nil {
		return nil, err
	}
	migs, err := LoadMigrations()
	if err != nil {
		return nil, err
	}
	applied, err := appliedVersions(ctx, db)
	if err != nil {
		return nil, err
	}

	rows := make([]MigrationStatusRow, 0, len(migs))
	for _, m := range migs {
		rows = append(rows, MigrationStatusRow{
			Version: m.Version,
			Name:    m.Name,
			Applied: applied[m.Version],
		})
	}
	return rows, nil
}

type MigrationStatusRow struct {
	Version int64
	Name    string
	Applied bool
}

func applyMigration(ctx context.Context, db *sql.DB, m Migration) error {
	// DDL is non-transactional on MySQL/TiDB (it auto-commits), and running
	// it inside an explicit transaction breaks multi-column ALTERs that use
	// AFTER to reference columns added in the same statement. Execute directly.
	if _, err := db.ExecContext(ctx, m.UpSQL); err != nil {
		return err
	}
	_, err := db.ExecContext(ctx, `INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)`,
		m.Version, m.Name, time.Now().UTC())
	return err
}
