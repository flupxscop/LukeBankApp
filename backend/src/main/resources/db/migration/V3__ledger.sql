-- M2: accounts, double-entry ledger, transaction read model and budgets (spec 7.2, section 8, 13.2 Integrity).

CREATE TABLE accounts (
    id                          UUID PRIMARY KEY,
    user_id                     UUID         REFERENCES users (id),  -- NULL = bank internal account
    type                        VARCHAR(16)  NOT NULL CHECK (type IN ('current', 'savings', 'internal')),
    name                        VARCHAR(100) NOT NULL,
    account_number              VARCHAR(20)  NOT NULL UNIQUE,
    currency                    CHAR(3)      NOT NULL DEFAULT 'THB',
    status                      VARCHAR(16)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'closed')),
    is_primary                  BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Snapshot of SUM(postings), kept in the posting transaction and checked by the daily reconciliation.
    balance_satang              BIGINT       NOT NULL DEFAULT 0,
    daily_transfer_limit_satang BIGINT       NOT NULL DEFAULT 20000000,
    created_at                  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version                     BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT chk_accounts_internal_has_no_owner CHECK ((type = 'internal') = (user_id IS NULL)),
    -- Customer accounts can never go negative, whatever the application does.
    CONSTRAINT chk_accounts_customer_balance CHECK (user_id IS NULL OR balance_satang >= 0)
);

CREATE INDEX idx_accounts_user ON accounts (user_id);
CREATE UNIQUE INDEX uq_accounts_one_primary_per_user ON accounts (user_id) WHERE is_primary;

CREATE TABLE journal_entries (
    id               UUID PRIMARY KEY,
    type             VARCHAR(16) NOT NULL
        CHECK (type IN ('opening', 'deposit', 'transfer', 'bill', 'card', 'fee', 'interest', 'cashback', 'investment')),
    reference_no     VARCHAR(24) NOT NULL UNIQUE,
    idempotency_key  VARCHAR(64) UNIQUE,
    status           VARCHAR(16) NOT NULL DEFAULT 'posted' CHECK (status IN ('pending', 'posted', 'failed', 'reversed')),
    occurred_at      TIMESTAMPTZ NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Signed amounts: positive credits the account, negative debits it. Every entry sums to zero.
CREATE TABLE postings (
    id                BIGSERIAL PRIMARY KEY,
    journal_entry_id  UUID   NOT NULL REFERENCES journal_entries (id),
    account_id        UUID   NOT NULL REFERENCES accounts (id),
    amount_satang     BIGINT NOT NULL CHECK (amount_satang <> 0)
);

CREATE INDEX idx_postings_account ON postings (account_id);
CREATE INDEX idx_postings_entry ON postings (journal_entry_id);

CREATE FUNCTION postings_reject_change() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'postings are append-only; post a reversing entry instead';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER postings_no_update
    BEFORE UPDATE OR DELETE ON postings
    FOR EACH ROW EXECUTE FUNCTION postings_reject_change();

-- Checked at commit, so all postings of an entry can be inserted first.
CREATE FUNCTION postings_check_balanced() RETURNS trigger AS $$
DECLARE
    total BIGINT;
    lines INT;
BEGIN
    SELECT COALESCE(SUM(amount_satang), 0), COUNT(*) INTO total, lines
    FROM postings WHERE journal_entry_id = NEW.journal_entry_id;
    IF total <> 0 OR lines < 2 THEN
        RAISE EXCEPTION 'journal entry % is unbalanced (sum %, % postings)', NEW.journal_entry_id, total, lines;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER postings_balanced
    AFTER INSERT ON postings
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION postings_check_balanced();

-- Read model for history screens: one row per customer-account posting (spec section 8 "Transaction").
CREATE TABLE transactions (
    id                UUID PRIMARY KEY,
    account_id        UUID         NOT NULL REFERENCES accounts (id),
    journal_entry_id  UUID         NOT NULL REFERENCES journal_entries (id),
    merchant          VARCHAR(100) NOT NULL,
    monogram          VARCHAR(3),
    category          VARCHAR(16)  NOT NULL,
    channel           VARCHAR(16)  NOT NULL,
    amount_satang     BIGINT       NOT NULL,
    memo              VARCHAR(100),
    occurred_at       TIMESTAMPTZ  NOT NULL,
    version           BIGINT       NOT NULL DEFAULT 0
);

CREATE INDEX idx_transactions_account_time ON transactions (account_id, occurred_at DESC, id DESC);

CREATE TABLE spending_budgets (
    id            UUID PRIMARY KEY,
    user_id       UUID        NOT NULL REFERENCES users (id),
    kind          VARCHAR(16) NOT NULL CHECK (kind IN ('lifestyle', 'travel')),
    month         DATE        NOT NULL CHECK (EXTRACT(DAY FROM month) = 1),
    limit_satang  BIGINT      NOT NULL CHECK (limit_satang > 0),
    UNIQUE (user_id, kind, month)
);

CREATE TABLE savings_goals (
    id             UUID PRIMARY KEY,
    user_id        UUID         NOT NULL UNIQUE REFERENCES users (id),
    account_id     UUID         NOT NULL REFERENCES accounts (id),
    name           VARCHAR(100) NOT NULL,
    target_satang  BIGINT       NOT NULL CHECK (target_satang > 0)
);

-- Counterparty for money entering or leaving the bank (other banks, merchants, payroll).
INSERT INTO accounts (id, user_id, type, name, account_number)
VALUES ('00000000-0000-0000-0000-000000000001', NULL, 'internal', 'External clearing', 'INT-CLEARING');
