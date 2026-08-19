-- 0013_message_types.up.sql
-- Rich messages: image/location/call media columns on messages.
-- NOTE: only the first ADD COLUMN may use AFTER (against the pre-existing
-- schema). TiDB cannot resolve an AFTER clause that references a column added
-- in the same ALTER statement, so the remaining columns are appended in order.

ALTER TABLE messages
    ADD COLUMN type ENUM('TEXT','IMAGE','VOICE','VIDEO','LOCATION','CALL') NOT NULL DEFAULT 'TEXT' AFTER body,
    ADD COLUMN media_asset_id CHAR(36) NULL,
    ADD COLUMN media_url VARCHAR(1024) NULL,
    ADD COLUMN mime_type VARCHAR(120) NULL,
    ADD COLUMN duration_ms INT NULL,
    ADD COLUMN width INT NULL,
    ADD COLUMN height INT NULL,
    ADD COLUMN latitude DECIMAL(10,7) NULL,
    ADD COLUMN longitude DECIMAL(10,7) NULL,
    ADD COLUMN address VARCHAR(500) NULL,
    ADD COLUMN call_type ENUM('VOICE','VIDEO') NULL;
