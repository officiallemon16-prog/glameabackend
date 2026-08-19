.PHONY: dev test lint migrate migrate-status seed generate build down smoke

dev:
	go run ./cmd/api

build:
	go build -o bin/api ./cmd/api

test:
	go test ./...

lint:
	golangci-lint run ./...

migrate:
	go run ./cmd/migrate -action up

migrate-status:
	go run ./cmd/migrate -action status

seed:
	go run ./cmd/seed

smoke:
	powershell -ExecutionPolicy Bypass -File scripts/smoke_test.ps1

generate:
	go generate ./...

down:
	docker compose down
