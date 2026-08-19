-- 0013_message_types.down.sql

ALTER TABLE messages
    DROP COLUMN call_type,
    DROP COLUMN address,
    DROP COLUMN longitude,
    DROP COLUMN latitude,
    DROP COLUMN height,
    DROP COLUMN width,
    DROP COLUMN duration_ms,
    DROP COLUMN mime_type,
    DROP COLUMN media_url,
    DROP COLUMN media_asset_id,
    DROP COLUMN type;
