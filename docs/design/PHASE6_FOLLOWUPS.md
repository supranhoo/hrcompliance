# Phase 6 follow-ups — DESIGN ONLY (nothing here is implemented; no migration exists)

**Gate:** implementation starts only after (1) the owner's `live_gate.sql` result is PASS and recorded, (2) the UAT baseline (runbook Parts 2–4) is captured in `docs/LIVE_VERIFICATION.md`, and (3) migrations 0014–0022 are hash-locked. The changes below are **new migrations 0023+**; no applied migration is edited.
Owner decisions (2026-10-03) driving this design: D-001 approved, F-1 decided, F-2 decided, provisional UAT defaults accepted — see `docs/DEFAULTS_DECISIONS.md`.

## 1. D-001 — no alert may disappear silently (+ UNROUTABLE)
**Rule:** every alert that *should* fire must end in exactly one of: a delivered notification, a queued email, or an **UNROUTABLE** record that is visible to administrators. "Nothing happened" is never an outcome.

**Recipient resolution order (per alert):**
1. Recipients named by the alert rule (owner, `role:X`, `user:<id>`), active and in scope.
2. If none: the **configured business escalation recipients** (new alert-rule code `UNROUTABLE_ESCALATION`, versioned, editable — roles/users chosen by BFCL; **this is the only fallback in UAT/UAT-like and production**).
3. **DEVELOPMENT only** (`system_config environment.name = "development"`): active SUPER_ADMIN in scope. Never in production/UAT.
4. If still none → **UNROUTABLE**.

**UNROUTABLE handling:**
* new exception category `alert_unroutable` (severity high), one active exception per `alert_unroutable:<record>:<rule>` key (idempotent), parent = the obligation/licence; resolves automatically when the record gets a routable recipient or is closed;
* a persistent admin-visible notification is **not** possible without a recipient, so visibility is guaranteed through (a) the exception register, (b) the dashboard exception counts, (c) **System Health**: `system_health()` gains `unroutable_alerts` (count of active `alert_unroutable` exceptions) and the page shows a red tile + link to `/exceptions?category=alert_unroutable`, (d) `generate_alerts()` returns `unroutable` in its result and `run_alert_generation` marks the **job run with a warning** (`error_detail.warning`) so the Job Monitor shows it;
* the live gate and the engine demo add checks: unroutable ≥ 0 reported, never swallowed.

**Tests (CI):** no owner + no Head HR + no escalation config → UNROUTABLE exception, health count 1, job warning; dev environment → Super Admin receives; production label → Super Admin does **not** receive and exception is raised; configured escalation recipients receive in production; idempotent re-run; auto-resolution when an owner is assigned.

## 2. F-1 — read visibility
Decision: legal/reference masters and Compliance Master (+ rule versions, categories) remain readable by authorised HR users **regardless of scope**. **Applicability Matrix and everything transactional or location-specific are scope-controlled.**
Interpretation (safest; please correct if wrong): "location-specific data" includes the **location master itself** — a scoped user lists only locations in their scope (`scope_all` users unchanged). Consequences to handle in the migration:
* `compliance_applicability` SELECT policy → `compliance.read` **and** row in scope (`app.scope_ok(entity_id, location_id)`); global rows (no entity/location) readable only by `scope_all` users;
* `location` SELECT policy → `master.read` **and** in scope; pick-lists therefore show only permitted locations;
* `compliance_coverage()` and `applicability_for` callers see only in-scope pairs (they inherit the above; `applicability_for` is `SECURITY DEFINER`, so add an explicit scope check);
* `entity`, `business_unit`, `unit` stay as-is unless the owner says otherwise (entity-level scope is already enforced for writes).
**Tests:** a single-location user sees one location, its applicability rows and coverage only; unscoped users see none; `scope_all` sees all; compliance master still globally readable; `uat_scope_check.sql` coverage row changes from INFO to a hard PASS expectation (0 other-location rows).

## 3. F-2 — reconcile future untouched obligations when a rule version takes effect
**Rule:** completed / actioned obligations stay **pinned** to their original rule version. Future **untouched** obligations whose period starts on or after the new version's `effective_from` are **superseded** by obligations under the new rule, with full audit history and no duplicates.

**"Untouched" (proposed definition — owner to confirm):** `status = 'open'`, never changed (`row_version` = creation version), no evidence, no exceptions ever raised, no remarks, owner still equals the master's default (or null), `period_start >= new.effective_from`. Anything else is *actioned* → pinned, and listed in a **reconciliation report** (count + ids) so a person decides.

**Mechanism:**
* new terminal status `superseded` (category cancelled) in `status_definition`; reachable only through the reconcile function (guard by a transaction flag, like evidence replacement) — not by the UI;
* `compliance_instance` gains `superseded_by_id`, `superseded_at`, `supersede_reason`; the idempotency key becomes **unique among non-superseded rows** (`create unique index … where status <> 'superseded'`, replacing the full unique constraint), so a replacement for the same period is legal and duplicates remain impossible;
* `app.reconcile_future_obligations(compliance_id)`: in one transaction, for each untouched future obligation → mark `superseded` (reason "rule v{n} effective {date}"), insert the replacement under the new version with a new `CMP-` number and `source='generated'`, link both ways; returns counts `{superseded, created, pinned_actioned}`; **idempotent** (a second call finds nothing untouched under the old version);
* called automatically at the end of `compliance_activate_rule_version()` (same transaction, same actor) and available to the job runner; every row change is audited (audit_log) and the activation reason is propagated;
* superseded obligations are excluded from registers' default view (filter chip "include superseded"), dashboard totals, calendar, alerts and exception detection; open exceptions on them auto-resolve with "Obligation superseded by rule change";
* applicability changes use the same function (an obligation that is no longer applicable is superseded instead of orphaned) — flagged as a follow-on, not in the first cut.
**Tests (CI):** v1 → v2 mid-horizon: future untouched replaced once, history retained and linked; completed/in-progress/evidenced pinned and reported; second activation/second call is a no-op; concurrent calls produce no duplicates; dashboard/alerts/exceptions ignore superseded; audit rows exist for every change; unique index prevents two live obligations per (compliance, location, period).

## 4. Provisionally accepted UAT defaults (not BFCL policy; must become frontend-configurable)
Reminders T-7/T-3/T0/D+1 · escalation D+3/D+7 · due-soon 7 days · licence thresholds 90/60/30/15/7 · overdue grace 0 · mandatory reason for Reopen / Not applicable / Waive · generator horizon 60 days · Plant HR may mark compliance **Completed**; evidence verification stays a separate permission (`evidence.verify`, Head HR). All are already stored as configuration (no code change to alter); the **admin screens** that make them editable from the web app are in the master-data/configuration increment (alert/exception/threshold configuration, role-permission editor, status-transition editor).

## 5. Order of work after the gate
1. Capture gate + UAT baseline; hash-lock 0014–0022.
2. Migration 0023 (D-001 UNROUTABLE + System Health), 0024 (F-1 scope), 0025 (F-2 supersession) — each with tests, each deployed and live-gated separately.
3. Notification centre (G-001) alongside 0023.
4. Master-data/configuration UI, then the generic import framework.
