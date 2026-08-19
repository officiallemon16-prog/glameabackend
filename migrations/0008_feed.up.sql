-- Category cover images for the visual home feed.
ALTER TABLE categories ADD COLUMN image_url VARCHAR(1024) NULL AFTER icon_media_id;

-- Posts power the Instagram-style home feed. Each post is one professional's
-- work with multiple images (a carousel), plus a cover for the service category.
CREATE TABLE IF NOT EXISTS posts (
    id CHAR(36) PRIMARY KEY,
    professional_id CHAR(36) NOT NULL,
    category_id CHAR(36) NULL,
    caption VARCHAR(512) NULL,
    location VARCHAR(255) NULL,
    sponsored TINYINT(1) NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_posts_professional (professional_id, is_active),
    KEY idx_posts_category (category_id, is_active),
    KEY idx_posts_sponsored_created (sponsored, created_at),
    CONSTRAINT fk_posts_professional FOREIGN KEY (professional_id) REFERENCES professionals (id) ON DELETE CASCADE,
    CONSTRAINT fk_posts_category FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Media for a post carousel. `secure_url` is the display URL (direct or from a
-- media asset referenced by `media_asset_id`).
CREATE TABLE IF NOT EXISTS post_media (
    id CHAR(36) PRIMARY KEY,
    post_id CHAR(36) NOT NULL,
    secure_url VARCHAR(1024) NOT NULL,
    media_asset_id CHAR(36) NULL,
    display_order INT NOT NULL DEFAULT 0,
    KEY idx_post_media_post (post_id, display_order),
    CONSTRAINT fk_post_media_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_media_asset FOREIGN KEY (media_asset_id) REFERENCES media_assets (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
