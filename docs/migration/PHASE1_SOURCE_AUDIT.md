# Phase 1 — BFCL source workbook inventory & audit

**Status:** Phase 1 (audit only) complete. Nothing was cleaned, imported, normalised, uploaded or changed; no migration, schema, database or `pg_cron` change. Awaiting owner approval before Phase 2.
**Date:** 2026-10-05 · **Environment:** DEV only · **Baseline:** platform frozen through migration 0039.

**Data protection note.** The workbooks contain personal data (employee, contract-worker and contractor names, employee IDs, an ESIC insurance-person number, medical-treatment narratives). This document therefore reports **aggregates and row references only** — no personal names, IDs or raw rows. The originals are not in the repository. Traceability is by `workbook → sheet → Excel row number → column letter` (row numbers are the Excel row numbers in the original files).

## 1. Workbook inventory
Originals were uploaded to the session (`/root/.claude/uploads/<session>/`). A byte-identical, read-only (mode 444) working copy was made at `/tmp/claude-0/src_orig/` (ephemeral); the uploaded originals were never opened for writing. SHA-256 of each original:

| # | Original filename | Type | Size (bytes) | Sheets | Sheet names (state) | SHA-256 |
|---|---|---|---:|---:|---|---|
| W1 | `Contractor_MP_cost_01092026_1_1.xlsx` | .xlsx (no macros, no external links, no defined names) | 244,836 | 6 | `May 2025`, `June 2025`, `July 2025`, `Aug 2025`, `Sept 2025` (all **hidden**); `Mar 2026` (visible) | `0d9e2a1b37749d28df4cd6f3b94d8bcebbe2bfd91172cbfea1361dfac75a266d` |
| W2 | `Liaison_with_ESIC.xlsx` | .xlsx | 12,538 | 1 | `Sheet1` | `b97872f68c00158b5eaf3484041ef875e8863ba5ed899e22256554622dba5623` |
| W3 | `GRC_Register_Final_31082026_JB.xlsx` | .xlsx | 56,322 | 4 | `29052026`, `Sheet1`, `Sheet2` (empty), `Sheet3` (empty) | `1c406daac51ca2e999b1aac1ab9c84e8487ebaa15e61e625f0e13f09155eebcf` |
| W4 | `Liaisoning_with_Govt_Officials.xlsx` | .xlsx | 17,791 | 1 | `Sheet1` | `0e4cfd9f42646cc882242d76552dfc4c3fbae3fd477c5e371e3c2d1b06e17195` |
| W5 | `Daily_Plant_Visit.xlsx` | .xlsx | 19,016 | 3 | `May 2026`, `July 2026`, `Aug 2026` | `fa01bd76a7d530f5fe56f094f4b10f3f3939eb5dccf29ed3a4628a24645019bc` |

Not provided (so not audited): any employee master, contractor master (list), compliance master/calendar, licence/registration register, evidence, disciplinary/case file, communications register, ESIC claim-level data, contractor *compliance* (HASP) workbook, labour-supply bill register separate from W1.

