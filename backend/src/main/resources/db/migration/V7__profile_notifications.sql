-- M5: profile, preferences, push tokens and the notification inbox (PROF-01…09, NOTI-01…03).

CREATE TABLE relationship_managers (
    id        UUID PRIMARY KEY,
    name_th   VARCHAR(100) NOT NULL,
    name_en   VARCHAR(100) NOT NULL,
    phone     VARCHAR(20)  NOT NULL,
    hours_th  VARCHAR(60)  NOT NULL,
    hours_en  VARCHAR(60)  NOT NULL
);

ALTER TABLE users
    ADD COLUMN relationship_manager_id UUID REFERENCES relationship_managers (id),
    ADD COLUMN preferred_language VARCHAR(2) NOT NULL DEFAULT 'th' CHECK (preferred_language IN ('th', 'en')),
    -- Security alerts cannot be turned off (NOTI-02), so there is no column for them.
    ADD COLUMN notify_transactions BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN notify_marketing BOOLEAN NOT NULL DEFAULT FALSE;

-- APNs device token of the bound device; replaced when iOS issues a new one.
ALTER TABLE devices ADD COLUMN push_token VARCHAR(200);

-- In-app inbox. Text is stored in the customer's language at the time it was sent.
CREATE TABLE notifications (
    id          UUID PRIMARY KEY,
    user_id     UUID         NOT NULL REFERENCES users (id),
    kind        VARCHAR(12)  NOT NULL CHECK (kind IN ('transaction', 'security', 'marketing')),
    title       VARCHAR(120) NOT NULL,
    body        VARCHAR(300) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    read_at     TIMESTAMPTZ
);

CREATE INDEX idx_notifications_user_time ON notifications (user_id, created_at DESC, id DESC);

-- Synthetic relationship manager for the simulation (D26).
INSERT INTO relationship_managers (id, name_th, name_en, phone, hours_th, hours_en)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'นกนางน้อย ใจดี', 'Noknangnoi Jaidee', '021234567',
        'จันทร์–ศุกร์ 09:00–18:00', 'Mon–Fri 09:00–18:00');
