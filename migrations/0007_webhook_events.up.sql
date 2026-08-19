-- 0007_webhook_events.up.sql
-- Webhook event deduplication + booking reminder tracking.

CREATE TABLE IF NOT EXISTS payment_events (
    id CHAR(36) NOT NULL PRIMARY KEY,
    gateway VARCHAR(32) NOT NULL,
    event_id VARCHAR(128) NOT NULL,
    reference VARCHAR(128) NOT NULL,
    payload MEDIUMTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_payment_events_gateway_event (gateway, event_id),
    KEY idx_payment_events_reference (reference)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS booking_reminders (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    kind VARCHAR(32) NOT NULL,
    sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_booking_reminders_booking_kind (booking_id, kind),
    CONSTRAINT fk_booking_reminders_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