## 2. Sheet classification matrix
| Workbook / sheet | Used range | Data rows | Primary area | Also supports | Notes |
|---|---|---:|---|---|---|
| W1 `Mar 2026` | A1:CM690 (data to col U) | 685 dated rows (+2 undated) | **Contractor manpower cost / bill register** (transaction/history) | Contractor master (derive), Department & cost-centre lookup, Unit lookup, MIS/report-only | Name is misleading: holds **16 months May 2025–Aug 2026 stacked**. Not "Contractor compliance". |
| W1 `May 2025`…`Sept 2025` (hidden) | A1:T23, S29, S29, CL35, CL41 | 22, 28, 28, 34, 40 | Same register, older per-month copies | History | Hidden; June–Sept totals equal the consolidated sheet, May does not (see §4). |
| W2 `Sheet1` | A1:E20 | 18 | **ESIC liaison log** | Liaison / government interaction, GRC (medical grievances), Contractor-related | Free-text particulars; health-related personal data. |
| W3 `29052026` | A1:O387 | 143 records (rows 3–144 + stray row 387) | **GRC / grievance register** | Employee reference (IDs only), Contractor (responsibility), Department lookup | 241 pre-filled formula rows 145–385. |
| W3 `Sheet1` | A1:M4 | 3 | Duplicate extract of 3 GRC records | — | Exact copies of main-sheet rows 101, 104, 108 (all 12 shared fields equal); no Registration Number. |
| W3 `Sheet2`, `Sheet3` | A1 | 0 | Empty default sheets | — | Ignore. |
| W4 `Sheet1` | A1:D59 | 57 | **Liaison with government authorities** (monthly log) | ESIC, Employment Exchange, Labour office, Factory Inspector, bank, CSR-like activities | Excel table `Table13456`. |
| W5 `May 2026` | A1:C33 | 31 | **Plant visit / grievance observation log** (daily) | GRC feeder | Title "Tracker Towards Observation of Daily Plant Visit". |
| W5 `July 2026` | A1:C63 | 61 (30 hidden = June) | Same | — | Title says July; also contains **hidden June 1–30 rows**. |
| W5 `Aug 2026` | A1:C63 | 61 (30 hidden = June) | Same | — | Hidden June rows identical to those in `July 2026` (0 differences). No separate June sheet exists. |

No sheet is an Organisation/Entity, Location, Employee, Contractor-master, Compliance-master, Rule/frequency, Applicability, Licence, Evidence, Disciplinary or Communications master. Lookup values (Unit, Department, LS/PR, Status) exist only as free values inside the registers.

## 3. Column / data dictionary
Types are the probable business type; "stored" notes how Excel holds them. `F` = formula, `H` = hard-coded.

### W1 `Mar 2026` (header row 1; autofilter A1:U365 only; freeze pane A676 — both stale)
| Col | Header | Probable type | Notes |
|---|---|---|---|
| A | Month | date (first of month) | 685 rows; 16 distinct months 2025-05…2026-08; all stored as real dates. |
| B | Contractor | name (display) | 64 raw strings → 22 base names after dropping a `(n)` suffix (222 rows carry the suffix). |
| C | Dept | lookup/text | 86 distinct strings; 20 blank. |
| D | Nature of work | lookup/text | 62 distinct. |
| E | Cost Centre | lookup/text | 62 distinct; 6 blank. |
| F | LS/PR | code (LS 366, PR 319) | Meaning not stated. |
| G | Unit | lookup (GFA 352, HASP 332, Common 1) | Plant/unit. |
| H | Bill No. | identifier (text 307 / number 88) | Blank for the 77 rows of May–Jul 2025 (column did not exist then); also holds free-text notes ("Work not done…") in 195 rows. 27 values repeat. |
| I | Mandays | number | 455 filled. |
| J–L | Wages, PF, ESI | amount | Mix of H and F; PF/ESI often `=J×13%` / `=J×3.25%` (some 12%). 7 Wages cells are the text `.`. |
| M | Bill amount | amount | 1 text value (`38,83,582`). |
| N, O, P | Performance / Bonus / Production incentive | amount | **Bonus is blank in every row.** |
| Q | Total cost excluding GST | amount | 490 numeric. 9 formulas, rest hard-coded. |
| R | Hold amount (25%) | amount | Usually `=Q×25%`; **28 of 447 rows differ from 25 % of Q**. |
| S | Other hold amount/Deduction | amount/text | 1 text value (`2,43,600`); several formulas of typed constants. |
| T | Hold amount release month | date (first of month) | Usually one month *before* the bill month (360 rows); 2 rows are text notes, 2 are +10 months. Semantics unclear. |
| U | Remarks | free text | |
Data beyond column U: none (dimension to CM is formatting only).

### W1 hidden monthly sheets
Same business columns; `May–July 2025` have 19 columns (no Nature of work, no Bill No.); `Aug/Sept 2025` add Bill No. (merged G:S note rows: 3 and 4). Column letters differ from `Mar 2026`.

