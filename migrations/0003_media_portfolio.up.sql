CREATE TABLE IF NOT EXISTS media_assets (
    id CHAR(36) PRIMARY KEY,
    uploader_id CHAR(36) NOT NULL,
    provider VARCHAR(32) NOT NULL DEFAULT 'cloudinary',
    public_id VARCHAR(512) NOT NULL,
    resource_type VARCHAR(32) NOT NULL DEFAULT 'image',
    format VARCHAR(16) NULL,
    width INT NULL,
    height INT NULL,
    duration_ms INT NULL,
    bytes BIGINT NULL,
    secure_url VARCHAR(1024) NULL,
    folder VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_media_provider_public_id (provider, public_id),
    KEY idx_media_uploader (uploader_id),
    CONSTRAINT fk_media_uploader FOREIGN KEY (uploader_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS portfolio_items (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    media_asset_id CHAR(36) NOT NULL,
    service_id CHAR(36) NULL,
    caption VARCHAR(512) NULL,
    is_featured TINYINT(1) NOT NULL DEFAULT 0,
    display_order INT NOT NULL DEFAULT 0,
    before_after_pair_id CHAR(36) NULL,
    is_verification TINYINT(1) NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_portfolio_professional (professional_id, is_active),
    KEY idx_portfolio_featured (professional_id, is_featured),
    CONSTRAINT fk_portfolio_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_portfolio_media FOREIGN KEY (media_asset_id) REFERENCES media_assets (id) ON DELETE CASCADE,
    CONSTRAINT fk_portfolio_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
