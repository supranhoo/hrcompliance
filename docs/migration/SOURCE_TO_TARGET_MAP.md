# Source-to-target map (Phase 3 — design only; nothing imported, no migration, no schema change)

**Status:** formal field-level map for the five BFCL source workbooks. Supersedes the earlier provisional version. Target names are **design-level concepts**, not existing tables/columns unless marked *(exists)*. Nothing here is implemented.
**Privacy:** no raw values or personal data — only workbook / sheet / column / Excel-row references, counts and rules. Traceability for every future import row: `workbook name + SHA-256 → sheet → Excel row → column → original value` (kept in the existing `import_row.raw`, plus a `source_ref` on the target record).

## Legend
| Workbook | File | SHA-256 (first 12) |
|---|---|---|
| W1 | `Contractor_MP_cost_01092026_1_1.xlsx` | `0d9e2a1b3774` |
| W2 | `Liaison_with_ESIC.xlsx` | `b97872f68c00` |
| W3 | `GRC_Register_Final_31082026_JB.xlsx` | `1c406daac51c` |
| W4 | `Liaisoning_with_Govt_Officials.xlsx` | `0e4cfd9f4264` |
| W5 | `Daily_Plant_Visit.xlsx` | `fa01bd76a7d5` |

**Class:** ORD = ordinary business data · PER = personal data · SEN = sensitive personal/medical data · COM = confidential commercial data. (Free text is classed PER because it can carry names.)
**Import eligibility:** **YES** = no open owner decision for this field (eligible once its target module exists and is approved) · **BLOCKED** = an owner ruling is required (ID in the *Issue* column; OC-nn are Phase 1 register items) · **NO** = not to be imported (derived, trace-only, decorative, superseded).
**Mand.** = mandatory in the proposed target. **Src key** = business key in the source. **App key** = proposed application key. **Lookup** = master/LOV the value must resolve to.
Existing platform objects reused only where semantics fit: `department`, `location`, `entity`, `authority`, `designation`, `business_unit`, `unit`, `status_definition`/`status_transition`, `numbering_rule`, `audit_log`, `field_role_access`, `import_*`, `module_definition` (all *(exist)*).

---
## 1. W3 `29052026` — GRC complaints register → **GRC module** (`grievance_case`, `grievance_action`)
Source rows: 3–144 (142 records) + stray record at 387; rows 145–385 are formula-only placeholders and row 386 is a blank (all **NO**). Header row 2; title row 1; `K1 = TODAY()`.

