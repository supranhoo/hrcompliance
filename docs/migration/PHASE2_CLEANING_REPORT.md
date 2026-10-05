# Phase 2 — Conservative source cleaning report

**Status:** Phase 2 complete (cleaning/preparation only, outside the application). No import into DEV, no migration, no schema change, no `pg_cron`, originals untouched (SHA-256 of all five uploads and the read-only working copy re-verified identical to Phase 1). Awaiting owner approval before Phase 3.
**Privacy:** this document and `scripts/migration/phase2/` contain only counts, issue categories, row references and rules — no names, employee IDs, ESIC numbers, medical text or raw rows. Cleaned files containing source personal data live **outside the repository** (session scratchpad `phase2_out/`).

## Owner rulings applied
1. GFA/HASP kept as `unit_candidate_raw` (location/unit candidate), never as department. 2. `(n)` kept exactly in the contractor name and also copied to `suffix_as_found`; nothing removed or interpreted. 3. `Mar 2026` is the working source; the May-2025 conflict with the hidden sheet is **not resolved** and sits in Owner_Review. 4. Duplicate/conflicting GRC registrations not fixed. 5. Only unambiguous dates normalised (day > 12 in dd/mm/yyyy, or real Excel dates). 6. Ambiguous employee IDs preserved raw and classified, never split. 7. `Closed` spellings canonicalised, original kept in `status_raw`. 8–10. Sensitive/personal data kept out of the repo; medical/ESIC narrative and all free text withheld from the DEV-oriented files; personal names/IDs pseudonymised there.

## Output structure (per area, FULL and DEV variants)
`Cleaned_Data` · `Duplicate_Rows` · `Rejected_or_Invalid` · `Owner_Review` · `Transformation_Log` (workbook → sheet → Excel row → field → rule → original → cleaned) · `Data_Quality_Summary`. Files: `GRC`, `CONTRACTOR_COST`, `LIAISON_ESIC`, `LIAISON_GOVT`, `PLANT_VISIT` (each `_cleaned_FULL_CONFIDENTIAL.xlsx` and `_cleaned_DEV_pseudonymized.xlsx`) and `PSEUDONYM_KEY_CONFIDENTIAL.xlsx`.
DEV variants: personal name and employee-ID columns → deterministic pseudonyms (`PERSON-nnnn`, `EMPID-nnnn`, `CONTR-nnnn`); every free-text column → `[WITHHELD - not approved for DEV]`; the designation column is kept only for values shared by ≥ 3 rows and not matching any pseudonymised value. A scan of all DEV workbooks for every original name/ID/contractor string found **0 occurrences**.

## GRC cleaning result
143 register records cleaned (rows 3–144 + stray row 387); 41 CLEAN, 102 FLAGGED. 242 formula-only/decorative rows (145–385, 386) moved to Rejected_or_Invalid (not data). Sheet1: 3 records, all 13 comparable fields equal to the main sheet → listed in Duplicate_Rows, excluded from Cleaned_Data.
Flags: duplicate registration numbers 4 rows (2 numbers); malformed registration 1; duplicate Sl.No. 2; Sl/registration mismatch 1; stray row 1; ambiguous text date 1 (multi-date cell → Owner_Review, date left blank); unambiguous text dates normalised 2 (annotation kept separately); status blank 1; status respelled 6 (`Closed␠`/`closed` → `Closed`; final `Closed` 138, `Open` 4); employee ID missing 86, multiple 7, non-ID text 1 (49 numeric single IDs); TAT blank 4.
Not touched: registration numbers, Sl.No., employee IDs, TAT values, department/designation/responsibility wording.

## Contractor cost cleaning result
685 dated rows cleaned; 2 rows without Month → Rejected_or_Invalid (values preserved, flagged); all 685 carry ≥ 1 flag (mostly the informational HARDCODED_TOTAL 481). Reconciliation: **sum of Total cost excl. GST identical to the source (diff 0.00)**; Bill amount differs only by the one text value converted (3,883,582).
Flags: `(n)` suffix 222 rows; 64 contractor strings as found / 22 candidate groups; 2 spelling-variant pairs flagged for the owner (not merged); exact duplicate rows 22 (11 pairs, both kept); repeated Bill No. 67 rows (28 values; 33 rows share a Bill No. within the same contractor key); hold ≠ 25 % of total 28; hand-typed-number formulas 147 rows; numbers stored as text converted 2 (certain: grouped digits), non-numeric text in a number column 7 (left blank, raw preserved in Owner_Review); hard-coded Total 481; rows whose Bill No. cell holds a "Work not done"-type note 210 (kept; **see the count reconciliation below — 16 of them carry amounts and were wrongly given class PLACEHOLDER_NO_WORK**); release month not a date 2.
May 2025: 22 consolidated rows kept and flagged; **1 row differs from the hidden May sheet (Total and Hold; the Total difference is exactly 1,882,318)**; Production Incentive carries a value in 22 of 22 consolidated May rows where the hidden sheet has none; consolidated Cost Centre equals hidden Dept in 22 of 22 rows (column roles differ before/after Aug 2025). June–Sept 2025 hidden sheets reconcile exactly with the consolidated sheet.

