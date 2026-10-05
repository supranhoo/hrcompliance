# GRC (Grievance) module — V1 build-ready specification (Phase 4; design only)

**Status:** specification for owner approval. **No code, migration, UI or import is created by this document.** Migrations 0001–0039 stay frozen; migration numbers below are conceptual. Source mapping: `docs/migration/SOURCE_TO_TARGET_MAP.md` §1; decisions: `docs/OWNER_DECISION_PACK_PHASE4.md` (GRC-nn, ORG-nn). Approved: GRC is a **standalone transactional module, not `exception`**. No personal data in this document.
Platform facts used (checked): numbering engine `app.next_business_id(key, date)` → `KEY-YYYY-NNNNNN` (rule `reset_policy` yearly|never, pad width; key = 2–6 capital letters; rule `GRC` is seeded yearly, width 6); `app.assign_business_id` insert trigger pattern; `status_definition` + `status_transition` per module; `lov_set/lov_value`; `config_definition` (versioned, status, jsonb) for SLA-type rules; `audit_row`/`audit_immutable`; permissions via `app.has_permission`, scope via entity/location/department with the 0039 once-per-statement pattern; `field_role_access` is **UI metadata only** (not enforced by the database) so DB-level restriction of personal fields needs a separate table; `notification` is compliance-only; there is **no file-upload mechanism yet** (Google Drive `NOT_CONFIGURED`, evidence upload disabled).

## GRC V1 Specification
### Lifecycle (proposed — owner approves the final list, GRC-01)
`RECEIVED → ASSIGNED → IN_PROGRESS → RESOLVED → CLOSED`, plus controlled `REOPENED`. No other status is added without a business need (withdrawn/duplicate would be a *closure outcome*, not a status — GRC-14).
| From → To | Permission | Mandatory on transition |
|---|---|---|
| (create) → RECEIVED | `grievance.create` | received date, entity, description, complainant type |
| RECEIVED → ASSIGNED | `grievance.assign` | owner user (and responsible department) |
| ASSIGNED → IN_PROGRESS | `grievance.update` (owner or manager) | – |
| IN_PROGRESS → RESOLVED | `grievance.resolve` | resolution text, resolved date |
| RESOLVED → CLOSED | `grievance.close` | closure date (note; acknowledgement per GRC-13) |
| CLOSED/RESOLVED → REOPENED | `grievance.reopen` | **reopen reason** (mandatory) |
| REOPENED → ASSIGNED / IN_PROGRESS | `grievance.assign` / `grievance.update` | – |
Rules: transitions are enforced by `status_transition` rows and a table trigger (not only by the screen); a closed case is immutable except by reopen; every transition appends an action; legacy records are loaded directly into their historical status through the import path only, with reason `Import IMP-…` (the dated history is preserved).

