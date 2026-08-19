-- 0011_payment_checkout.down.sql

ALTER TABLE payment_intents
    DROP COLUMN authorization_url;