## Liaison cleaning result
ESIC: 18 rows cleaned; TAT recomputed (calendar days) = source for all 18; 1 row flagged for a long-digit (insurance-number-like) token; narrative withheld from the DEV file. Govt: 57 rows cleaned; Month kept as first-of-month; Remark split by cell type into `remark_as_date` (36) / text (20) / blank (1) — the date is not interpreted; 1 hard-coded Sr cell; 1 placeholder-like short entry. **2 overlapping events detected (ESIC rows ↔ Govt rows, text similarity ≥ 0.85) — flagged on both sides, not merged.** No row rejected.

## Plant visit cleaning result
153 source rows → 123 unique dates cleaned (May 31, June 30, July 31, Aug 31). **30 June-2026 rows exist only as hidden rows duplicated in both `July 2026` and `Aug 2026`; all 30 copies identical; canonical copy kept (July sheet), the Aug copies are in Duplicate_Rows (not double counted); `also_present_in` records the other copy.** Entry-type hints (exact boilerplate phrases only): no-grievance 61, authorised leave 14, weekly off 8, other text 40. Free text withheld from the DEV file.

## Rows cleaned / flagged / rejected
| Area | Source data rows | Cleaned_Data | Flagged | Duplicate_Rows entries | Rejected/Invalid | Owner_Review items |
|---|---:|---:|---:|---:|---:|---:|
| GRC | 143 + 3 (Sheet1) + 242 non-data | 143 | 102 | 7 | 242 | 99 |
| Contractor cost | 687 | 685 | 685 | 50 | 2 | 43 |
| ESIC | 18 | 18 | 4 | 2 | 0 | 3 |
| Govt liaison | 57 | 57 | 11 | 2 | 0 | 5 |
| Plant visit | 153 | 123 | 30 (duplicated) | 30 | 0 | 3 |

## Transformations applied (all logged row-by-row with original and cleaned value in the FULL files)
Whitespace trim/collapse (single-line fields; free text keeps line breaks); dates → ISO (`yyyy-mm-dd`); unambiguous text dates → ISO; status respelling → `Closed`; text numbers with grouped digits → number (2 cells); row exclusion only of formula-only/decorative/no-Month rows; Remark column split by type. **Not done:** no ID/code invented, no names/contractors merged, no (n) change, no amount/hold/TAT change, no department/location/entity inference, no registration fix, no ID split.

## Unresolved owner questions (carried from Phase 1 + new)
OC-01 (GFA/HASP meaning), OC-02 (`(n)`), OC-03 (contractor spellings), OC-04 (May 2025 authority — now with the exact row), OC-06 (hold and release month), OC-07 (11 repeated FAD MECH rows, repeated bill numbers), OC-08 (placeholder rows, no-Month rows 166/173), OC-10 (Dept/Cost Centre/Nature of work — new evidence: roles differ in early rows), OC-13/14 (duplicate/malformed registrations), OC-15 (multi-date cell), OC-18/19 (employee-ID policy; designation/department lists), OC-21 (ESIC sensitivity), OC-22 (overlap source of truth: 2 events), OC-23, OC-25 (June 2026 sheet), OC-26/27. New: Production-Incentive column shift in May 2025; whether repeated Bill Nos across different contractors are legitimate numbering.

## Sensitive data handling
Repo: counts, categories, row references, rules, scripts only. FULL files (outside repo) hold source values for traceability and are marked CONFIDENTIAL. DEV files: pseudonymised personal fields, all free text withheld (ESIC particulars, case detail, plant-visit observations, GRC nature/action/remarks/responsibility, contractor remarks). ESIC IP-number-like tokens exist only in the FULL ESIC file; none appear in any DEV file or the repo. The pseudonym key is a separate confidential file; do not share it with DEV.

