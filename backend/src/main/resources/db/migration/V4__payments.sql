-- M3: transfers, bill payments, payees and saved bills (spec section 8, TRF-*, BILL-*).

-- Recipients see a masked full name ("นาย สมชาย ใจ**"), so customers need a last name.
ALTER TABLE users
    ADD COLUMN last_name_th VARCHAR(100) NOT NULL DEFAULT '',
    ADD COLUMN last_name_en VARCHAR(100) NOT NULL DEFAULT '';

-- A priced, name-checked payment waiting for the customer's confirmation (TRF-05, TRF-06).
-- Amount and recipient are fixed here; the confirm request can only reference the inquiry (13.4.4).
CREATE TABLE payment_inquiries (
    id                 UUID PRIMARY KEY,
    user_id            UUID         NOT NULL REFERENCES users (id),
    device_id          UUID         NOT NULL REFERENCES devices (id),
    kind               VARCHAR(16)  NOT NULL CHECK (kind IN ('transfer', 'bill')),
    recipient_type     VARCHAR(16)  NOT NULL CHECK (recipient_type IN ('own', 'internal', 'other_bank', 'promptpay', 'bill')),
    from_account_id    UUID         NOT NULL REFERENCES accounts (id),
    to_account_id      UUID         REFERENCES accounts (id),
    bank_code          VARCHAR(8),
    account_or_proxy   VARCHAR(32),
    recipient_name     VARCHAR(120) NOT NULL,
    biller_code        VARCHAR(16),
    ref1               VARCHAR(32),
    ref2               VARCHAR(32),
    amount_satang      BIGINT       NOT NULL CHECK (amount_satang > 0),
    fee_satang         BIGINT       NOT NULL DEFAULT 0 CHECK (fee_satang >= 0),
    memo               VARCHAR(100),
    challenge          VARCHAR(64)  NOT NULL,  -- single-use nonce the device signs to authorise this payment
    requires_biometric BOOLEAN      NOT NULL,
    expires_at         TIMESTAMPTZ  NOT NULL,
    consumed_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_payment_inquiries_user ON payment_inquiries (user_id, created_at);

-- A confirmed payment. One per inquiry and per idempotency key (TRF-14).
CREATE TABLE payments (
    id                UUID PRIMARY KEY,
    user_id           UUID        NOT NULL REFERENCES users (id),
    inquiry_id        UUID        NOT NULL UNIQUE REFERENCES payment_inquiries (id),
    idempotency_hash  VARCHAR(64) NOT NULL UNIQUE,  -- SHA-256 of user ID + Idempotency-Key header
    journal_entry_id  UUID        NOT NULL REFERENCES journal_entries (id),
    transaction_id    UUID        NOT NULL REFERENCES transactions (id),  -- the payer's history row
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_user ON payments (user_id, created_at);

-- Favourites and recent recipients (TRF-11).
CREATE TABLE payees (
    id                UUID PRIMARY KEY,
    user_id           UUID         NOT NULL REFERENCES users (id),
    type              VARCHAR(16)  NOT NULL CHECK (type IN ('internal', 'other_bank', 'promptpay')),
    bank_code         VARCHAR(8)   NOT NULL,
    account_or_proxy  VARCHAR(32)  NOT NULL,
    name              VARCHAR(120) NOT NULL,
    nickname          VARCHAR(40),
    favorite          BOOLEAN      NOT NULL DEFAULT FALSE,
    last_used_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (user_id, type, bank_code, account_or_proxy)
);

CREATE TABLE billers (
    code          VARCHAR(16)  PRIMARY KEY,
    name_th       VARCHAR(100) NOT NULL,
    name_en       VARCHAR(100) NOT NULL,
    category      VARCHAR(16)  NOT NULL CHECK (category IN ('electricity', 'water', 'internet', 'mobile', 'credit_card', 'insurance', 'ewallet')),
    ref1_label_th VARCHAR(60)  NOT NULL,
    ref1_label_en VARCHAR(60)  NOT NULL,
    ref2_label_th VARCHAR(60),
    ref2_label_en VARCHAR(60),
    top_up        BOOLEAN      NOT NULL DEFAULT FALSE,  -- customer chooses the amount
    monogram      VARCHAR(3)   NOT NULL,
    qr_biller_id  VARCHAR(20)  UNIQUE                   -- Biller ID in Thai QR bill-payment codes (tag 30)
);

-- Synthetic catalogue for development; QR biller IDs are placeholders until the aggregator contract (D2).
INSERT INTO billers (code, name_th, name_en, category, ref1_label_th, ref1_label_en, ref2_label_th, ref2_label_en, top_up, monogram, qr_biller_id) VALUES
    ('MEA',    'การไฟฟ้านครหลวง',     'Metropolitan Electricity Authority', 'electricity', 'หมายเลขผู้ใช้ไฟฟ้า', 'Customer number',  NULL, NULL, FALSE, 'MEA', '099000000000101'),
    ('PEA',    'การไฟฟ้าส่วนภูมิภาค',  'Provincial Electricity Authority',   'electricity', 'หมายเลขผู้ใช้ไฟฟ้า', 'Customer number',  NULL, NULL, FALSE, 'PEA', '099000000000102'),
    ('MWA',    'การประปานครหลวง',     'Metropolitan Waterworks Authority',  'water',       'เลขที่ผู้ใช้น้ำ',    'Account number',   NULL, NULL, FALSE, 'MWA', '099000000000103'),
    ('AISFIB', 'AIS Fibre',          'AIS Fibre',                          'internet',    'หมายเลขบริการ',     'Service number',   NULL, NULL, FALSE, 'AIS', '099000000000104'),
    ('TRUEON', 'ทรูออนไลน์',          'True Online',                        'internet',    'หมายเลขบริการ',     'Service number',   NULL, NULL, FALSE, 'TRU', '099000000000105'),
    ('LXCARD', 'บัตรเครดิต LuxeBank', 'LuxeBank credit card',               'credit_card', 'เลขบัตร 16 หลัก',    'Card number',      NULL, NULL, FALSE, 'LX',  '099000000000106'),
    ('THLIFE', 'ไทยประกันชีวิต',       'Thai Life Insurance',                'insurance',   'เลขที่กรมธรรม์',     'Policy number',    'เลขอ้างอิง 2', 'Reference 2', FALSE, 'TL', '099000000000107'),
    ('AISTOP', 'เติมเงิน AIS',        'AIS top-up',                         'mobile',      'เบอร์โทรศัพท์',      'Mobile number',    NULL, NULL, TRUE,  'AIS', NULL),
    ('TRUTOP', 'เติมเงิน TrueMove H', 'TrueMove H top-up',                  'mobile',      'เบอร์โทรศัพท์',      'Mobile number',    NULL, NULL, TRUE,  'TRU', NULL),
    ('TMNW',   'TrueMoney Wallet',   'TrueMoney Wallet',                   'ewallet',     'เบอร์โทรศัพท์',      'Mobile number',    NULL, NULL, TRUE,  'TMN', NULL);

-- BILL-03: bills the customer pays regularly.
CREATE TABLE saved_bills (
    id           UUID PRIMARY KEY,
    user_id      UUID        NOT NULL REFERENCES users (id),
    biller_code  VARCHAR(16) NOT NULL REFERENCES billers (code),
    ref1         VARCHAR(32) NOT NULL,
    ref2         VARCHAR(32) NOT NULL DEFAULT '',
    nickname     VARCHAR(40),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, biller_code, ref1, ref2)
);