### W2 `Sheet1` (title row 1; header row 2; data rows 3–20)
`Sl.No.` (int, sequential 1–18, H) · `Information received on` (date) · `Particulars` (free text, ≤792 chars; names, one IP-number-like value, contractor references) · `Work completed on` (date) · `TAT` (days, `=D−B`, F in all 18, 0 mismatches). No ID, authority, status, category or owner column.

### W3 `29052026` (title row 1; `K1 = TODAY()`; header row 2; data rows 3–144; stray 387)
| Col | Header | Probable type | Notes |
|---|---|---|---|
| A | Sl.No. | sequence | 137 `=prev+1` formulas, 6 hard-coded. |
| B | Registration Number | identifier `BFCL/GRC/NNNN/FY` | One pattern in all 143; sequence runs 0001–0142 continuously across FY (does **not** reset in April). |
| C | Date | date | 140 dates, **3 text** (rows 47, 48: `18/10/2025 (Repeated grievance)`; row 55: three dates in one cell). Range 2025-07-01…2026-08-29. |
| D | Name of Employee | name/group description | 1 blank; many group descriptions ("Group of Workers …"). |
| E | Employee Id | reference | 86 blank, 49 numeric, 8 text (multi-ID strings such as `A, B`, `x/y`, `SK…`, and a contractor name). |
| F | Designation | text/category | 58 distinct; mixes real designations with categories (Blue/White collar, Contract Labour); typos ("While Colllar"); 13 blank. |
| G | Dept. | lookup | 41 distinct strings. |
| H | Nature of Grievances | free text | |
| I | Responsibility | text | 54 distinct: departments, named individuals, contractors, committees. |
| J | Action Taken | free text | 1 blank (stray row). |
| K | Closed on | date | 138 filled; blank for 4 Open + stray row. |
| L | Present Status | status | `Closed` 132, `Open` 4, `Closed␠` 3, `closed` 3, blank 1. |
| M | Remarks | free text | 91 filled. |
| N | TAT | days | `=K−C` (42 rows) or `=IF(K>0,K−C,$K$1−C)` (97 rows); for Open items depends on volatile `TODAY()`. 4 blank. |
| O | (no header) | note | One value, stray row 387. |

### W3 `Sheet1`
Same 12 columns minus Registration Number (Sl.No., Date, Name, Employee Id, Designation, Dept., Nature, Responsibility, Action Taken, Closed on, Status, Remarks, TAT) for Sl 99, 102, 106.

### W4 `Sheet1` (merged long title A1:D1; header row 2; table `Table13456` A2:D59)
`Sr.` (sequence; 56 formulas, row 3 hard-coded) · `Month` (date, always the 1st; 13 months 2025-09…2026-09) · `Case detail` (free text) · `Remark` (**mixed**: 36 completion dates, 20 text outcomes, 1 blank).

### W5 sheets (title row 1; header row 2)
`Date` (date, daily, no duplicates) · `Grievance Received` (free text: observations, "No grievance is observed", "Weekly Off day", leave wording, multi-item numbered text with embedded newlines) · `Remarks` (free text; filled in 9 May rows, 0 July, 1 Aug).

