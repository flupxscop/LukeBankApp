-- M1: customers, bound devices and refresh tokens (spec section 8, AUTH-01…09).

CREATE TABLE users (
    id                        UUID PRIMARY KEY,
    citizen_id_hash           VARCHAR(64)  NOT NULL UNIQUE,  -- HMAC-SHA256, never the raw ID (13.3.1)
    password_hash             TEXT         NOT NULL,         -- Argon2id over a peppered HMAC
    phone                     VARCHAR(20)  NOT NULL,
    first_name_th             VARCHAR(100) NOT NULL,
    first_name_en             VARCHAR(100) NOT NULL,
    tier                      VARCHAR(16)  NOT NULL,
    failed_password_attempts  INT          NOT NULL DEFAULT 0,
    locked_until              TIMESTAMPTZ,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version                   BIGINT       NOT NULL DEFAULT 0
);

CREATE TABLE devices (
    id                    UUID PRIMARY KEY,
    user_id               UUID         NOT NULL REFERENCES users (id),
    device_name           VARCHAR(100) NOT NULL,
    public_key            BYTEA        NOT NULL,   -- P-256 X9.63, Secure Enclave
    biometric_public_key  BYTEA,                   -- P-256 X9.63, biometry-gated key
    pin_hash              TEXT         NOT NULL,
    failed_pin_attempts   INT          NOT NULL DEFAULT 0,
    pin_locked            BOOLEAN      NOT NULL DEFAULT FALSE,
    registered_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    revoked_at            TIMESTAMPTZ,
    version               BIGINT       NOT NULL DEFAULT 0
);

-- One active device per customer (AUTH-09).
CREATE UNIQUE INDEX uq_devices_one_active_per_user ON devices (user_id) WHERE revoked_at IS NULL;

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY,
    family_id   UUID        NOT NULL,
    device_id   UUID        NOT NULL REFERENCES devices (id),
    token_hash  VARCHAR(64) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
CREATE INDEX idx_refresh_tokens_device ON refresh_tokens (device_id);
