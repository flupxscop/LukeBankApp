-- Baseline schema. Domain tables (users, accounts, ledger, ...) arrive with M1/M2 (spec section 8).

-- Append-only audit trail (spec 7.2, 13.1 A09). Each row stores the hash of the previous row.
CREATE TABLE audit_log (
    id            BIGSERIAL PRIMARY KEY,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_id      UUID,
    action        VARCHAR(64) NOT NULL,
    metadata      JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip            INET,
    device_id     UUID,
    trace_id      VARCHAR(64),
    previous_hash CHAR(64),
    row_hash      CHAR(64) NOT NULL
);

CREATE INDEX idx_audit_log_actor ON audit_log (actor_id, occurred_at);

CREATE FUNCTION audit_log_reject_change() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_log_no_update
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_reject_change();
