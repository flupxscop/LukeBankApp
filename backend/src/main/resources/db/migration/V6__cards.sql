-- M4: debit and credit cards (spec section 8 "Card", CARD-01…09).

-- A credit card spends from its own ledger account: the balance is negative while money is owed,
-- never below minus the credit limit. Deposit accounts keep credit_limit 0, so they still cannot go negative.
ALTER TABLE accounts DROP CONSTRAINT accounts_type_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_type_check CHECK (type IN ('current', 'savings', 'internal', 'credit'));
ALTER TABLE accounts ADD COLUMN credit_limit_satang BIGINT NOT NULL DEFAULT 0 CHECK (credit_limit_satang >= 0);
ALTER TABLE accounts DROP CONSTRAINT chk_accounts_customer_balance;
ALTER TABLE accounts ADD CONSTRAINT chk_accounts_customer_balance CHECK (user_id IS NULL OR balance_satang >= -credit_limit_satang);
ALTER TABLE accounts ADD CONSTRAINT chk_accounts_credit_only CHECK (type = 'credit' OR credit_limit_satang = 0);

-- The full card number and CVV live only at the card processor; LuxeBank keeps its token (PCI scope reduction).
CREATE TABLE cards (
    id                     UUID PRIMARY KEY,
    user_id                UUID        NOT NULL REFERENCES users (id),
    account_id             UUID        NOT NULL REFERENCES accounts (id),  -- debit: linked deposit account; credit: the card's credit account
    type                   VARCHAR(8)  NOT NULL CHECK (type IN ('debit', 'credit')),
    product_name           VARCHAR(60) NOT NULL,
    last4                  CHAR(4)     NOT NULL,
    token_ref              VARCHAR(64) NOT NULL UNIQUE,
    expiry_month           SMALLINT    NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year            SMALLINT    NOT NULL,
    status                 VARCHAR(8)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'lost', 'closed')),
    daily_limit_satang     BIGINT      NOT NULL CHECK (daily_limit_satang > 0),
    max_daily_limit_satang BIGINT      NOT NULL,
    online_enabled         BOOLEAN     NOT NULL DEFAULT TRUE,
    overseas_enabled       BOOLEAN     NOT NULL DEFAULT FALSE,
    contactless_enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
    atm_enabled            BOOLEAN     NOT NULL DEFAULT TRUE,
    reward_points          BIGINT      NOT NULL DEFAULT 0 CHECK (reward_points >= 0),
    travel_insurance       BOOLEAN     NOT NULL DEFAULT FALSE,
    replaced_by            UUID        REFERENCES cards (id),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    version                BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT chk_cards_daily_limit CHECK (daily_limit_satang <= max_daily_limit_satang)
);

CREATE INDEX idx_cards_user ON cards (user_id);

-- Which card made a purchase (CARD-09); NULL for transfers, bills and deposits.
ALTER TABLE transactions ADD COLUMN card_id UUID REFERENCES cards (id);
CREATE INDEX idx_transactions_card_time ON transactions (card_id, occurred_at DESC, id DESC) WHERE card_id IS NOT NULL;