| Col | Source meaning | Type | Class | Target field (concept) | Transformation | Validation | Lookup | Mand. | Src key | App key | Issue / decision | Import |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Serial number in sheet | int (137 formula, 6 hard-coded) | ORD | trace only (`source_serial`) | none | sheet-local; dup on 2 rows | – | no | no | no | OC-13 (Sl 140 twice) | NO |
| B | Registration number `BFCL/GRC/NNNN/FY` | text | ORD | `grievance_case.legacy_registration_no` (+ app `case_no`) | trim | regex with consecutive FY; unique in file; unique in DB once ruled | `numbering_rule` GRC *(exists; yearly reset, width 6)* | yes | **yes** | `case_no` (generated) ; legacy no. kept | OC-13 (0140 ×2: rows 142, 387), OC-14 (0123 ×2: rows 125–126; malformed FY row 107); numbering format/reset differs from source (source runs 0001–0142 across two FYs) | BLOCKED (5 rows) / YES (rest) |
| C | Date grievance received/registered | date (140) / text (3: rows 47, 48, 55) | ORD | `received_on` | ISO; unambiguous text dates (rows 47, 48) normalised; row 55 (multi-date) not | not null, ≤ today, ≤ `closed_on` | – | yes | no | – | OC-15; meaning of the "(Repeated grievance)" annotation | YES (139) / BLOCKED (row 55; annotation rows pending OC-15) |
| D | Name of employee, or a group description | text | PER | `complainant_label` (restricted field) | trim/collapse | not blank (1 blank = stray row) | future `employee` | yes | no | – | OC-12 (contractor vs employee), OC-18 (group vs person) | BLOCKED |
| E | Employee id as keyed | text/int | PER | `employee_ref_raw` (preserved text) → later `employee_id` | none (never split) | class NUMERIC_SINGLE 49 / MISSING 86 / MULTIPLE 7 / NON-ID text 1 | future `employee` (**no master exists**) | no | no | – | OC-18 | BLOCKED (94 rows pending policy) / YES (49 as raw text) |
| F | Designation or employee category (mixed) | text | ORD | `complainant_designation_text` → `designation` *(exists)* or category LOV | trim | – | `designation` | no | no | – | OC-19 (58 variants; categories vs titles; typos) | BLOCKED |
| G | Department / plant-unit (mixed) | text | ORD | `department_id` and/or unit/location candidate | trim | resolves to master | `department` *(exists)*; `unit`/`location` candidates | no | no | – | OC-01 (GFA/HASP), OC-19 (41 spellings) | BLOCKED |
| H | Nature of grievance (free text) | text | PER | `grievance_case.description` | whitespace only | not blank | – | yes | no | – | OC-27; **no category column in source** | YES (structure) – content withheld from DEV |
| I | Responsibility (person / department / contractor / committee) | text | PER | `responsible_text` → later owner user / department / contractor ref | trim | – | `app_user`, `department`, future `contractor` | no | no | – | OC-19, OC-12 | BLOCKED |
| J | Action taken | text | PER | `grievance_action` (first action) / `resolution_note` | whitespace only | – | – | no | no | – | – | YES (content withheld from DEV) |
| K | Closed on | date | ORD | `closed_on` | ISO | ≥ received; present when status Closed | – | cond. | no | – | – | YES |
| L | Present status (Open/Closed; 3 spellings) | text | ORD | `status` (LOV) | canonical `Closed`; original kept | in `status_definition` module `grievance`; transitions | `status_definition` *(exists; no grievance rows yet)* | yes | no | – | OC-16 (full list/meaning) | BLOCKED |
| M | Remarks | text | PER | `closure_remarks` | whitespace only | – | – | no | no | – | – | YES (content withheld from DEV) |
| N | TAT (calendar days; open items depend on `TODAY()`) | int (formula) | ORD | **not stored** — derived `age_days` / SLA | recompute from dates | reconcile only | SLA definition (`config_definition`) | – | no | – | OC-17 | NO |
| O | Unnamed note (row 387 only) | text | PER | none | – | – | – | – | – | – | stray row | NO |

W3 `Sheet1` (3 rows) = exact duplicates of main-sheet rows 101, 104, 108 → **NO**. `Sheet2`, `Sheet3` empty → **NO**.
**Explicit mapping exceptions kept open:** duplicate registrations (rows 125/126 and 142/387), malformed registration (row 107), missing employee IDs (86), multiple IDs (7), non-ID text in the ID column (1), employee-vs-contractor identity (OC-12), stray row 387, text/ambiguous date row 55.

---
## 2. W1 `Mar 2026` — contractor manpower cost / bill register → **Contractor Cost register** (not Contractor Compliance)
Rows 2–690: 687 non-empty = 685 dated + 2 undated (166, 173 → **NO**, rejected for lack of Month). Consolidated working source per owner ruling; classification per row: `DATA` / `PLACEHOLDER_NO_WORK` (194) / `CONFLICTING_NOTE_WITH_AMOUNTS` (16: rows 316, 317, 361, 362, 409, 410, 458, 459, 512, 513, 566, 567, 621, 622, 678, 679).