## 4. Data-quality audit (nothing was changed)
### W1 Contractor manpower cost
- **Contractor naming:** 64 raw strings for 22 base names; spelling variants (two spellings each of one construction contractor and one labour contractor); the `(n)` suffix meaning is undocumented; 4 values with leading/trailing spaces.
- **Duplicates:** 11 **exact duplicate rows** (one per month, same contractor + "FAD MECH" work area, rows 183/184, 222/223, 263/264, 307/308, 351/352, 399/400, 448/449, 500/501, 555/556, 610/611, 666/667) and 44 groups sharing month + contractor + dept + cost centre + bill no. 27 Bill-No values repeat.
- **Structure/placeholder rows:** 195 rows have no amounts ("Work Not done" 187 and similar notes in col H); 2 rows (166, 173) have **no Month** and are shifted/extra lines (e.g. festival-day service, a security bill).
- **Stacked sheet:** the visible sheet named `Mar 2026` contains all 16 months; the five hidden sheets are older per-month copies in a different column layout.
- **Reconciliation with the hidden monthly sheets:** June, July, Aug, Sept 2025 totals equal the consolidated sheet; **May 2025 differs by exactly 1,882,318** (consolidated row 9 `Total` = `M+N+O+P` double-counts a value that landed in the shifted Production-Incentive column). In 21 May-2025 rows the Production Incentive column equals Total (column shift from consolidation).
- **Numbers as text:** 7 Wages `.`, 1 Bill amount, 1 Other hold. **Hold ≠ 25 %** of total in 28 rows; Total > Bill in 4 rows.
- **Formulas:** 1,509 formulas; money cells 1,426 F vs 1,685 H; **223 formulas embed typed constants** (e.g. `=721+16`, `=638409`) — hand-keyed arithmetic that cannot be recalculated from other cells; PF rate varies (13 % vs 12 %) between rows/months; `Total` is hard-coded in 481 of 490 rows.
- **Errors:** no `#N/A`, `#VALUE!`, `#REF!` etc. in any sheet of any workbook.
- **Other:** `Bonus` column entirely blank; autofilter and freeze panes stale; merged note ranges inside the data (8 ranges).
- **Orphans:** Unit has 3 values; Dept (86) / Nature of work (62) / Cost Centre (62) are not governed lists and overlap in meaning (e.g. dept and cost centre often repeat each other).

### W3 GRC register
- **Duplicate / conflicting identifiers:** Registration `0140/2026-27` appears twice (row 142 and stray row 387) with **different dates, employees and content**; Sl.No. 140 repeats; Registration `0123/2026-27` appears on rows 125 and 126 (second has Sl 124); row 107 has malformed FY `2025-27`.
- **Stray content:** row 387 (a late record + a note in col O), row 386 holds a single space, rows 145–385 are 241 pre-filled TAT formulas whose cached value is **46,271** (TODAY() minus blank).
- **Dates:** 3 text dates (see dictionary); rows out of chronological order at 118 and 144.
- **Status:** `Closed`, `Closed␠`, `closed` (3 spellings, 138 rows) and `Open` (4); no other states.
- **Names/IDs:** 86 of 143 records have no employee ID (group grievances/contract labour); 4 IDs appear with spelling/format variants of the name; 8 IDs are text (multiple IDs in one cell, non-numeric codes, a contractor name in the ID column).
- **Lookups:** Dept 41 distinct strings for far fewer real departments (e.g. `GFA`, `GFA Unit`, `HASP`, `HASP Unit`, `HASP & GFA Unit`, `HASP/GFA`, `Admin`, `Admin.`, `HR`, `Human Resources`, `FAD`, `FAD Operation`, `FAD-Production`, `FAD Production`); Designation mixes categories and titles; Responsibility 54 strings (person names, departments, contractors).
- **Whitespace:** leading/trailing spaces in names (8), designation (5), responsibility (4), status (3).
- **TAT:** consistent with dates (0 mismatches on real records); Open items' TAT changes every day (`$K$1 = TODAY()`, cached 2026-09-06). Calendar days, not working days.
- **Sheet1:** 3 exact duplicates (no new information). The sheet name `29052026` does not match content (to 31/08/2026).
- **Identifier validity:** no email, mobile, GST, PAN, PF or ESIC number columns. Employee IDs: 48 six-digit numerics plus irregular values listed above.

### W2 ESIC log
No exact duplicate rows; sequence and dates consistent; TAT recomputes with 0 mismatches; 1 text cell has trailing whitespace. **Two entries (Sl 8 and 10) are also recorded in W4** (Sr 25 and 28, same opening text). Contains personal and medical information in free text; one 10-digit insurance-person-number-like token. No status/outcome column — outcome only inferable from text.

### W4 Government liaison
Sr chain consistent; Month always the 1st (day lost); `Remark` mixes dates and text; row 3 (`ER1`, "Done") looks like a placeholder/form name, not a case; 6 values with trailing spaces; 36 Remark dates all fall within or after the Month (none earlier). Includes non-compliance activities (bank salary-account camps, parents meetings, insurance claim follow-up).

