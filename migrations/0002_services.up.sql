CREATE TABLE IF NOT EXISTS cancellation_policies (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    name VARCHAR(120) NOT NULL,
    free_cancel_hours INT NOT NULL DEFAULT 24,
    cancel_fee_percent DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    is_default TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_cancel_policies_professional (professional_id),
    CONSTRAINT fk_cancel_policies_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS services (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    category_id CHAR(36) NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT NULL,
    base_price DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(8) NOT NULL DEFAULT 'NGN',
    duration_minutes INT NOT NULL DEFAULT 30,
    deposit_percentage DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    home_service_available TINYINT(1) NOT NULL DEFAULT 0,
    cancellation_policy_id CHAR(36) NULL,
    display_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_services_professional (professional_id),
    KEY idx_services_category (category_id),
    KEY idx_services_professional_active (professional_id, is_active),
    CONSTRAINT fk_services_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_services_category FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL,
    CONSTRAINT fk_services_cancel_policy FOREIGN KEY (cancellation_policy_id) REFERENCES cancellation_policies (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS service_variants (
    id CHAR(36) PRIMARY KEY,
    service_id CHAR(36) NOT NULL,
    name VARCHAR(60) NOT NULL,
    price_delta DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    duration_delta_minutes INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_service_variants (service_id, name),
    CONSTRAINT fk_service_variants_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
