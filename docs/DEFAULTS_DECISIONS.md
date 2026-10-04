# Seeded defaults — owner decision register (D-023 and related)

> **Owner decisions recorded 2026-10-03** (implementation deferred until the live gate + UAT baseline are captured; design: `docs/design/PHASE6_FOLLOWUPS.md`):
> * **D-001 APPROVED TO FIX** — no alert may disappear silently; no valid recipient ⇒ `UNROUTABLE` exception, visible in System Health / Super Admin. Super Admin fallback **DEVELOPMENT only**; production uses configured business escalation recipients.
> * **F-1 DECIDED** — legal/reference masters and Compliance Master globally readable by authorised HR users; **Applicability Matrix and all transactional / location-specific data scope-controlled**.
> * **F-2 DECIDED** — completed/actioned obligations stay pinned to their original rule version; future *untouched* obligations on/after a new rule's effective date are reconciled (superseded) to the new rule with full audit history and no duplicates.
> * **Confirmed 2026-10-03 (second message):** Location Master is globally readable (not scoped; sensitive attributes later go in a scoped extension); "untouched" = no human/business action, machine activity never counts, via a `human_touched_at` marker backed by audit; D-001 adds a Notification Centre home for UNROUTABLE records and a pre-activation validation of critical alert rules with no valid routing. See `docs/design/PHASE6_FOLLOWUPS.md` §6.
> * **Provisionally accepted for UAT only (development defaults, not BFCL policy, must stay frontend-configurable):** reminders T-7/T-3/T0/D+1 · escalation D+3/D+7 · due-soon 7 days · licence thresholds 90/60/30/15/7 · overdue grace 0 · mandatory reason for Reopen / Not applicable / Waive · generator horizon 60 days · Plant HR may mark compliance Completed (evidence verification stays separately permissioned).

**These are DEVELOPMENT defaults chosen by the engineering team to make the system work. None is BFCL policy, and none is a legal requirement.**
Each row states what is configured today, where, what it changes for the business, whether an administrator can change it from the web app *today*, and the decision the BFCL owner needs to make.
"Web-configurable today" = **No** means the value is stored as editable configuration (no code change, versioned where noted) but there is no admin screen yet — it is changed with SQL by an administrator until the Phase-4 designers/ master-data UI are built (next product increment).
Record the decision in the last column; engineering then applies it through the versioned configuration (not code) and logs it in `docs/DECISIONS.md`.

## A. Alert timing and routing
| # | Default now | Where configured | Business effect | Web-configurable today | Owner decision needed | **Decision** |
|---|---|---|---|---|---|---|
| A1 | Compliance reminders to the **owner** at **T-7, T-3, due day, D+1** (in-app + email) | `config_definition` kind `alert_rule`, code `DEFAULT_COMPLIANCE_ALERT`; per-obligation override via the rule version's `alert_rule_code`; new version via `config_new_version()` | When people are nagged; too many = ignored, too few = missed deadlines | No (SQL; designer UI planned) | Confirm offsets; decide whether critical obligations need earlier/more reminders (per-compliance override) | **UAT-provisional: T-7/T-3/T0/D+1 accepted** (not final policy) |
| A2 | Escalation to **Head HR** at **D+3, D+7** | `DEFAULT_COMPLIANCE_ESCALATION` | Who is told when something stays overdue | No | Confirm days and recipients (add HOD / Plant HR / named user?) | **UAT-provisional: D+3/D+7 accepted** |
| A3 | Licence alerts to **owner + Head HR** at **T-90, 60, 30, 15, 7, due, D+1** | `DEFAULT_LICENCE_ALERT` | Renewal lead time for registrations | No | Confirm per licence class (some need longer lead) | |
| A4 | Catch-up window **3 days**: a missed night still sends the most recent reached reminder | `system_config` `alert.catchup_days` | How late an alert may arrive after an outage | No | Usually keep | |
| A5 | **Email channel** is in the rules but **never created** while Gmail is `NOT_CONFIGURED` | `system_config` `integration.gmail` | No email until the mail integration is connected; no backlog blast afterwards | No | Approve go-live approach for email | |