### W5 Plant visit
June 2026 exists **only as 30 hidden rows duplicated identically** inside both `July 2026` and `Aug 2026`; there is no June sheet. Sheet titles differ by sheet; leave wording varies (`On authorized leave`, `…leave.`, `Authorized Leave`); "Weekly Off day" appears in July/Aug (Sundays only) but not May; 3+1+1 entries with leading/trailing spaces; 29 days with a substantive entry, of which 10 fall on days with a GRC-register record. Single free-text column mixes grievance, absence and weekly-off.

## 5. Probable keys & relationships
| Sheet | Business key | Identifier vs display vs free text | Relationships |
|---|---|---|---|
| W1 `Mar 2026` | **None reliable.** Candidate: Month + Contractor(base) + Dept/Work area + Cost Centre + Bill No. — fails on 11 exact duplicates and 27 repeated Bill Nos | ID: Bill No. (inconsistent); display: Contractor, Dept, Cost Centre, Unit; lookup: LS/PR, Unit; free: Nature of work, Remarks | Contractor → *future* contractor master; Unit/Dept/Cost Centre → department/location masters (no mapping exists); Month → period |
| W2 | Sl.No. within the sheet (no business ID) | free: Particulars | → ESIC/liaison; refers to contractors, workers, hospitals in text only |
| W3 `29052026` | **Registration Number** (unique except `0140/2026-27`, `0123/2026-27`) | ID: Registration Number, Employee Id (partially), display: Name/Designation/Dept, lookup: Status, free: Nature/Action/Remarks | Employee Id → *future* employee master (not provided); Dept → department master; Responsibility → people/dept/contractor (mixed); Date/Closed on → TAT |
| W4 | Sr. (sheet-local) | free: Case detail, Remark | Authority is only inside text (ESIC, EPF/RPFC, Factory Inspector, Labour office, Employment Exchange, Pollution Board, bank) → `authority` master could be matched later |
| W5 | **Date** (unique per sheet; June duplicated across sheets) | free: Grievance Received, Remarks | Loosely related to GRC by date |
No employee code, contractor code, entity code, location code, department code, licence/registration number or compliance code exists in any workbook. None has been invented. Cross-workbook: W2⇄W4 overlap (2 entries); one contractor name appears in W1 and in 35 GRC rows (as contractor and, apparently, as an individual with an employee-style ID — see OC-12); GRC ⇄ plant visit by date.

## 6. Preliminary source-to-module mapping (conceptual; no mapping created)
| Source | Existing platform target | Direct fields | No obvious target / gaps |
|---|---|---|---|
| W3 GRC | **No GRC module/table** (DATA_MODEL: "GRC/ESIC/disciplinary/liaison … not yet modelled"). Reusable: `department`, `location`, `lov`/status config, `exception`-style SLA/ageing engine, import framework (`import_template/batch/row`) | Date→logged date, Registration Number→case number, Dept→department (after cleaning), Status, Closed on, Action taken, Nature, Remarks, TAT (derivable) | Employee reference (no employee master), designation/category, responsibility (person/dept mixed), repeated-grievance links, group grievances |
| W1 contractor cost | **No contractor tables**. Reusable: `department`, `location`, config lists, import framework, report/export framework | Month, Unit, LS/PR, Dept/Cost Centre (lists), amounts | Contractor master (names only), bill register, hold/release semantics, cost rollups |
| W2 + W4 liaison | **No liaison module**. `authority` master exists | Date received/Month, particulars, completion date, TAT | Authority, category, status/outcome, owner, linked person/contractor, medical-privacy class |
| W5 plant visit | **No plant-visit/CAPA module** | Date, observation, remarks | Structured grievance link, action owner, CAPA fields, area/plant |
| (none) employee / compliance / licence / evidence / disciplinary / communications | Compliance/licence/evidence/exception/alert modules **exist** but no workbook feeds them | — | Source not provided |
Source→existing masters: Unit (GFA/HASP) and Dept/Cost-centre values have **no mapping** to the current `entity`/`location`/`department` masters; this requires owner confirmation (OC-01). Platform fields absent from all workbooks: entity/location codes, compliance codes, due-date rules, evidence, licence numbers/validity, roles/scopes. Potential missing modules: Contractor master & bill/cost register, Employee master, GRC register, Liaison log (government/ESIC), Plant-visit log/CAPA, Disciplinary cases, Communications.

