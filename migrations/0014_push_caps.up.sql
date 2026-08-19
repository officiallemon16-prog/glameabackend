-- 0014_push_caps.up.sql
-- Frequency caps for re-engagement pushes so we never spam a user. One row is
-- inserted every time a re-engagement push is claimed (sent); jobs check that
-- the last claim for (user, cap_type) is older than the configured cooldown
-- before sending again.

CREATE TABLE IF NOT EXISTS push_caps (
    id CHAR(36) NOT NULL PRIMARY KEY,
    user_id CHAR(36) NOT NULL,
    cap_type VARCHAR(40) NOT NULL,
    claimed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_push_caps_user_type (user_id, cap_type, claimed_at),
    CONSTRAINT fk_push_caps_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
