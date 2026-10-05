# Phase 3 — Target design for the BFCL source modules (design only)

**Scope:** conceptual design derived from the five source workbooks and the current platform (migrations 0001–0039, frozen). **Nothing is implemented:** no schema, no migration, no import, no application data change, `pg_cron` OFF. Field-level mapping is in `SOURCE_TO_TARGET_MAP.md`; open source issues in `PHASE1_SOURCE_AUDIT.md` (OC-nn) and `PHASE2_CLEANING_REPORT.md`. No personal data or raw values appear here.
Platform facts this design relies on (checked against the schema): masters `entity`, `location`, `department`, `designation`, `authority`, `business_unit`, `unit` (all empty/seeded generically); `status_definition` + `status_transition` (module-scoped; only `exception` and `compliance` have values); `numbering_rule` rows `GRC`, `LIA`, `ESIC`, `DISC`, `BILL`, `CTR` (yearly or never reset, width 6); `module_definition` rows `grievance`, `liaison`, `esic`, `plant_visit`, `contractor` ("Contractor Compliance"), `disciplinary`, `communication`; generic `audit_log` trigger; `field_definition` + `field_role_access` (field-level view/edit by role); generic import framework (rows independent, one target table per template, runs as the importing user); RLS via `app.has_permission()` + entity/location/department scope. **There is no employee table, no contractor table, and no grievance/liaison/plant-visit/cost tables or permissions yet.**

## GRC Target Design
**Decision (recommended): GRC is its own transactional module; the existing `exception` table is *not* used as the GRC record.** Evidence from the schema:
- `exception` is defined as a *detected compliance gap* with a mandatory single parent (`exception_one_parent_ck`: exactly one of compliance instance / licence / evidence), a `detection_key`, auto-resolution and `source auto|manual`. A grievance has none of these parents and is raised by a person, not detected by an engine.
- A grievance has its own life-cycle, complainant, responsible party, closure and (later) confidentiality needs; forcing it into `exception` would require loosening a frozen constraint and would mix HR-personal data into the compliance exception RLS scope.
- What *does* fit and is reused: the ageing/target pattern (`age_days`, `target_breached` view logic), `status_definition`/`status_transition` (module `grievance`), `numbering_rule` `GRC`, `audit_log` trigger, `department`/`location`/`entity` scope, `designation` master, import framework, notifications/alert-rule pattern. Optional later link: *grievance SLA breach → exception* would need a new nullable parent on `exception` (a schema change needing owner approval); **not recommended for the first release** — a SLA/ageing view on the grievance module itself is enough.

**Minimum objects** (concept):
| Object | Purpose | Source support | Gap |
|---|---|---|---|
| `grievance_case` | one grievance: `case_no` (generated), `legacy_registration_no`, `received_on`, `entity/location` scope, `department_id`, `category_id`, `description`, `complainant_kind` (employee / contract worker / group / other), `complainant_label` (restricted), `employee_ref_raw` → `employee_id` later, `contractor_ref` later, `responsible_text` → owner user/department, `status`, `closed_on`, `resolution/closure_remarks`, `source_ref` | registration no. (B), date (C), name (D), id (E), dept (G), nature (H), responsibility (I), status (L), closed on (K), remarks (M) | **category/type** (no source column), SLA target, owner as a user, entity/location (unit candidate unresolved) |
| `grievance_action` | timeline of actions/escalations (many per case) | "Action taken" (J) — one text per case | action dates/owners (absent) |
| Attachments/evidence | files supporting a case | none in source | existing `evidence` is bound to compliance instance/licence (`evidence_one_parent_ck`) → needs a generic attachment link in a future migration |
| Audit/history | who changed what | – | **reuse** `audit_log` trigger; status machine via `status_transition` |
| TAT/SLA | target and breach | TAT (N) is derived (calendar days; open items volatile) | SLA targets by category: owner decision (OC-17); stored as `config_definition` (existing SLA-in-config decision) |
Registration numbers: the source runs 0001–0142 continuously across two financial years in the form `BFCL/GRC/NNNN/FY`, whereas the existing `GRC` numbering rule resets yearly with width 6 — historical numbers are kept as `legacy_registration_no`; new numbers use the rule after the owner confirms format/reset (OC-14 + numbering decision).
**Mapping exceptions kept explicit (not resolved by design):** duplicate registrations (0140 ×2, 0123 ×2), malformed registration (row 107), missing employee IDs (86), multiple IDs (7), non-ID text in ID column (1), employee-vs-contractor identity (OC-12), stray row 387, ambiguous multi-date row 55.
**Status:** design READY FOR APPROVAL; import NEEDS OWNER DECISION (OC-13/14/16/17/18/19, category list).