## 7. Owner clarification register
(Never guessed; severity: B = blocks cleaning/import of that sheet, D = needed for design, I = informational.)
| ID | Sheet / ref | Question | Sev |
|---|---|---|---|
| OC-01 | W1 col G; W3 col G | What are **GFA** and **HASP** (plants/units/divisions)? Are they entities, locations, or departments of one entity? Which BFCL entity/location codes do they map to? ("Common" appears once.) | B |
| OC-02 | W1 col B | What does the `(n)` suffix on contractor names mean (bill number, worker count, serial)? Should it be kept as data? | B |
| OC-03 | W1 col B | Confirm identities of near-identical names (two spellings each of one construction and one labour contractor, plus a possible person/trading-name pair). Which spelling is legal? Are there contractor codes/PAN/GST/licence numbers? | B |
| OC-04 | W1 | Is hidden-sheet content (May–Sept 2025 monthly sheets) superseded by `Mar 2026`? Which is authoritative for **May 2025** (difference 1,882,318: row 9 formula error or intended)? | B |
| OC-05 | W1 col F | What do LS and PR stand for, and does the distinction affect cost treatment? | D |
| OC-06 | W1 cols R–T | Meaning of "Hold amount (25%)", "Other hold/Deduction" and "Hold amount release month" (mostly the month *before* the bill month). When a row has hold ≠ 25 %, which is right? | B |
| OC-07 | W1 | Are the 11 repeated "FAD MECH" rows (one per month) duplicates or two real lines? 27 repeated Bill Nos: reuse or duplicate entries? | B |
| OC-08 | W1 | Rows with "Work Not done" and no amounts (195): drop, or keep as zero-activity records? Rows 166 and 173 without Month: which month? | B |
| OC-09 | W1 | Currency/units (appear to be rupees), PF 13 % vs 12 % and ESI 3.25 %: confirm rates by period; is `Bonus` intentionally empty? | D |
| OC-10 | W1 cols C/D/E | Which of Dept, Nature of work and Cost Centre is the governing hierarchy? Provide the authoritative department and cost-centre lists. | B |
| OC-11 | W1/W3 | Is cost data confidential (access scope: HR only? finance?) | D |
| OC-12 | W3 col D/E/I | One name appears as a contractor in W1/W2/W4 text and as an individual with an employee-style ID in some GRC rows. Same party? How should contractor-related grievances reference the contractor? | B |
| OC-13 | W3 rows 142 & 387 | Two different records both numbered `BFCL/GRC/0140/2026-27` (and Sl 140): which keeps 0140, what is the correct number of the other? | B |
| OC-14 | W3 rows 125–126, 107 | Duplicate `0123/2026-27` (second has Sl 124) and malformed `0105/2025-27`: correct registration numbers? | B |
| OC-15 | W3 rows 47, 48, 55 | Text dates ("18/10/2025 (Repeated grievance)", three dates in one cell): one record each? Which date is the registration date? | B |
| OC-16 | W3 col L | Complete list and meaning of status values (only Open/Closed observed). Is "closed" = resolved, withdrawn, or both? | D |
| OC-17 | W3 col N | TAT rule: calendar days or working days; for Open items measured to today or to a fixed date; SLA targets by nature? | D |
| OC-18 | W3 col E | Empty employee ID in 86 records (group grievances, contract labour): permitted? Group records: one row or one per person? What are `SK…` codes? | B |
| OC-19 | W3 col F/G/I | Authoritative designation list; "Blue/White Collar" is a category, not a designation; department list and mappings for the 41 spellings; responsibility: person vs department vs contractor? | B |
| OC-20 | W3 `Sheet1`, rows 145–386 | Confirm `Sheet1` is a duplicate extract and the pre-filled rows are empty templates (safe to ignore). | D |
| OC-21 | W2 | Medical/ESIC treatment narratives are sensitive personal data: who may see them; retention; redact names/IP numbers on import? | B |
| OC-22 | W2/W4 | Two events appear in both logs (W2 Sl 8, 10 = W4 Sr 25, 28). Single source of truth? Should ESIC be a category of the government-liaison log? | D |
| OC-23 | W4 | `Remark` mixes dates and text: is a date the completion date? Is row 3 (`ER1`) a real case? Month-only dates: is day-level date available? | B |
| OC-24 | W2/W4 | Authority list and case categories/status required for liaison; owner/responsible person per entry? | D |
| OC-25 | W5 | June 2026 exists only as hidden duplicated rows: is there a June sheet elsewhere? Are the hidden rows meant to be part of the record? | B |
| OC-26 | W5 | Daily plant-visit tracker: is it a register of grievances, of observations/CAPA, or both? Who performs/owns it? Distinguish "no grievance" / leave / weekly-off from observations? | D |
| OC-27 | all | Historical scope (earliest date to import), retention of personal data, and whether real names may be loaded into DEV at all. | B |
| OC-28 | missing | Provide: employee master, contractor master, compliance/licence workbooks, contractor-compliance (HASP) workbook, disciplinary and communications sources, entity/location/department master lists. | B |

