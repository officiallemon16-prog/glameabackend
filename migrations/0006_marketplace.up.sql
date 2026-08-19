-- 0006_marketplace.up.sql
-- Payments, wallets, payouts, reviews, messaging, notifications, disputes, deals, platform settings.

CREATE TABLE IF NOT EXISTS wallets (
    id CHAR(36) NOT NULL PRIMARY KEY,
    user_id CHAR(36) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_wallets_user_currency (user_id, currency),
    CONSTRAINT fk_wallets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id CHAR(36) NOT NULL PRIMARY KEY,
    user_id CHAR(36) NOT NULL,
    booking_id CHAR(36) NULL,
    payment_intent_id CHAR(36) NULL,
    type ENUM('DEBIT','CREDIT') NOT NULL,
    category ENUM('DEPOSIT','BALANCE_PAYMENT','FULL_PAYMENT','REFUND','EARNING','PLATFORM_FEE','PAYOUT','ADJUSTMENT') NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    balance_after DECIMAL(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    reference VARCHAR(128) NOT NULL,
    meta JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_wallet_tx_reference (reference),
    KEY idx_wallet_tx_user (user_id, created_at),
    CONSTRAINT fk_wallet_tx_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_tx_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payment_intents (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    customer_id CHAR(36) NOT NULL,
    amount_type ENUM('DEPOSIT','BALANCE','FULL') NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    status ENUM('PENDING','SUCCEEDED','FAILED','REFUNDED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    gateway VARCHAR(32) NULL,
    gateway_reference VARCHAR(128) NULL,
    provider_charge DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    platform_fee DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_payment_intent_booking_type (booking_id, amount_type),
    KEY idx_payment_intent_customer (customer_id, created_at),
    KEY idx_payment_intent_status (status),
    CONSTRAINT fk_payment_intent_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE,
    CONSTRAINT fk_payment_intent_customer FOREIGN KEY (customer_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payout_accounts (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    bank_name VARCHAR(120) NOT NULL,
    bank_code VARCHAR(20) NULL,
    account_number VARCHAR(32) NOT NULL,
    account_name VARCHAR(120) NOT NULL,
    is_verified TINYINT(1) NOT NULL DEFAULT 0,
    is_default TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_payout_accounts_pro (professional_id),
    CONSTRAINT fk_payout_accounts_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payouts (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    payout_account_id CHAR(36) NULL,
    amount DECIMAL(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    status ENUM('PENDING','PAID','FAILED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    gateway_reference VARCHAR(128) NULL,
    note VARCHAR(255) NULL,
    paid_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_payouts_pro (professional_id, created_at),
    KEY idx_payouts_status (status),
    CONSTRAINT fk_payouts_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_payouts_account FOREIGN KEY (payout_account_id) REFERENCES payout_accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS reviews (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    professional_id CHAR(36) NOT NULL,
    customer_id CHAR(36) NOT NULL,
    service_id CHAR(36) NULL,
    rating TINYINT NOT NULL,
    comment TEXT NULL,
    response TEXT NULL,
    responded_at TIMESTAMP NULL,
    is_published TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_reviews_booking (booking_id),
    KEY idx_reviews_pro (professional_id, created_at),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_reviews_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_customer FOREIGN KEY (customer_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS conversations (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    customer_id CHAR(36) NOT NULL,
    professional_id CHAR(36) NOT NULL,
    last_message TEXT NULL,
    last_message_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_conversations_booking (booking_id),
    CONSTRAINT fk_conversations_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversations_customer FOREIGN KEY (customer_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversations_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS messages (
    id CHAR(36) NOT NULL PRIMARY KEY,
    conversation_id CHAR(36) NOT NULL,
    sender_id CHAR(36) NOT NULL,
    recipient_id CHAR(36) NOT NULL,
    body TEXT NOT NULL,
    is_read TINYINT(1) NOT NULL DEFAULT 0,
    read_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_messages_conversation (conversation_id, created_at),
    CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_recipient FOREIGN KEY (recipient_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notifications (
    id CHAR(36) NOT NULL PRIMARY KEY,
    user_id CHAR(36) NOT NULL,
    type VARCHAR(40) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body VARCHAR(1000) NULL,
    data JSON NULL,
    is_read TINYINT(1) NOT NULL DEFAULT 0,
    read_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_notifications_user (user_id, created_at),
    KEY idx_notifications_unread (user_id, is_read),
    CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS disputes (
    id CHAR(36) NOT NULL PRIMARY KEY,
    booking_id CHAR(36) NOT NULL,
    raised_by CHAR(36) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    description TEXT NULL,
    status ENUM('OPEN','RESOLVED','CLOSED') NOT NULL DEFAULT 'OPEN',
    resolution TEXT NULL,
    resolved_by CHAR(36) NULL,
    resolved_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_disputes_status (status),
    KEY idx_disputes_booking (booking_id),
    CONSTRAINT fk_disputes_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE,
    CONSTRAINT fk_disputes_raised_by FOREIGN KEY (raised_by) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispute_messages (
    id CHAR(36) NOT NULL PRIMARY KEY,
    dispute_id CHAR(36) NOT NULL,
    sender_id CHAR(36) NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_dispute_messages_dispute (dispute_id, created_at),
    CONSTRAINT fk_dispute_messages_dispute FOREIGN KEY (dispute_id) REFERENCES disputes (id) ON DELETE CASCADE,
    CONSTRAINT fk_dispute_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS deals (
    id CHAR(36) NOT NULL PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    code VARCHAR(40) NULL,
    name VARCHAR(120) NOT NULL,
    description TEXT NULL,
    discount_type ENUM('PERCENT','FIXED') NOT NULL DEFAULT 'PERCENT',
    discount_value DECIMAL(10,2) NOT NULL,
    min_order_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    usage_limit INT NULL,
    times_used INT NOT NULL DEFAULT 0,
    starts_at TIMESTAMP NULL,
    ends_at TIMESTAMP NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_deals_code (code),
    KEY idx_deals_pro (professional_id),
    CONSTRAINT fk_deals_pro FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS deal_services (
    deal_id CHAR(36) NOT NULL,
    service_id CHAR(36) NOT NULL,
    PRIMARY KEY (deal_id, service_id),
    CONSTRAINT fk_deal_services_deal FOREIGN KEY (deal_id) REFERENCES deals (id) ON DELETE CASCADE,
    CONSTRAINT fk_deal_services_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS platform_settings (
    name VARCHAR(80) NOT NULL PRIMARY KEY,
    value TEXT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO platform_settings (name, value) VALUES
    ('platform_name', 'Glamea'),
    ('platform_fee_percent', '8.00'),
    ('default_currency', 'NGN'),
    ('booking_payment_required', 'false'),
    ('payout_holding_hours', '168')
ON DUPLICATE KEY UPDATE name = name;

-- System account that accrues platform fees (virtual user, referenced by wallets).
INSERT IGNORE INTO users (id, email, first_name, last_name, role, status) VALUES
    ('00000000-0000-0000-0000-000000000000', 'platform@glamea.local', 'Platform', 'System', 'ADMIN', 'ACTIVE');