## Contractor Cost Target Design
The workbook is a **manpower cost / bill / hold register** (monthly lines per contractor and work area), **not** contractor compliance. It must not be loaded into the `contractor` module ("Contractor Compliance") and must not generate compliance obligations. Proposed separate concept: **Contractor Cost register** (own module code, e.g. `contractor_cost`, owner to name).
Objects (concept): `contractor` (master — **does not exist**; minimum: legal name, optional code per the existing `CTR` numbering rule, status; PAN/GST/licence only if the owner supplies them) · `contractor_cost_line`: `period_month`, `contractor_id` (+ `contractor_name_as_found` incl. `(n)` exactly), `department`/`nature_of_work`/`cost_centre` (text → masters after rulings), `engagement_type` (LS/PR), unit/location candidate, `bill_no_text`, `bill_note_category`, `mandays`, `wages`, `pf_amount`, `esi_amount`, `bill_amount`, `performance_incentive`, `production_incentive`, `total_cost_excl_gst`, `hold_amount`, `other_hold_or_deduction`, `hold_release_month`, `remarks`, `classification` (`DATA` / `PLACEHOLDER_NO_WORK` / `CONFLICTING_NOTE_WITH_AMOUNTS`), source traceability (workbook, sheet, row). Amounts are stored **as given**; totals/holds are never recalculated by the load.
**Cannot be mapped until the owner rules** (no guess is made): `(n)` meaning (OC-02) · the two contractor spelling pairs and legal names (OC-03) · May-2025 consolidated-vs-hidden conflict and Production-Incentive shift (OC-04) · hold meaning/calculation and release month (OC-06; 28 rows ≠ 25 %) · repeated Bill No. policy (OC-07; 27 values on dated rows, 33 rows repeat within a contractor key, so the planned `UNIQUE(contractor, invoice)` cannot be enforced yet) · meaning of Dept / Cost Centre / Nature of Work early vs later (OC-10) · LS/PR (OC-05) · GFA/HASP (OC-01) · policy for the 194 `PLACEHOLDER_NO_WORK` rows (OC-08) and the 16 `CONFLICTING_NOTE_WITH_AMOUNTS` rows · currency/rates (OC-09) · confidentiality (OC-11).
Contractor *compliance* (statutory documents, requirements, scoring) needs different source data that has **not** been supplied.
**Status:** NEEDS OWNER DECISION; contractor master NEEDS ADDITIONAL SOURCE.

## ESIC Liaison Target Design
Structure only (non-sensitive): `interaction_date`, `authority/office` (absent in source), `subject/category` (absent), `action` (narrative — sensitive), `target/TAT` (derived), `completed_on`, `status` (absent), `owner` (absent), `evidence`, `source_ref`.
**Restricted data:** the ESIC insurance-person number and the medical/treatment narratives are SEN. **Recommendation:** (1) the insurance-person number is **not stored at all** in the application (claims are tracked in the ESIC portal; no business need shown); (2) narratives stay **external evidence only** in the first release (the register stores date, category, status, owner and a reference to the external document); (3) if the owner later needs the narrative in-app, add a **separately permissioned sensitive extension** (own table, own RLS, `field_role_access`, no export, read access audited, never loaded to DEV with real text). Nothing sensitive goes into the general-purpose liaison table by default.
**Status:** NEEDS OWNER DECISION (OC-21, OC-24).

## Government Liaison Target Design
**Recommendation: one generic `liaison_record` base module; ESIC is a *category* (and optional restricted extension), not a separate module.** Evidence: both logs have the same shape (date, free-text description, outcome/completion) and two events already appear in both (OC-22); ESIC entries are the subset concerning ESIC. A single register avoids double counting and keeps one numbering (`LIA`); the `ESIC` numbering rule can be left unused or used for an ESIC sub-sequence if the owner wants it.
Fields (concept): `liaison_no`, `authority_id` (existing `authority` master; **not derivable** from the source — only named inside text), `interaction_date` + `date_precision` (month-only in W4), `subject/category` (new LOV; none in source), `reference_no` (absent), `responsible` (absent), `next_action` and `due_date` (absent), `status` (absent), `description`, `outcome_text`/`completed_on` (W4 Remark split by cell type, not interpreted; W2 completion date), `evidence`, `source_refs` (array; holds both workbook rows for an overlap), `restricted_extension_ref`.
Overlap policy: one base record with both source references; never auto-merged.
**Status:** structure READY FOR APPROVAL; data NEEDS OWNER DECISION (authority list, category list, status list, owner policy).