## 8. Module unblocking assessment
| Module | Verdict | Basis |
|---|---|---|
| Employee Master | **SOURCE NOT FOUND** | Only referential IDs inside GRC (32 distinct non-blank values); no master list. |
| Contractor Master | **PARTIALLY SUFFICIENT** | 22 contractor base names exist only inside the cost register; no code/PAN/GST/licence/contact. OC-02, OC-03 first. |
| Contractor Compliance | **SOURCE NOT FOUND** | W1 is cost/hold data, not statutory compliance by contractor. (Contractor bills/cost: partially sufficient — separate module.) |
| ESIC | **PARTIALLY SUFFICIENT** | 18 free-text liaison entries; no claim-level structured data. OC-21/22. |
| GRC / grievance | **PARTIALLY SUFFICIENT** (closest to ready) | 142 well-structured records; blocked by OC-13…OC-19. |
| Disciplinary / cases | **SOURCE NOT FOUND** | |
| Liaison | **PARTIALLY SUFFICIENT** | 57-entry government log + ESIC log; needs authority/status/owner decisions. |
| Plant Visits / CAPA | **PARTIALLY SUFFICIENT** (log only; CAPA **OWNER DECISION REQUIRED**) | Daily observations; no CAPA fields. |
| Communications | **SOURCE NOT FOUND** | |
| Real BFCL import mappings | **OWNER DECISION REQUIRED** | Mappings can be drafted for the five workbook families only after OC-01, 10, 13–19, 27; compliance/licence/employee mappings cannot be started. |

## 9. Recommended Phase 2 cleaning scope (for approval — not started)
1. **Phase 2A — decisions first:** owner answers OC-01, 02, 03, 04, 06, 10, 12, 13–19, 21, 25, 27 (those marked B). Without them cleaning would guess.
2. **Phase 2B — cleaning files outside the application** (originals untouched, every output row carries `source_workbook, sheet, excel_row`): (a) GRC register (143 records → staging; trim/normalise status, resolve duplicates per owner ruling, parse text dates, split multi-ID cells into a reference list, department/designation mapping tables for owner approval); (b) contractor cost register (drop placeholder rows only if approved, normalise contractor names to an owner-approved list, convert text numbers, flag formula/constant mismatches, produce reconciliation to hidden sheets); (c) liaison logs (W2 + W4 merged with duplicate flag; remark date/text split; month-level dates kept as such); (d) plant-visit log (dedupe the repeated June rows; classify entries as observation / leave / weekly off / none).
3. **Phase 2C — mapping proposals** (documents only): proposed target tables for GRC, contractor cost, liaison, plant visit; **no migration** until the owner approves the design and the Phase 2B outputs.
4. **Out of scope until sources arrive:** employee master, compliance/licence/evidence, disciplinary, communications, contractor compliance.
5. Keep personal data out of the repository; Phase 2 outputs stay in the session/secure storage unless the owner approves a location. DEV only.