### GRC record (`grievance_case`) — field list
| Field | Type / rule | Source / note |
|---|---|---|
| `id`, stamps, `row_version` | standard | – |
| `case_no` | text, unique, generated (option B) | new cases |
| `legacy_registration_no` | text, unique where not null, **immutable**, as found after trim | W3 col B; never renumbered |
| `legacy_registration_raw` | text | exactly as found (kept for held/ruled records) |
| `received_on` | date, not null, ≤ today | W3 col C |
| `entity_id` | FK `entity`, not null | scope (ORG-01) |
| `location_id`, `unit_id` | FK `location`, FK `unit`, nullable | unresolved until ORG-02 |
| `department_id` | FK `department` (responsible department), nullable | W3 col G after mapping; scope axis |
| `complainant_type` | LOV: employee / contract_worker / group / other | W3 D/F (GRC-07) |
| `category_id` | FK `lov_value` of set `GRC_CATEGORY`, nullable | **no source column**; list empty until GRC-04 |
| `description` | text, not null | W3 col H |
| `owner_user_id` | FK `app_user`, nullable until assigned | W3 col I is text only |
| `responsible_text` | text | W3 col I as found (legacy) |
| `priority` | **not in V1** (GRC-06) | – |
| `target_due_on` | date, nullable, derived from the approved SLA rule; null = "no SLA configured" | GRC-05 |
| `status` | text, from `status_definition` module `grievance` | W3 col L (canonical) |
| `resolution_note`, `resolved_on` | text, date | W3 col J/M, K |
| `closed_on`, `closure_note`, `closure_outcome` | date, text, LOV (optional, GRC-14) | W3 col K |
| `reopen_count` | int | – |
| `confidentiality` | `standard` / `restricted` (GRC-15) | – |
| `source_ref` | jsonb: workbook, SHA-256 prefix, sheet, Excel row, import batch | traceability |
| `custom` | jsonb | existing pattern |
### Restricted personal data (`grievance_personal`, 1:1, its own RLS)
`complainant_label` (name or group description) · `legacy_employee_ref_raw` (as keyed; **never split or interpreted**) · `employee_ref_class` (`numeric_single`, `missing`, `multiple`, `alnum_code`, `non_id_text`) · `employee_id` (nullable; **added by a later migration with its foreign key only when an Employee Master exists**). Readable only with `grievance.personal.read` (+ case visibility). This is DB-enforced separation, because `field_role_access` is UI-only.
### Employee reference migration path (no fake master)
V1: store `legacy_employee_ref_raw` + class; `employee_id` does not exist yet and the Employee Master is **not** required or created from GRC IDs. When an Employee Master exists: (1) add `employee_id` + FK (new migration); (2) run a *proposal report* — exact code match only, for class `numeric_single`; (3) owner approves the proposal; (4) audited backfill sets `employee_id` (raw value is never overwritten); (5) `multiple`/`non_id_text`/`missing` stay manual, one record at a time with a reason; (6) only then may screens prefer the employee link.
### Action history (`grievance_action`, append-only)
`case_id`, `action_type` (note, assign, status_change, escalation, resolution, reopen, closure, import), `from_status`, `to_status`, `note`, `acted_by`, `acted_at`, `reason`. No update/delete (same immutability trigger pattern as the audit log); notes follow the case's confidentiality. Legacy "Action taken" becomes the first action of type `resolution` or `note` (owner chooses, GRC-02/11).
### Attachments
Via the shared generic attachment foundation (below); linked as module `grievance`, object `grievance_case`.
### API (RPCs, invoker rights; business rules in the database)
`grievance_create`, `grievance_update_details`, `grievance_assign`, `grievance_set_status` (validates transition + permission + mandatory fields), `grievance_add_action`, `grievance_reopen`; read via `v_grievance` (excludes personal columns). All writes audited; none bypasses RLS.
### Screens (UI slice)
Register (filters, URL-synced, server-paged, export gated), case detail with action timeline, create/edit form, assign/resolve/close/reopen dialogs with reasons, attachment panel, restricted-field masking, permission-denied states, 390 px layout, axe-clean.

