-- 0015_call_messages.down.sql

ALTER TABLE messages
    DROP COLUMN call_status;