| Col | Source meaning | Type | Class | Target field (concept) | Transformation | Validation | Lookup | Mand. | Src key | App key | Issue / decision | Import |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Month | date (1st of month) | ORD | `period_month` | ISO | not null | – | yes | part of line identity | – | – | YES |
| B | Contractor name incl. trailing `(n)` | text | COM | `contractor_id` (via future contractor master) + `contractor_name_as_found` | none — `(n)` kept exactly | resolves to contractor master | future `contractor` (**no master**) | yes | no | – | OC-02 (`(n)`), OC-03 (2 spelling pairs; 64 strings / 22 candidate groups) | BLOCKED |
| C | "Dept" (early rows = work description; later = department) | text | ORD | `department_text` → `department` | trim | – | `department` *(exists)* | no | no | – | OC-10 (column roles differ before/after Aug 2025) | BLOCKED |
| D | Nature of work | text | ORD | `nature_of_work_text` | trim | – | LOV (new) | no | no | – | OC-10 (blank in May–Jul 2025 rows) | BLOCKED |
| E | Cost centre | text | ORD | `cost_centre_text` → cost-centre LOV | trim | – | cost-centre list (**not provided**) | no | no | – | OC-10 | BLOCKED |
| F | LS / PR | code (LS 366, PR 319) | ORD | `engagement_type_code` | none | in {LS, PR} | LOV (new) | yes | no | – | OC-05 (meaning) | BLOCKED |
| G | Unit (GFA / HASP / Common) | text | ORD | unit/location **candidate** (`unit` / `location` / `business_unit` *(exist)*) | none — not inferred | resolves to master | `unit`, `location` | yes | no | – | **OC-01** | BLOCKED |
| H | Bill No. (also holds notes: 210 placeholder-type) | text/int | COM | `bill_no_text` + `bill_note_category` | none | not unique (27 repeated values on dated rows; 33 rows repeat within a contractor key) | – | no | candidate (month+contractor+work area+bill no.) fails | none until policy | OC-07, repeated-bill policy; 16 conflicting rows | BLOCKED |
| I | Mandays | number | ORD | `mandays` | none | ≥ 0 | – | no | no | – | – | YES |
| J, K, L | Wages, PF, ESI | amount | COM | `wages`, `pf_amount`, `esi_amount` | none (223 hand-typed-number formulas, PF rate 12/13 %) | ≥ 0 | – | no | no | – | OC-09 | YES (except May-2025 rows) |
| M | Bill amount | amount (1 text number converted) | COM | `bill_amount` | grouped-digit text → number | ≥ 0 | – | no | no | – | May-2025 conflict (OC-04) | BLOCKED (22 May rows) / YES (rest) |
| N | Performance incentive | amount | COM | `performance_incentive` | none | ≥ 0 | – | no | no | – | – | YES |
| O | Bonus | – (blank in all rows) | COM | none | – | – | – | – | – | – | OC-09 | NO |
| P | Production incentive | amount | COM | `production_incentive` | none | – | – | no | no | – | value in all 22 May-2025 rows looks column-shifted (OC-04) | BLOCKED (22 rows) / YES |
| Q | Total cost excl. GST | amount (hard-coded in 481 of 490) | COM | `total_cost_excl_gst` | none | reconcile to components only as information | – | no | no | – | row 9 conflicts with hidden May sheet (diff 1,882,318); OC-04 | BLOCKED (May-2025) / YES |
| R | Hold amount ("25 %") | amount | COM | `hold_amount` | none | **not recalculated** | – | no | no | – | OC-06 (28 rows ≠ 25 % of total) | BLOCKED |
| S | Other hold / deduction | amount / text | COM | `other_hold_or_deduction` | none | 1 text value left blank | – | no | no | – | OC-06 | BLOCKED |
| T | Hold release month | date / text | COM | `hold_release_month` | ISO or raw text kept | – | – | no | no | – | OC-06 (usually earlier than bill month) | BLOCKED |
| U | Remarks | text | COM | `remarks` | whitespace | – | – | no | no | – | – | YES (withheld from DEV) |

Hidden sheets `May 2025`…`Sept 2025` → **NO** (reconciliation reference only; June–Sept reconcile exactly, May differs). Row classes: `PLACEHOLDER_NO_WORK` rows — keep as zero-activity candidates only after OC-08; `CONFLICTING_NOTE_WITH_AMOUNTS` — never dropped, owner review.

---
## 3. W2 `Sheet1` — ESIC liaison → **Liaison register (ESIC category)** + optional restricted extension
Rows 3–20 (18). Title row 1, header row 2.