## B. Thresholds
| # | Default now | Where configured | Business effect | Web-configurable today | Owner decision needed | **Decision** |
|---|---|---|---|---|---|---|
| B1 | **Due soon = within 7 days** | `system_config` `compliance.due_soon_days` | Amber "Due soon" badge, dashboard tile, calendar colour | No | Confirm 7 (or e.g. 10/15) | **UAT-provisional: 7 days accepted** |
| B2 | **Licence expiry buckets 90 / 60 / 30 / 15 / 7 days** | `system_config` `licence.expiry_thresholds` | Expiry categories, colours and dashboard licence bars | No | Confirm buckets | **UAT-provisional: 90/60/30/15/7 accepted** |
| B3 | **Renewal window = 60 days** before expiry (per licence; per-type default) | column default `licence.renewal_lead_days`, `licence_type.default_renewal_lead_days` | When a licence enters "renewal window" and raises a *licence expiring* exception | Per record only (no screen yet) | Set lead time per licence type | |
| B4 | **Generator horizon 60 days ahead, look-back 0** | `system_config` `compliance.generation_horizon_days`, `…_lookback_days` | How far ahead obligations appear in the calendar; history comes from import | No | Confirm horizon | **UAT-provisional: 60 days accepted** |
| B5 | **Financial vs calendar year**: new rule versions default to **calendar year** (`period_start_month = 1`) | rule-version column (set per rule) | Quarterly/half-yearly/annual period boundaries | Per rule (no screen yet) | Confirm which obligations follow Apr–Mar | |
| B6 | Evidence files: **PDF/JPEG/PNG, 25 MB** | `document_type.allowed_mime_types`, `max_size_mb` | What can be uploaded as evidence | Per document type (no screen yet) | Add Excel/Word? size limit? | |

## C. Exceptions
| # | Default now | Where configured | Business effect | Web-configurable today | Owner decision needed | **Decision** |
|---|---|---|---|---|---|---|
| C1 | **Severity = the rule version's risk level** for overdue and evidence exceptions | rule version `risk_level` (LOV `RISK`) | How urgent an exception looks and the resolution target | Risk per rule: no screen yet | Assign risk to every compliance (this is business content) | |
| C2 | Expired licence → **critical** if licence risk is high/critical, else **high**; expiring licence → licence risk (else **medium**) | logic in `app.detect_exceptions()` (code) | Severity of licence exceptions | **Yes (configuration)** | Confirm, or move to a rule table | |
| C3 | **Resolution target days: critical 1, high 3, medium 7, low 14** | `system_config` `exception.target_days` | "Target breached" flag and ageing | No | Confirm SLA days (later formalised in the SLA Designer) | |
| C4 | **Overdue grace = 0 days** | `system_config` `exception.overdue_grace_days` | An obligation raises an exception the day after its due date | No | Any grace period? | **UAT-provisional: 0 accepted** |
| C5 | Missing-evidence exception when the due date has passed **or** the obligation is completed without the mandatory document | logic in `app.detect_exceptions()` | Completed-but-undocumented work is flagged | **Yes (configuration)** | Confirm this rule | |
| C6 | Status changes needing a **mandatory reason**: reopen (compliance & exception), mark *not applicable*, *waive* an exception | `status_transition.requires_reason` | Audit quality of corrections | No (Status Designer planned) | Confirm which transitions need reasons | **UAT-provisional: mandatory reason for Reopen / Not applicable / Waive accepted** |

