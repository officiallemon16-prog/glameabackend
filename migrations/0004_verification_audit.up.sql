CREATE TABLE IF NOT EXISTS audit_logs (
    id CHAR(36) PRIMARY KEY,
    actor_id CHAR(36) NULL,
    actor_role VARCHAR(32) NULL,
    action VARCHAR(120) NOT NULL,
    entity_type VARCHAR(60) NOT NULL,
    entity_id CHAR(36) NULL,
    before_state JSON NULL,
    after_state JSON NULL,
    ip VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_audit_entity (entity_type, entity_id),
    KEY idx_audit_actor (actor_id),
    KEY idx_audit_action (action),
    CONSTRAINT fk_audit_actor FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_documents (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    stage ENUM('IDENTITY','BUSINESS','LOCATION','CERTIFICATE') NOT NULL,
    document_type VARCHAR(60) NOT NULL,
    media_asset_id CHAR(36) NULL,
    status ENUM('PENDING','APPROVED','REJECTED','REVIEWING') NOT NULL DEFAULT 'PENDING',
    reviewer_id CHAR(36) NULL,
    review_note TEXT NULL,
    submitted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_verification_docs_professional (professional_id),
    KEY idx_verification_docs_status (status),
    CONSTRAINT fk_verification_docs_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_docs_media FOREIGN KEY (media_asset_id) REFERENCES media_assets (id) ON DELETE SET NULL,
    CONSTRAINT fk_verification_docs_reviewer FOREIGN KEY (reviewer_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_events (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    stage VARCHAR(32) NOT NULL,
    action VARCHAR(60) NOT NULL,
    actor_id CHAR(36) NULL,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_verification_events_professional (professional_id),
    CONSTRAINT fk_verification_events_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_events_actor FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
