-- 0015_call_messages.up.sql
-- Tracks the outcome of CALL messages so the chat can render missed calls,
-- answered calls with duration, and declined calls distinctly.

ALTER TABLE messages
    ADD COLUMN call_status ENUM('MISSED','ANSWERED','DECLINED') NULL AFTER call_type;
