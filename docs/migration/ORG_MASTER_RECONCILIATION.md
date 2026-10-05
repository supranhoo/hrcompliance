# Organisation / master reconciliation (Phase 4 — owner-facing; nothing created, nothing inferred)

**Purpose:** match the terms used in the source workbooks to the master tables that already exist in the application, so the owner can confirm each one. **No master record is created, no value is mapped automatically, and GFA / HASP are not inferred.** Decisions are recorded in `docs/OWNER_DECISION_PACK_PHASE4.md` (ORG-01…ORG-06).
**What exists:** the application has the masters `entity` (code, name, legal name, PAN, GSTIN, CIN), `location` (belongs to an entity), `business_unit` (belongs to an entity), `unit` (belongs to a location and/or business unit), `department` (optional parent), `designation` (code, name, grade) and `authority` (code, name, type, office). **The repository's migrations seed none of them**, so "existing record?" below means *no record is created by the repository*; what already sits in the DEV database is unknown to me. To list it, run the read-only `supabase/dev-samples/live_org_masters_inventory.sql` (paste the whole file in a fresh Supabase SQL Editor tab, send the rows back) — then the "Existing record?" column is completed from real records.
**Counting note:** distinct counts here are *non-blank* values after whitespace normalisation, so some differ by one from the Phase 1 report, which counted a blank as a value (cost Dept 85 not 86, Nature of work 61 not 62, Cost Centre 61 not 62). The complete term lists with row counts are in `ORG_RECONCILIATION_OWNER_TABLE_CONFIDENTIAL.xlsx` (outside the repo; organisation names only).

## 1. Entity, plants and units
| Source term | Where it appears | Current master candidate | Recommended master type | Existing record? | Owner confirmation required |
|---|---|---|---|---|---|
| **BFCL** | GRC Dept. (3 rows); the company name in titles | `entity` | entity (legal name, code) | none seeded | **Yes — ORG-01** (single entity or several?) |
| **GFA** | cost register Unit (352 rows); GRC Dept. variants (see §2); cost Dept/Cost-Centre text | `location` / `unit` / `business_unit` (all exist, none chosen) | **not decided** — location, unit or business unit | none seeded | **Yes — ORG-02** (do not infer) |
| **HASP** | cost register Unit (332 rows); GRC Dept. variants; cost Dept/Cost-Centre text | same | **not decided** | none seeded | **Yes — ORG-02** |
| **Common** | cost register Unit (1 row) | entity-level "shared" marker or a unit | not decided | none | **Yes — ORG-03** |
| Several cells name both plants (e.g. combined or slash forms) | GRC Dept. (10 rows) | – | needs a rule: a record belongs to one scope, or "both" | – | **Yes — ORG-02** (how to scope a record naming two plants) |
Also in the source and **not** mapped to a master: other plant-area words inside department and cost-centre text (FAD, DRI, SMS, CPP, 3X100 TPD, 1050 TPD …). These may be departments, plant areas or cost centres; they are recorded only as *display families*, not as a decision.

