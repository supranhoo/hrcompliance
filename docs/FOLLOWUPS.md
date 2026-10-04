# Follow-up items

Open items that do not block a milestone. Each needs its own migration (0034+) and live verification before it is locked.

## FU-001 Configuration-driven fallback routing (replace hardcoded `HEAD_HR`)
- **Where:** `app.resolve_recipients` (0020, re-created with a department parameter in 0033) routes the "owner has no active user" fallback to users whose role code is `HEAD_HR`. The same hardcoded code now exists in the 4-argument version (0020) and the 5-argument version (0033). `app.unroutable_recipients` also uses the literal `SUPER_ADMIN` for the development-only fallback (D-001; this one is intentionally environment-gated).
- **Why it matters:** it is routing, not access control. A user still only receives an alert if they hold the entity/location/department scope, so it is not a security issue (confirmed with the department-scope tests). It does contradict "no role-name-specific logic" and silently depends on a role existing.
- **Proposed change:** a configurable alert rule/setting (for example `OWNER_FALLBACK` recipients, role or user list, same shape as `UNROUTABLE_ESCALATION`), read by one resolver, validated by `alert_routing_validation()`, editable on the Alert Rules screen with a reason and audit. Keep the old behaviour as the seeded default until the owner configures it. Collapse the 4- and 5-argument resolvers into one.
- **Acceptance:** no role literal in `resolve_recipients`; routing tests (suites 46, 49, 59) pass unchanged; validation reports a missing fallback; a rule change is audited.
- **Status:** open, opened 2026-10-04. Not blocking 0033 (owner decision).
