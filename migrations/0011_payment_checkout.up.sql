-- 0011_payment_checkout.up.sql
-- Adds the gateway checkout URL (Paystack authorization_url) to payment intents.

ALTER TABLE payment_intents
    ADD COLUMN authorization_url VARCHAR(500) NULL AFTER gateway_reference;