## D. Roles and permissions (seeded)
| Role | Seeded permissions | Business effect | Web-configurable today | Owner decision |
|---|---|---|---|---|
| **SUPER_ADMIN** | all 24 | Full configuration, users, roles, audit, jobs, exports | **Yes** — Roles & Permissions screen (migration 0033); the last `role.admin` holder cannot be removed | Limit to a very small group |
| **HEAD_HR** | master.read/write, config.read, audit.read, user.read, health.read, job.read, compliance.read/write/**manage**, licence.read/write, evidence.read/write/**verify**, exception.read/write | Manages compliance master & applicability, verifies evidence. **Cannot** change settings (`config.write`), users (`user.admin`), roles (`role.admin`), jobs; also holds `report.export` | **Yes** (Roles & Permissions) | Should Head HR manage the compliance master and verify evidence? |
| **PLANT_HR** | master.read, config.read, compliance.read/write, licence.read/write, evidence.read/write, exception.read/write | Updates status, uploads evidence, handles exceptions **within assigned scope**; cannot verify evidence or edit the master | **Yes** | Can Plant HR mark obligations *completed*? Who verifies? |
| **HOD** | master.read, compliance/licence/evidence/exception **read** | View-only | **Yes** | Confirm HOD scope: department scope **is now enforced** (an obligation's department = its master's responsible department; D-038) |
| **VIEWER** | same as HOD | View-only | **Yes** | Confirm |
**Important:** every role is also limited by **entity/location scope** — a user with *no* scope sees *nothing* (fail-closed). Scope is assigned per user (`user_scope`), or `scope_all`. Decide who gets all-location access.

## E. Fallback owner and escalation behaviour
| # | Default now | Where | Business effect | Web-configurable today | Owner decision needed | **Decision** |
|---|---|---|---|---|---|---|
| E1 | Obligation owner = the compliance master's **default owner**, copied at generation (blank if none) | `compliance_master.default_owner_user_id` | Who is accountable and who is alerted | Owner on an instance: API allows, **no screen yet** | Name a default owner for every compliance | |
| E2 | **No owner, or inactive owner → alerts go to active Head HR users who are in scope** | alert rule `OWNER_FALLBACK` (configuration, migration 0034; seeded `role:HEAD_HR`) | Prevents silent obligations when ownership is missing | **Yes** — Alert Rules → Owner fallback | Confirm fallback = Head HR; or name other roles/users | |
| E3 | ⚠ **Known defect D-001:** if there is *no* owner **and** no active Head HR user in scope, the alert is **dropped without any warning** | same | Alerts can vanish silently (e.g. the dev project today has only a Super Admin) | — | Approve fixing it (proposed: fall back to Super Admin, count and surface unroutable alerts as an exception + job warning) | **APPROVED — amended:** UNROUTABLE exception/notification visible in System Health & Super Admin; Super Admin fallback **DEVELOPMENT only**; production uses configured business escalation recipients. Design: PHASE6_FOLLOWUPS §1 |
| E4 | Exceptions inherit the obligation's owner; unowned exceptions are visible to all with `exception.read` in scope | `app.detect_exceptions()` | Who must act on an exception | Owner editable via API; **no screen yet** | Assign owners at least by location | |
| E5 | Escalation is **time-based only** (D+3, D+7); there is no hierarchy lookup (HOD / manager) | alert rules | Reaches Head HR regardless of org chart | No | Is a department-head chain required? (needs employee master) | |

## F. Read visibility of configuration data across scope (found by the scope check)
| # | Default now | Where | Business effect | Web-configurable | Owner decision needed | **Decision** |
|---|---|---|---|---|---|---|
| F1 | **Locations, compliance masters/rule versions, and the applicability matrix are readable by every user holding `master.read` / `compliance.read`, regardless of entity/location scope.** Only *transactional* data (obligations, exceptions, licences, evidence, notifications, calendar, dashboard) is scope-limited. Consequence: `compliance_coverage()` shows a single-location user which obligations apply (or are unmapped) at *other* locations — never dates, evidence or people | RLS policies (D-020); location select policy | A Plant HR can see that another site exists and which obligations are mapped to it | No | **Accept** (simplest, needed for pick-lists) **or** restrict applicability/coverage reads to the user's scope (needs a reviewed migration) | **DECIDED:** compliance master & legal/reference masters globally readable to authorised HR users; **Applicability Matrix and location-specific/transactional data scope-controlled** (location master treated as location-specific — please confirm). Design: §2 |
| F2 | **A rule-version change applies to periods generated *afterwards*.** Obligations already generated for future periods keep the version they were created under (history is never rewritten) | generator design (D-021) | If a due day changes, obligations already created for the next ~60 days still show the old due date until someone acts | No | **Accept**, or add a controlled "regenerate not-yet-started future obligations" action | **DECIDED:** pinned if completed/actioned; **future untouched obligations are superseded to the new rule** with audit and no duplicates. Definition of "untouched" proposed in §3 — please confirm |
| F3 | Alert/exception **owner is a single user per obligation**; no department-head or deputy chain | data model | Unavailable owners require manual reassignment | No | Needed before go-live? (depends on employee master) | |

## Decision process
1. Owner fills the **Decision** column (or "keep default").
2. Engineering applies each decision as versioned configuration (`config_new_version`, `system_config`, `role_permission`) — no code change except C2, C5, E2/E3 which are logic and need a reviewed migration.
3. The resulting values are recorded in `docs/DECISIONS.md` as BFCL-approved policy, replacing the "development default" label.