## GRC Numbering Decision
Historical `legacy_registration_no` (format `BFCL/GRC/NNNN/FY`, 0001–0142 running continuously across two financial years) is kept **immutable** and separate. New application cases get a generated `case_no`. Options with the existing engine:
| Option | Result | Needs | Pros / cons |
|---|---|---|---|
| **A** engine as is | `GRC-2026-000001`, resets each calendar year | nothing | simplest; resets annually (differs from the source's continuous habit); calendar-year not financial-year |
| **B (recommended)** `never` reset, counter seeded after the highest legacy number | `GRC-000143`, `GRC-000144`… continuous | one data change in the GRC migration: rule `GRC` → `reset_policy='never'` and one-time `number_counter` seed (the counter table has no API access) | existing engine unchanged; continuous like the source; cannot collide with legacy format (`BFCL/…`); seed value to be confirmed after GRC-11 |
| **C** legacy-look display | `BFCL/GRC/0143/2026-27` | a new formatting function wrapping a continuous counter; owner must confirm the financial-year rule (source evidence suggests April–March, **to be confirmed**) | familiar to users; more code, a second numbering style in the system |
Recommendation: **B**. Legacy numbers are never altered; duplicates are never auto-renumbered.

## GRC Category/SLA Proposal
The source has no category column and no SLA rule; none is invented. First-release structure (all values **empty/unapproved** until BFCL supplies them):
- **Category** — LOV set `GRC_CATEGORY` (code, label, active). Optional on a case until the list exists.
- Per-category configuration stored as a versioned `config_definition` (kind `grievance_sla`, status draft/approved): `default_department` (code), `default_owner_role`, `sla_days`, `sla_basis` (`working` | `calendar`; a working-day calendar is an owner/holiday decision), `escalation` (who is told, after how many days — reuses the alert-rule pattern).
- Behaviour with no approved rule: `target_due_on` stays null, ageing is shown without a target, nothing is flagged overdue. Only an **approved** rule version sets a target; changing a rule never rewrites closed cases.
- **No statutory SLA value is proposed** and no performance targets or RAG thresholds are created.

## Historical Exception Resolution
Default for every row: never auto-renumber, never guess an employee, never silently discard a conflicting record. "Hold" = not imported in the first load; kept in the Owner Review file until a ruling is recorded in an approved **override file**, then imported in a later batch.
| Problem type | Source rows | Import behaviour | Owner resolution needed | Outcome |
|---|---|---|---|---|
| Duplicate registration `0140/2026-27` | 142 and stray 387 (different date/content) | neither imported until ruled | which keeps 0140; the other's correct number (or "import without legacy number") | **HOLD** |
| Duplicate registration `0123/2026-27` | 125, 126 (Sl 123/124) | neither imported until ruled | correct number for the second | **HOLD** |
| Malformed registration `0105/2025-27` | 107 | not imported | the correct number | **HOLD** |
| Missing employee ID | 86 records | import; `legacy_employee_ref_raw` empty, class `missing` | approval of GRC-10 | **IMPORT WITH WARNING** (hold all if GRC-10 = no) |
| Multiple IDs in one cell | 7 records | import; raw preserved, class `multiple`, no split | GRC-10 | **IMPORT WITH WARNING** |
| ID cell holds a name/non-ID text | 1 record | import; raw in restricted field, class `non_id_text`; complainant type per owner | GRC-10, identity (OC-12) | **IMPORT WITH WARNING** (or HOLD) |
| Ambiguous multi-date record | 55 | not imported | which date is the received date | **HOLD** |
| Unambiguous text dates with annotation | 47, 48 | date normalised, annotation kept in `source_ref` | confirm meaning of "repeated grievance" | **IMPORT WITH WARNING** |
| Stray record after the placeholder block | 387 | see duplicate 0140 | – | **HOLD** (with 142) |
| Duplicated `Sheet1` rows | 3 records (Sl 99, 102, 106) | excluded: exact copies of main-sheet rows | none (evidence kept) | **REJECT as duplicate** (not data loss) |
| Formula-only / blank rows | 242 | not data | none | **REJECT (not records)** |
| `Open` status records | 4 | held until each is mapped | GRC-02 | **HOLD** |
| Blank status | row 387 | held with its record | – | **HOLD** |
Expected first-load arithmetic: 143 cleaned source records = imported + held + rejected, with held ≥ 6 (rows 125, 126, 142, 387, 107, 55) plus the 4 Open records pending GRC-02.

## GRC Permissions & Confidentiality
New permissions (added by the GRC migration; 24 → 34): `grievance.read`, `grievance.create`, `grievance.update`, `grievance.assign`, `grievance.resolve`, `grievance.close`, `grievance.reopen`, `grievance.export`, `grievance.admin`, and `grievance.personal.read` (complainant name/employee reference).
Recommended role mapping (owner approves, GRC-09; existing roles only):
| Role | Permissions |
|---|---|
| SUPER_ADMIN | all ten |
| HEAD_HR | read, create, update, assign, resolve, close, reopen, personal.read (export and admin by owner decision) |
| PLANT_HR | read, create, update, resolve, personal.read — **within scope only** |
| HOD | read (non-personal), in department scope; no personal fields |
| PLANT_WRITER, VIEWER | none |
Rules: visibility = permission **and** entity/location/department scope (department = responsible department) **and** confidentiality (`restricted` cases are visible only to the assignee, the creator and `grievance.admin`). Normal HR users do not automatically see every grievance. Personal fields live in `grievance_personal` with their own RLS (DB-enforced) in addition to UI masking. Exports exclude personal fields unless `grievance.export` **and** `grievance.personal.read`; every export is logged. The 0039 once-per-statement RLS pattern is used so performance stays flat.

## Generic Attachment Foundation
One reusable service (not a table per module). Existing `evidence` stays as is (compliance only; frozen).
- **`attachment`** — `id`, `module` (registered), `object_type`, `object_id` (uuid, validated by a trigger against the registry), `document_type_id` (existing `document_type`: MIME and size limits), `file_name`, `mime_type`, `size_bytes`, `storage_provider`, `storage_file_id`, `checksum_sha256`, `confidentiality` (`standard`/`confidential`/`restricted`), `version`, `supersedes_id`, `replace_reason`, `is_active`, `uploaded_by/at`, `remarks`, audit stamps (same version/supersede pattern as `evidence`).
- **`attachment_target`** (registry) — per module/object: parent table, read permission, write permission, parent-visibility function. Access to an attachment is decided by the **parent's** visibility + confidentiality; V1 registers `grievance` only; Liaison, Plant Visit/CAPA and Disciplinary register later without new tables.
- **`attachment_access_log`** — read/download of `confidential`/`restricted` files (who/when/which; no content).
- **Storage & upload (needs GRC-16/CORE-06):** private storage bucket; uploads/downloads only through a server function that checks permission, size/MIME and returns short-lived signed URLs; checksum recorded and verified; malware scanning is an open option. No public URLs.
- Audited, versioned (replace = new version + reason), deactivate instead of delete.

## GRC Register/Dashboard
**Register** (`v_grievance`, invoker rights, server-paged, URL-synced filters, personal columns excluded): case no., legacy no., received date, entity/location/unit, department, category, complainant type, owner, status, target date, age days. **Filters:** date period (received), location, department, category, owner, status, ageing bucket. Export: separate permission, logged.
**Dashboard** (`grievance_dashboard`, invoker rights, same scope/confidentiality rules; counts only): total received · open (not CLOSED) · resolved · closed · overdue (only where an approved target exists) · ageing buckets (0–7 / 8–30 / 31–90 / 90+ using the existing bucket convention) · by location · by department · by category. **No performance targets, no RAG thresholds.** Drill-down opens the register with the same filters; counts never reveal cases the viewer cannot see.

## GRC Import Acceptance Plan
Uses the existing Import Centre (stage → validate → review → commit); **no import happens in Phase 4**. Preconditions: GRC schema live and locked; ORG-01/02/04 answered and masters present; approved department-mapping and override files; DEV data is the pseudonymised file only (free text arrives as the withheld marker, so the DEV load tests structure, not narrative content; `description` accepts the marker in DEV).
Acceptance criteria (all must pass, evidence recorded):
1. **Counts reconcile:** 143 source records = imported + held + rejected; 242 non-record rows and 3 Sheet1 duplicates excluded and listed; per-class counts match the Phase 2 Data_Quality_Summary.
2. **Duplicates/malformed per ruling:** the 6 held rows (+ Open-pending rows) are absent from the committed batch and present in the Owner Review file; no legacy number altered; no renumbering.
3. **No unintended updates:** duplicate policy = *error*, never *update*; dry-run reports 0 updates; row counts of masters and unrelated tables are identical before/after; audit log rows = imported rows.
4. **No unresolved master reference committed:** every department/unit/entity value resolves through the approved mapping or the row is held; validation reports 0 reference errors in the commit set.
5. **DEV data pseudonymised only:** a scan of the loaded DEV data finds 0 original names/IDs (same scan as the Phase 2 privacy scan); the pseudonym key is absent from DEV, Git and CI.
6. **RLS after import:** the sanity check (as in `live_rls_authz_sanity_check.sql`, extended to grievances) shows 0 extra/0 missing rows for a scope_all user, a scoped user and a user without personal permission; personal fields are invisible without `grievance.personal.read`.
7. **Spot checks:** first 5, middle 5 and last 5 imported records by source row compared field by field with the cleaned file.
8. **Traceability:** for every record `source_ref` (workbook SHA-256 prefix, sheet, Excel row) joins to `import_row.raw` and to the cleaned file's source row; a query returns 0 orphans in either direction.
9. **Idempotency:** re-uploading the same file is refused (file hash); a second dry run changes nothing.
10. **Rollback plan agreed before commit:** forward-fix via a controlled correction batch; no deletion of audited rows.

## GRC Build Slices
Conceptual numbers; each slice is lockable: new migration(s) only (never edit 0001–0039), tests, live verification by the owner (live gate + dedicated check), then hash-lock. Live-gate constants (tables/views/permissions) are updated in the same slice.
| Slice | Scope | Depends on | DB scope | UI scope | Tests | Live verification | Acceptance | Rollback / forward-fix |
|---|---|---|---|---|---|---|---|---|
| **0040** shared attachment foundation | generic attachments + registry + access log; no GRC yet | GRC-16 (storage choice), CORE-06 | `attachment`, `attachment_target`, `attachment_access_log`, RLS dispatcher, validation trigger, audit | reusable attachment panel (list, add, replace, deactivate) | SQL suite: visibility follows parent, confidentiality, MIME/size, versioning, immutability; web tests | live check + a real upload/download with signed URL | parent-based access proven; restricted read logged | tables empty at ship → drop is safe; otherwise forward-fix migration |
| **0041** GRC schema + permissions + RLS | tables, personal table, actions, LOVs, status/transition rows, numbering change, 10 permissions + role grants, views, audit triggers | 0040, GRC-01/03/09/15, ORG-01 | as listed; counter seed | none | RLS equivalence suite (scope, confidentiality, personal), status machine, numbering (seed continuity, concurrency), live-gate counts (permissions 34) | live gate + authz sanity (extended) | no cross-scope leakage; personal fields DB-restricted | empty tables → reversible; otherwise forward-fix |
| **0042** GRC workflow/API | RPCs, SLA derivation (approved rules only), ageing view, in-app notification on assignment | 0041, GRC-05 values (may be empty) | RPCs, triggers, config kind `grievance_sla` | none | transition/permission matrix tests, mandatory-field tests, reopen rules | live workflow script (create → close → reopen) | every transition guarded in DB; audit complete | forward-fix migration |
| **0043** GRC UI | register, detail, timeline, forms, attachments, masking, URL filters | 0042 | none (or view tweaks) | full screens, 390 px, a11y | unit + browser tests incl. axe audit, permission-denied states | owner UAT checklist on DEV | UX audit clean; keyboard operable | redeploy previous web build |
| **0044** GRC import mapping | import template + custom load function (case + personal in one transaction), mapping/override files, held-row handling | 0041, ORG answers, GRC-02/10/11 | template + function (calls the same RPCs) | Import Centre template entry | dry-run suite incl. every Historical Exception row, duplicate policy, traceability | acceptance plan above on DEV (pseudonymised) | all 10 criteria | forward-fix batch; never delete audited rows |
| **0045** GRC dashboard/report/export | `grievance_dashboard`, register export, report | 0042–0043 | invoker-rights functions, `grievance.export` gating, export log | dashboard tab, export button | scope/confidentiality equivalence, CSV safety, cap | live dashboard check vs register counts | totals equal register for each scope | forward-fix migration |
Parallelism: Track A (Core rollout) is not blocked by any slice; 0040 is the only slice shared with Core (file storage).
