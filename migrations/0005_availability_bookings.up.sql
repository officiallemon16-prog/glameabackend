-- 0005_availability_bookings.up.sql
-- Availability windows (weekly recurring) and one-off exceptions.

CREATE TABLE IF NOT EXISTS availability_windows (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    day_of_week TINYINT NOT NULL COMMENT '0=Sunday .. 6=Saturday',
    start_minutes INT NOT NULL COMMENT 'minutes from midnight',
    end_minutes INT NOT NULL COMMENT 'minutes from midnight',
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_avail_windows_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT chk_avail_window CHECK (start_minutes >= 0 AND end_minutes > start_minutes AND end_minutes <= 1440)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS availability_exceptions (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    exception_date DATE NOT NULL,
    start_minutes INT NULL COMMENT 'minutes from midnight, NULL for full-day',
    end_minutes INT NULL COMMENT 'minutes from midnight, NULL for full-day',
    is_available TINYINT(1) NOT NULL DEFAULT 0 COMMENT '0=blocked, 1=extra window',
    note VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_avail_exceptions_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_avail_windows_pro ON availability_windows (professional_id, day_of_week);
CREATE INDEX idx_avail_exceptions_pro_date ON availability_exceptions (professional_id, exception_date);

-- Bookings + status history.

CREATE TABLE IF NOT EXISTS bookings (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    customer_id CHAR(36) NOT NULL,
    service_id CHAR(36) NOT NULL,
    variant_id CHAR(36) NULL,
    status ENUM('PENDING','CONFIRMED','IN_PROGRESS','COMPLETED','CANCELLED','NO_SHOW') NOT NULL DEFAULT 'PENDING',
    start_at DATETIME NOT NULL,
    end_at DATETIME NOT NULL,
    base_amount DECIMAL(12,2) NOT NULL,
    total_amount DECIMAL(12,2) NOT NULL,
    deposit_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    home_service TINYINT(1) NOT NULL DEFAULT 0,
    location_lat DECIMAL(10,7) NULL,
    location_lng DECIMAL(10,7) NULL,
    location_address VARCHAR(255) NULL,
    customer_notes TEXT NULL,
    cancellation_policy_id CHAR(36) NULL,
    idempotency_key VARCHAR(128) NULL,
    cancelled_at DATETIME NULL,
    cancelled_by CHAR(36) NULL,
    cancel_reason VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookings_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_bookings_customer FOREIGN KEY (customer_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_bookings_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_variant FOREIGN KEY (variant_id) REFERENCES service_variants (id) ON DELETE SET NULL,
    CONSTRAINT fk_bookings_cancel_policy FOREIGN KEY (cancellation_policy_id) REFERENCES cancellation_policies (id) ON DELETE SET NULL,
    CONSTRAINT uq_bookings_idempotency UNIQUE (idempotency_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_bookings_pro_start ON bookings (professional_id, start_at);
CREATE INDEX idx_bookings_customer_start ON bookings (customer_id, start_at);
CREATE INDEX idx_bookings_status ON bookings (status);

CREATE TABLE IF NOT EXISTS booking_status_history (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    from_status VARCHAR(20) NULL,
    to_status VARCHAR(20) NOT NULL,
    changed_by CHAR(36) NULL,
    note VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_booking_history_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_booking_history_booking ON booking_status_history (booking_id);