## Phase 3 mapping readiness
- **GRC:** ready for mapping *design* once OC-13/14/16/17/18/19 are ruled; cleaned set is consistent.
- **Contractor cost:** ready for design; **blocked for load** by OC-02/03/04/06/10 (names, May conflict, hold semantics, column roles).
- **Liaison (ESIC + Govt):** structure only (dates, TAT); content cannot be loaded to DEV until OC-21 and the authority/category decisions.
- **Plant visit:** structure ready (date, entry hint); free text and CAPA scope await owner decision (OC-26/27).
- Still **SOURCE NOT FOUND:** employee master, contractor master, compliance/licence, disciplinary, communications.

## Phase 1 vs Phase 2 count reconciliation (added after owner review; no workbook or cleaned file was changed)
**Source-row basis (contractor sheet `Mar 2026`):** sheet rows 2–690 = 689 rows; 2 rows are completely empty (573, 628); 687 non-empty data rows = **685 dated rows + 2 undated rows (166, 173)**. (The Phase 1 "688 of 690" included the header row.)

| # | Item | Phase 1 definition → count | Phase 2 definition → count | Nature of difference | Authoritative figure to carry forward |
|---|---|---|---|---|---|
| 1 | "Work not done" | Dated rows with **no numeric Bill amount (M) and no numeric Total (Q)** → **195** (187 exact "Work Not done" + 4 "Work not done during the month of August 2025" + 3 other notes + 1 row, 49, with a blank Bill No. cell). | Dated rows whose **Bill No. (H) text matches a placeholder phrase**, whatever the amounts → **210** (= 194 without amounts + **16 with amounts**). | Counting-definition difference **plus one real Phase 2 classification error** (below). Phase 1 wording "195 rows say Work not done" was also loose: 195 is the no-amount count; only 187 are the exact phrase. | No-amount rows: **195**. Placeholder-note rows in the Bill No. column: **210** (194 no amounts, 16 with amounts). Exact phrase "Work Not done": **203** (187 no amounts + 16 with amounts). |
| 2 | Repeated Bill No. | **Dated rows only** (685); strings containing "work" or "bill" excluded; exact text after trim → **27 values** (66 rows). | **All 687 non-empty rows** (incl. the 2 undated); only "work"/"bill is not" excluded; whitespace-collapsed, case-folded → **28 values** (68 rows). | Counting-definition difference only. The extra value is Bill No. `105`, shared by undated row 166 and dated row 327 (different contractors). No Phase 1 error. | **27 values on dated rows** (66 rows); **28 including undated row 166**. Both are reported; Phase 3 uses the 27-value dated basis plus the row-166 note. |
| 3 | 685 rows | "685 dated rows (+2 undated)" (Phase 1 sheet matrix). | 685 Cleaned_Data + 2 No-Month rejected = 687. | Same basis, described differently: **no difference**. Phase 1 already said "+2 undated". | **687 non-empty data rows = 685 dated + 2 undated.** |

### Real Phase 2 classification error found (stop-and-report item)
16 rows (Excel rows 316, 317, 361, 362, 409, 410, 458, 459, 512, 513, 566, 567, 621, 622, 678, 679 — two rows per month, Jan–Aug 2026) have "Work Not done" in the Bill No. column **and** populated amounts (Total 774,770.04 and 62,434.42 per month, identical every month). The Phase 2 script classified them from the text alone as `row_class = PLACEHOLDER_NO_WORK` / flag `WORK_NOT_DONE_PLACEHOLDER`, which is wrong for rows that carry cost.
- **Impact:** no value was changed or dropped (reconciliation to the source total is exact); only the label is misleading — a downstream filter that excludes `PLACEHOLDER_NO_WORK` would silently drop ₹ 8 × (774,770.04 + 62,434.42) of cost, and the Phase 2 report overstated "placeholder rows" by 16.
- **Not yet corrected** (owner instruction: stop and report). Proposed correction, to be applied only on approval: reclassify these 16 as `row_class = CONFLICTING_NOTE_WITH_AMOUNTS`, flag `WORK_NOT_DONE_NOTE_BUT_AMOUNTS_PRESENT`, add one Owner_Review item (identical figures repeated for 8 consecutive months alongside a "Work Not done" note — possible carried-forward figures; **not interpreted**), keep all amounts as found, and re-issue the two cleaned contractor files. The other 194 note rows stay `PLACEHOLDER_NO_WORK`.