| Col | Source meaning | Type | Class | Target field (concept) | Transformation | Validation | Lookup | Mand. | Src key | App key | Issue / decision | Import |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Serial | int (hard) | ORD | trace only | none | sequential | – | no | sheet-local | no | – | NO |
| B | Information received on | date | ORD | `liaison_record.interaction_date` | ISO | not null | – | yes | no | – | – | YES |
| C | Particulars (narrative incl. names, medical info, one insurance-number-like token) | text | **SEN** | **not in the general table** (see design: external evidence / restricted extension / not stored) | whitespace only | – | – | no | no | – | OC-21 | BLOCKED (not prepared for DEV) |
| D | Work completed on | date | ORD | `completed_on` | ISO | ≥ interaction date | – | no | no | – | – | YES |
| E | TAT (formula) | int | ORD | derived, not stored | recompute | reconcile only | – | – | – | – | – | NO |
| – | *(absent)* | – | – | authority/office, subject/category, status, owner, evidence | – | – | `authority` *(exists)* | – | – | – | no source column | – |

## 4. W4 `Sheet1` — Government liaison → **Liaison register (generic)**
Rows 3–59 (57). Merged title A1:D1; Excel table `Table13456` A2:D59.

| Col | Source meaning | Type | Class | Target field (concept) | Transformation | Validation | Lookup | Mand. | Src key | App key | Issue / decision | Import |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Serial (formula chain; row 3 hard-coded) | int | ORD | trace only | none | – | – | no | sheet-local | no | – | NO |
| B | Month (always the 1st) | date | ORD | `interaction_date` with `date_precision = month` | ISO | not null | – | yes | no | – | OC-23 (day unknown) | YES |
| C | Case detail (free text; authority named only inside text) | text | PER | `subject` / `description` | whitespace only | not blank | `authority` *(exists)* (not derivable) | yes | no | – | OC-23 (row 3 placeholder-like), OC-24, OC-27 | BLOCKED (content withheld from DEV) |
| D | Remark (36 dates, 20 outcomes, 1 blank) | date/text | PER | `outcome_text` or `completed_on` (by cell type, **not** interpreted) | split by type | – | – | no | no | – | OC-23 | BLOCKED |
| – | *(absent)* | – | – | authority_id, category, reference no., responsible person, next action, due date, status | – | – | – | – | – | – | no source column | – |

Overlap: W2 rows 8 and 10 ↔ W4 rows 25 and 28 (two events) — flagged, not merged (OC-22).

## 5. W5 `May 2026`, `July 2026`, `Aug 2026` — plant visit log → **Plant Visit → Observation → optional CAPA**
Header row 2, data from row 3 (153 rows = 123 unique dates; 30 June-2026 rows exist only as hidden rows, duplicated identically in both later sheets).

| Col | Source meaning | Type | Class | Target field (concept) | Transformation | Validation | Lookup | Mand. | Src key | App key | Issue / decision | Import |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Date | date | ORD | `plant_visit.visit_date` | ISO | one per date (dedupe June copies) | – | yes | **date** (per sheet) | `visit_date` (+ location when known) | OC-25 (June has no sheet) | YES |
| B | "Grievance received" / observation text (boilerplate "no grievance", "weekly off", "leave" or free text) | text | PER | `observation.text` (+ `entry_type_hint` for exact boilerplate) | whitespace only | – | – | no | no | – | OC-26 (purpose), OC-27 | BLOCKED (content withheld from DEV) |
| C | Remarks (10 rows) | text | PER | `observation.response_note` (not a CAPA by itself) | whitespace only | – | – | no | no | – | OC-26 | BLOCKED |
| title | Sheet title in A1 (differs by sheet) | text | ORD | trace only | none | – | – | – | – | – | OC-26 | NO |
| – | *(absent)* | – | – | location/plant, visitor, observation category, severity, action owner/due/status | – | – | – | – | – | – | no source column | – |

## 6. Summary of import eligibility (field level)
Fields YES today (structure only): dates (`received_on`, `closed_on`, `period_month`, `visit_date`, liaison dates), mandays and most cost amounts outside the May-2025 rows, free-text fields (content withheld from DEV). Everything keyed to a master or governed by a ruling is **BLOCKED**; derived/trace/decorative columns are **NO**. No source column exists for: GRC category, SLA target, contractor code/licence, liaison authority/category/status/owner, plant-visit location/CAPA fields, employee master data.