## 2. Departments (GRC register, 41 distinct non-blank terms)
| Source term | Rows | Current master candidate | Recommended master type | Existing record? | Owner confirmation |
|---|---:|---|---|---|---|
| `GFA` | 31 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `HASP` | 18 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `Admin` | 11 | department | department | none seeded | yes (ORG-04) |
| `GFA Unit` | 10 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `HASP Unit` | 6 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `HASP/GFA` | 6 | location/unit candidates (both plants named) — **one source cell, two plants** | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `FAD` | 5 | department | department | none seeded | yes (ORG-04) |
| `HR` | 5 | department | department | none seeded | yes (ORG-04) |
| `HASP & GFA Unit` | 4 | location/unit candidates (both plants named) — **one source cell, two plants** | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `Admin.` | 3 | department | department | none seeded | yes (ORG-04) |
| `BFCL` | 3 | entity | entity | none seeded | yes (ORG-01) |
| `Central Automobile` | 3 | department | department | none seeded | yes (ORG-04) |
| `Admin-Security` | 2 | department | department | none seeded | yes (ORG-04) |
| `Audit` | 2 | department | department | none seeded | yes (ORG-04) |
| `Automobile` | 2 | department | department | none seeded | yes (ORG-04) |
| `Commercial plant` | 2 | department | department | none seeded | yes (ORG-04) |
| `EHS-Health` | 2 | department | department | none seeded | yes (ORG-04) |
| `FAD Operation` | 2 | department | department | none seeded | yes (ORG-04) |
| `FAD-Production` | 2 | department | department | none seeded | yes (ORG-04) |
| `1050 TPD QC` | 1 | department | department | none seeded | yes (ORG-04) |
| `3X100 TPD` | 1 | department | department | none seeded | yes (ORG-04) |
| `Admin-Canteen` | 1 | department | department | none seeded | yes (ORG-04) |
| `Admin-Pollution` | 1 | department | department | none seeded | yes (ORG-04) |
| `Admin-Temple` | 1 | department | department | none seeded | yes (ORG-04) |
| `CLU & DRI` | 1 | department | department | none seeded | yes (ORG-04) |
| `CPP, HASP Unit` | 1 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `Commercial HO` | 1 | department | department | none seeded | yes (ORG-04) |
| `Costing & Business Analytic` | 1 | department | department | none seeded | yes (ORG-04) |
| `DRI` | 1 | department | department | none seeded | yes (ORG-04) |
| `DRI-HASP Unit` | 1 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `FAD Mech.` | 1 | department | department | none seeded | yes (ORG-04) |
| `FAD Production` | 1 | department | department | none seeded | yes (ORG-04) |
| `FAD-Metal Handling` | 1 | department | department | none seeded | yes (ORG-04) |
| `Ferro-Operation` | 1 | department | department | none seeded | yes (ORG-04) |
| `HASP Plumber` | 1 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `HASP Unit, DRI Mech 1050 TPD` | 1 | location/unit candidate (plant named; ruled: not a department) | location / unit / business unit — owner (ORG-02); any department word in the cell — ORG-04 | none seeded | yes (ORG-02 + ORG-04) |
| `HO Ranchi` | 1 | department | department | none seeded | yes (ORG-04) |
| `Human Resources` | 1 | department | department | none seeded | yes (ORG-04) |
| `SMS` | 1 | department | department | none seeded | yes (ORG-04) |
| `SMS Furnace` | 1 | department | department | none seeded | yes (ORG-04) |
| `Works Committee` | 1 | department | department | none seeded | yes (ORG-04) |

Display families for the 85 distinct **cost-register Dept** terms (keyword only, *not* a mapping): FAD-related 191 rows · Admin 58 · Admin+Security 74 · SMS 26 · DRI 14 · CPP 8 · Commercial 9 · GFA 19 · other 246 (+ minor combinations). Full list in the confidential xlsx. **Recommended handling:** owner supplies the authoritative department list (ORG-04); a many-to-one mapping file is proposed for approval; unmapped terms stay on hold.

## 3. Cost-register work-area terms (not organisation masters)
Cost Centre (61 distinct) and Nature of work (61 distinct) are **not** the same list as Dept; their meaning differs before/after Aug 2025 (CTR-06). Candidate masters: cost-centre list (not in the application) and a nature-of-work LOV (new). No record exists; owner supplies/approves the lists.

## 4. Designations
55 distinct non-blank GRC "Designation" values mix three kinds of content: employee **category** terms (blue collar, white collar incl. a misspelling, contract labour, labour supervisors), **job titles**, and cells that contain **names** (not listed here). Candidate master: `designation` (code, name, grade). Recommended (ORG-05): do **not** load the designation master from GRC; keep a complainant-category list plus free-text designation for V1. Existing record: none seeded.

## 5. Authorities (liaison)
No authority column exists; bodies are named only inside free text. Indicative keyword scan (case-detail text, 57 + 18 entries; a *hint*, not a mapping): Labour office / Labour Superintendent / Labour Commissioner ~11 · Factory Inspector / Factory Directorate ~10 · ESIC ~10 · EPF / RPFC ~4 · Employment Exchange 3 · State Pollution Control Board 1 · **banks 8 (not government authorities — outside the authority master)**. Candidate master: `authority` (code, name, type, office); existing record: none seeded. **Owner confirmation:** supply the authority/office list (ORG-06); no mapping is done by keyword.

## 6. What the owner needs to return
1. The live inventory rows (`live_org_masters_inventory.sql`). 2. ORG-01…ORG-06 answers. 3. The authoritative department list. After that a **proposed** mapping file (term → master code, unmapped = hold) is prepared for approval; masters are created only after approval, through the existing Master Data admin screens.
