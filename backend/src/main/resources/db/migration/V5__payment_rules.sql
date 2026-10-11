-- M3 review fixes.

-- Internal accounts no longer keep a balance snapshot: locking and updating that one row on every
-- external payment serialised the whole bank. Their balance is SUM(postings); reconciliation covers
-- customer accounts only.
UPDATE accounts SET balance_satang = 0 WHERE user_id IS NULL;
COMMENT ON COLUMN accounts.balance_satang IS 'Snapshot of SUM(postings) for customer accounts; always 0 for internal accounts';

-- Billers that accept any amount up to what is due (cards, insurance). Others must be paid in full.
ALTER TABLE billers ADD COLUMN partial_payment BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE billers SET partial_payment = TRUE WHERE code IN ('LXCARD', 'THLIFE');