## Plant Visit / CAPA Target Design
Relationship: **Plant Visit → Observation → optional CAPA/action**. No assumption that a visit creates a CAPA.
| Level | Concept | Source support | Missing |
|---|---|---|---|
| Visit/log | `plant_visit`: `visit_date`, location/plant, visitor, `entry_type` (observation / no grievance / weekly off / leave) | date (A), exact boilerplate phrases (61 no-grievance, 14 leave, 8 weekly-off) | location/plant, visitor, visit type |
| Observation | `plant_visit_observation`: text, category, severity, link to a grievance (optional) | free text (B; 40 days with substantive text) | category, severity |
| Action/CAPA | `capa_action`: description, owner, due date, status, closure, evidence | "Remarks" (C; 10 rows) reads like a response, not a structured action | owner, due, status, effectiveness check — **not supported by the source** |
Overlap with GRC is by date only (10 of 29 days); no key — a link would be manual/optional. June 2026 exists only as 30 hidden duplicated rows (OC-25).
**Status:** NEEDS OWNER DECISION (purpose of the log; whether CAPA is in scope).

## Master Dependencies
| Master | Exists? | Source values available? | Mapping possible? | New master needed? | Owner decision |
|---|---|---|---|---|---|
| Entity | yes (`entity`) | none (value "BFCL" appears in 3 GRC dept cells) | no | no | confirm BFCL entity structure |
| Location | yes (`location`; also `unit`, `business_unit`) | **GFA / HASP / Common** only as "Unit"/dept strings | **not inferred** — GFA/HASP stay unresolved location/unit candidates until compared with BFCL's actual structure | maybe (`unit` rows) | **OC-01** |
| Department | yes (`department`) | GRC: 41 raw strings; cost: 86 raw strings | many-to-one table needed, owner-approved | no | OC-19, OC-10 |
| Employee | **no** | IDs only (32 distinct non-blank values) inside GRC | no | **yes** (needs a source file) | OC-18, OC-28 |
| Contractor | **no** | 22 candidate base names / 64 raw strings | no (OC-02/03) | **yes** | OC-02, 03, 28 |
| Authority | yes (`authority`) | only inside free text | no automatic mapping | list to be supplied | OC-24 |
| GRC category | no | none (no column) | no | yes (LOV) | new list |
| Liaison category | no | none | no | yes (LOV) | new list |
| Visit category | no | none | no | yes (LOV) | new list |
| Status/LOV values | `status_definition` (module `grievance`, `liaison`, `plant_visit` empty) | GRC: Open, Closed; others none | GRC yes after OC-16; others no | yes | OC-16, OC-24, OC-26 |
| Designation | yes (`designation`) | 58 GRC strings (mixed with categories) | no | maybe | OC-19 |

## Privacy & Access Design
**Classes:** ordinary business — dates, status, department, registration/bill numbers; personal — names, employee IDs, free-text descriptions/actions/remarks (may contain names); sensitive personal/medical — ESIC narratives and insurance-person numbers, health-related grievance text; confidential commercial — contractor cost, wages, hold, bill amounts, contractor remarks.
**Controls (design):** module permissions per module (e.g. `grievance.read/write/manage`, `liaison.read/write`, `contractor_cost.read/write`, `plant_visit.read/write`, plus a distinct sensitive-extension permission) added by future migrations; scope via existing entity/location/department scoping; field-level hiding with the existing `field_role_access` for complainant name/ID, free text and cost fields; no export of sensitive fields unless a separate explicit permission; sensitive extension: separate table + RLS, reads audited; DEV loads use pseudonymised data and withheld free text only until the owner approves real data.
**Pseudonym key rules (binding):** `PSEUDONYM_KEY_CONFIDENTIAL.xlsx` must **never** be committed to Git, loaded into DEV, included in CI artifacts, or placed in ordinary application storage; it stays outside the repo with the owner. Recommended guard (to be added at implementation time): a CI check failing on file names matching `*PSEUDONYM_KEY*`, `*_FULL_CONFIDENTIAL*` and `data/source/**`, and a repository `.gitignore` for them. The FULL cleaned files likewise stay outside the repo.

## Import Design
All proposals use the existing import framework (staged → validated → committed; runs as the user; rows independent; ≤ 5,000 rows; templates are added by migration; multi-table imports need a dedicated function). Not implemented.
| Module | Candidate template | Business / dedupe key | Required references | Dry-run validations | Duplicate policy | Reject conditions | Traceability fields |
|---|---|---|---|---|---|---|---|
| GRC | `grievance_case` (cases) + optional actions template | `legacy_registration_no` | department/location (mapping table), status LOV, designation (optional) | regex/FY, date ≤ today, closed ≥ received, status resolves, ID class recorded | **error** on duplicate key in file or DB (no auto-fix; owner mapping applied before upload) | duplicate/malformed registration without ruling, missing date, unresolved status, text/multi dates | workbook SHA-256, sheet, Excel row, original values (`import_row.raw`) |
| Contractor cost | `contractor_cost_line` (needs contractor master first) | none reliable → composite (month + contractor + work area + bill no.) flagged non-unique; row identity = workbook+row | contractor, department/cost-centre/unit mappings | numeric ≥ 0, classification present, no recomputation, May-2025 rows held back | **warn** (not skip) on exact duplicates and repeated bill nos until policy | unresolved contractor, undated rows, unrecognised LS/PR, conflicting rows without ruling | as above + `classification`, `bill_note_category` |
| Liaison (incl. ESIC category) | `liaison_record` | none → workbook+row; overlap flagged via `source_refs` | authority (from owner list), category LOV | dates, completion ≥ interaction, precision flag | warn on overlap pair; single record | missing date, sensitive columns present | as above; **sensitive columns excluded from template** |
| Plant visit | `plant_visit` (+ observation template) | `visit_date` (+ location) | location (if known) | date unique; June copies de-duplicated | skip identical copies (evidence kept) | non-date, conflicting duplicate dates | as above incl. `source_row_hidden`, sheet name |
Each template: dry-run only until the owner approves; load into DEV only with the pseudonymised/withheld variants.

## Owner Decisions Required
1. **GFA / HASP / Common** — location, unit, business unit or department; compare with the BFCL organisation structure (OC-01). 2. Approve **GRC as a standalone module** (not exception). 3. GRC: registration format/reset, category list, status list + transitions, SLA targets, responsibility modelling, complainant model (employee / contract worker / group), employee-ID policy, duplicate/malformed registrations (OC-13/14/15/16/17/18/19). 4. Employee and contractor master sources (OC-28) and employee-vs-contractor identity (OC-12). 5. Contractor cost: module name, `(n)`, spellings, May-2025 authority, hold semantics, bill-no policy, Dept/Cost Centre/Nature roles, LS/PR, placeholder and conflicting-row policy, confidentiality (OC-02…11). 6. Liaison: single base module with ESIC as a category (recommended), authority list, category list, status list, owner; ESIC narrative handling — recommend external evidence only, insurance-person number not stored (OC-21/22/23/24). 7. Plant visit: purpose, CAPA scope, location/visitor, June 2026 source (OC-25/26). 8. Data protection: whether real personal data may ever be loaded to DEV, retention, access groups (OC-27).

## Recommended Implementation Order
Evidence supports a small change to the preferred principle: **required masters → GRC → liaison → contractor master/cost → plant visit/CAPA.**
1. **Required masters** (no source file; owner confirms organisation structure: entity/location/department/unit incl. GFA/HASP, authorities, designations, status/LOV lists).
2. **GRC** — best-structured source (142 records), needs only masters + owner decisions; employee reference can be raw text until an employee master exists.
3. **Government liaison (+ ESIC category)** — tiny (75 rows), generic, needs only authority/category/status lists; no contractor dependency.
4. **Contractor master + cost register** — blocked by ≥ 10 owner rulings and by the missing contractor master source; independent of liaison, so it can move earlier *if the owner answers OC-02…OC-11 first*.
5. **Plant visit / CAPA** — weakest source (log only; CAPA unsupported); last.
Employee master, disciplinary, communications, contractor compliance remain **NEEDS ADDITIONAL SOURCE**.

## Architecture decision report
| Area | Status |
|---|---|
| Required masters (entity, location/unit, department, authority, designation) | NEEDS MASTER DATA (organisation structure) + NEEDS OWNER DECISION (GFA/HASP) |
| GRC module | READY FOR MODULE DESIGN APPROVAL (import: NEEDS OWNER DECISION) |
| Contractor master | NEEDS ADDITIONAL SOURCE |
| Contractor cost register | NEEDS OWNER DECISION |
| Contractor compliance | NEEDS ADDITIONAL SOURCE; the cost workbook is NOT SUITABLE FOR IMPORT as compliance |
| Government liaison base | READY FOR MODULE DESIGN APPROVAL (data: NEEDS OWNER DECISION) |
| ESIC liaison | NEEDS OWNER DECISION; ESIC narratives and insurance-person numbers: NOT SUITABLE FOR IMPORT |
| Plant visit / CAPA | NEEDS OWNER DECISION |
| Employee master, disciplinary, communications | NEEDS ADDITIONAL SOURCE |

## Phase 4 Readiness
Phase 4 would be *module build planning for approved designs*, starting with the masters + GRC. Prerequisites: owner approval of the standalone-GRC design; answers to the GRC decisions (registration format, status list, categories, SLA, complainant/ID policy, duplicate rulings); confirmation of the organisation structure (GFA/HASP); decision on pseudonymised vs real data in DEV. Each build would be a new migration (never touching 0001–0039), RLS-first, with live verification before locking, and import templates only after dry-run approval. Contractor, liaison and plant-visit builds follow the order above once their decisions land.
