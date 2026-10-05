# Owner Decision Pack — Phase 4 (single consolidated list)

**This is the only place owner questions are tracked.** It supersedes `docs/OWNER_DECISION_PACK.md` (production-readiness pack; its 10 rows are carried into group 8). Source of each question: OC-nn = `docs/migration/PHASE1_SOURCE_AUDIT.md`; designs = `PHASE3_TARGET_DESIGN.md`, `DISCIPLINARY_DOMESTIC_ENQUIRY_DESIGN.md`; GRC detail = `docs/GRC_V1_SPEC.md`.
**How to answer:** fill *Owner decision* and *Decision date* in this file (or reply with the ID and choice). **Blocks build?** — YES = the module cannot be built/used without it; "NO (blocks import)" = module can be built, but loading source data waits. Options carry their consequence after "→". Recommendations are proposals; nothing is decided until you answer. No legal, statutory, SLA or retention value is proposed — those cells stay empty until BFCL/legal supply them.

## Two delivery tracks (independent)
- **Track A — Core Compliance V1 rollout:** production readiness / UAT continue regardless of Track B. GRC, Liaison, Contractor, Plant Visit and Disciplinary are **not** prerequisites of Core V1 (see `docs/CORE_V1_ROLLOUT_CHECK.md`). Shared dependencies are flagged where they exist (file storage, email provider).
- **Track B — Module expansion:** `Master reconciliation → GRC → Liaison → Contractor Master/Cost → Plant Visit/CAPA`. **Disciplinary / SCN / Domestic Enquiry** is a parallel future stream, starting only when the Employee Master exists, Certified Standing Orders are supplied, the authority matrix exists, and the communications / PDF / OTP decisions are approved.

## Already approved — not asked again
GRC is a standalone transactional module, not `exception` · Contractor Cost is separate from Contractor Compliance · Government Liaison is one base register with ESIC as a category/specialization · Plant Visit → Observation → optional CAPA · Disciplinary / SCN / Domestic Enquiry is a dedicated domain and its records are not compliance exceptions · humans decide guilt, findings and punishment · issued disciplinary documents are immutable · DEV source data stays pseudonymised/synthetic unless the owner explicitly authorizes real personal data · ESIC insurance-person numbers are not loaded into the ordinary liaison register · medical narratives stay outside the ordinary module in the first release · the pseudonym key never enters Git, DEV, CI artifacts or ordinary application storage.

Columns: **ID | Module | Question | Why needed | Options → consequence | Claude recommendation | Blocks build? | Owner decision | Decision date**

## 1. Organisation structure
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| ORG-01 | Masters | Which legal entity(ies) does "BFCL" denote, and what are the entity code/legal name? | `entity` is mandatory scope for GRC; "BFCL" appears only as a department string | (a) one entity → all records get it; (b) several → each source row needs an entity ruling | Owner confirms entity list from the live inventory (`live_org_masters_inventory.sql`) | NO (blocks import) | | |
| ORG-02 | Masters | What are **GFA** and **HASP**? | Source "Unit"/dept values; scope for location/unit | (a) physical plants → `location`; (b) sites' production units → `unit` under a location; (c) business divisions → `business_unit`; (d) departments → ruled out earlier → consequence: determines scope rules, dashboards and every location mapping | No automatic inference. Supply the BFCL organisation chart; if they are separate plants choose (a), if divisions inside one site (b) or (c) | YES for GRC import and Contractor | | |
| ORG-03 | Masters | What is **Common** (1 cost row)? | Only one source row | (a) shared/overhead marker → entity-level, no location; (b) a real unit | Entity-level "shared" (a) if owner agrees | NO (blocks import) | | |
| ORG-04 | Masters | Approve the department list and the many-to-one mapping of 41 GRC and 85 cost-register department strings | Import needs resolvable department codes | (a) owner supplies list, we propose mapping for approval → clean; (b) auto-match by text → rejected (risk of wrong mapping) | (a). Unmapped values are held, never guessed | NO (blocks import) | | |
| ORG-05 | Masters | Use the `designation` master for GRC complainant designation? (source mixes titles and employee categories) | 55 distinct non-blank values, mixed | (a) store a complainant category LOV only (blue/white collar, contract) + free-text designation; (b) map to `designation` master → needs a designation list | (a) for V1 | NO | | |
| ORG-06 | Masters | Authority master: supply the list of government bodies/offices used for liaison | `authority` master is empty; source names bodies only inside text | (a) owner supplies list → clean mapping; (b) free text → no reporting | (a) (blocks Liaison only) | NO (blocks Liaison) | | |

## 2. GRC
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| GRC-01 | GRC | Approve the status list `RECEIVED → ASSIGNED → IN_PROGRESS → RESOLVED → CLOSED` + controlled `REOPENED` | Drives workflow and legacy mapping | (a) approve as proposed; (b) fewer (e.g. Open/Closed as in source) → simpler, no assignment tracking; (c) more → heavier | (a). No status without a business need | YES | | |
| GRC-02 | GRC | Legacy status mapping: source `Closed` (138) → `CLOSED`; source `Open` (4) → ? | Only two source states | `Open` → RECEIVED / ASSIGNED / IN_PROGRESS → changes ageing of 4 open records | Owner states for each of the 4 open records (never inferred) | NO (blocks import) | | |
| GRC-03 | GRC | Case-number option: A / B / C (see spec) | New cases need a number; legacy kept separately | A `GRC-2026-000001` yearly · B `GRC-000143…` continuous · C legacy look `BFCL/GRC/0143/2026-27` | **B** (existing engine; continuous like the source; no collision with legacy). Counter seeded one-time to continue after 142 | YES | | |
| GRC-04 | GRC | Supply the grievance category list | Source has no category column | (a) owner list; (b) start uncategorised and add later → category reports empty | (a); until supplied category is optional | NO | | |
| GRC-05 | GRC | Per category: default responsible department, default owner role, SLA days, working/calendar basis, escalation rule | SLA/ageing/assignment | values empty until supplied → "no SLA configured" shown; nothing invented | Fill only what BFCL has approved | NO | | |
| GRC-06 | GRC | Priority/severity field in V1? | Not in source | yes → another list to maintain; no → simpler | **No** in V1 | NO | | |
| GRC-07 | GRC | Complainant types: employee / contract worker / group / other — approve | Source mixes individuals, groups, contract labour | add/remove types → changes validation | Approve the four | NO | | |
| GRC-08 | GRC | Who may be owner/assignee (any user with `grievance.update` in scope?) and may a department be the "owner"? | Source "Responsibility" mixes people, departments, contractors | (a) user owner + responsible department; (b) department only | (a) | NO | | |
| GRC-09 | GRC | Role mapping for the 9 grievance permissions (see spec) and field-level restriction of complainant name/ID | Confidentiality | adopt proposal / change per role | Adopt proposal; VIEWER and PLANT_WRITER get none | YES | | |
| GRC-10 | GRC | Employee-ID policy: may a grievance have no employee ID (group/contract) and keep a restricted legacy reference? | 86 of 143 source records have none | (a) yes, restricted `legacy_employee_ref`; (b) require ID → rejects 86 records | (a); future FK when Employee Master exists | NO | | |
| GRC-11 | GRC | Rulings for the historical problem records (table in spec): registration 0140 (rows 142, 387), 0123 (rows 125–126), malformed 0105/2025-27 (row 107), multi-date row 55, stray row 387, text dates rows 47–48, 4 Open records | Import behaviour | per record: import with warning / hold / reject | Hold all until owner supplies the correct number or says "import without legacy number" | NO (blocks import) | | |
| GRC-12 | GRC | Reopen policy: who can reopen, reason mandatory, any time limit? | Reopen workflow | (a) `grievance.reopen` holders, reason mandatory, no time limit; (b) add a time limit (value must come from BFCL) | (a) | NO | | |
| GRC-13 | GRC | Closure rule: may a case close without recorded complainant acknowledgement? | Closure integrity | (a) acknowledgement optional note; (b) mandatory | (a) | NO | | |
| GRC-14 | GRC | Closure outcome list (e.g. resolved / withdrawn / duplicate) or just `CLOSED`? | Avoid extra statuses | (a) `closure_outcome` list owner-defined; (b) none | (a) only if owner wants it | NO | | |
| GRC-15 | GRC | Confidential grievances: a `restricted` flag visible only to assignee/creator/`grievance.admin`? | Not all HR users should see all grievances | yes/no | **Yes** | NO | | |
| GRC-16 | GRC | Attachment file store for GRC (and Core evidence): Supabase Storage (private bucket) or Google Drive | Upload is disabled today (Drive `NOT_CONFIGURED`) | Supabase Storage → no external credentials, DB-near; Drive → needs Workspace admin setup | Supabase Storage for new attachments (shared decision with CORE-06) | YES (attachments) | | |
| GRC-17 | GRC | Retention period for grievance records | Privacy | value must come from BFCL/legal | none proposed | NO | | |

## 3. Liaison
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| LIA-01 | Liaison | Category list (e.g. by authority/subject) | No category in source | owner list vs uncategorised | owner list | NO (blocks import) | | |
| LIA-02 | Liaison | Status list and transitions (source has none) | Tracking | (a) Open/Done; (b) richer | (a) minimal, owner confirms | YES | | |
| LIA-03 | Liaison | Month-only dates (W4): keep as month with `date_precision`, or supply day dates? | Day lost in source | keep month → ageing by month only | keep month precision | NO | | |
| LIA-04 | Liaison | Overlapping events (2 pairs): which entry is the record of truth? | Avoid double count | keep the ESIC log row / keep the Govt row / one record with both refs | one record with both source refs (OC-22) | NO (blocks import) | | |
| LIA-05 | Liaison | Responsible person and next-action fields mandatory? | Not in source | optional vs mandatory | optional | NO | | |
| LIA-06 | Liaison | Where do ESIC medical narratives live (external evidence reference only, per approval)? Who holds the external file and how is it referenced? | Approved principle; mechanism open | reference field + owner of the external store | owner names the custodian/store | NO | | |

## 4. Contractor cost / master
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| CTR-01 | Contractor cost | Meaning of the `(n)` suffix on contractor names (222 rows) | Cannot be kept or dropped blindly | bill number / worker count / serial / other → affects identity and uniqueness | Owner states meaning; kept as found until then | YES | | |
| CTR-02 | Contractor master | Legal names/spellings of the 2 variant pairs; supply contractor master (codes, PAN/GST/licence if available) | No contractor master exists | (a) owner list → master built from it; (b) derive from workbook → rejected | (a) | YES | | |
| CTR-03 | Contractor cost | May-2025: which version is authoritative (consolidated vs hidden sheet; row 9 differs by exactly 1,882,318; Production Incentive column shift in 22 rows)? | Conflict kept open | consolidated / hidden / per-field | Owner/source confirmation | NO (blocks import of 22 rows) | | |
| CTR-04 | Contractor cost | Meaning/calculation of hold amount, other hold, hold release month (28 rows ≠ 25 %) | Holds are financial | store as given vs rule-based | Store as given, no recalculation | YES | | |
| CTR-05 | Contractor cost | Bill-number policy (repeated values; planned unique contractor+invoice) | Uniqueness | warn only / unique per contractor+month / unique per contractor | warn only until owner rules | NO (blocks import) | | |
| CTR-06 | Contractor cost | Meaning of Dept / Cost Centre / Nature of work (differ before/after Aug 2025); supply cost-centre list | Column roles | owner defines each | owner definition | YES | | |
| CTR-07 | Contractor cost | LS and PR meaning; Bonus column intentionally empty? PF 12 % vs 13 % | Interpretation | owner states | owner states | NO (blocks import) | | |
| CTR-08 | Contractor cost | Policy for 194 "Work not done" rows without amounts and the 16 `CONFLICTING_NOTE_WITH_AMOUNTS` rows (identical figures Jan–Aug 2026) | Must not drop or invent | import as zero-activity / skip / hold; conflicting rows → owner confirms nature | hold conflicting rows; placeholders per owner | NO (blocks import) | | |
| CTR-09 | Contractor cost | Access to cost data (confidential commercial): which roles? | Privacy | HR only / finance / named roles | restricted new permission | YES | | |
| CTR-10 | Contractor cost | Module name/code (not "Contractor Compliance") | Avoid confusion | `contractor_cost` or other | `contractor_cost` | NO | | |

## 5. Plant Visit / CAPA
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| PLV-01 | Plant Visit | Purpose of the daily log: grievance feeder, general observation log, or both? | Shapes the model | per purpose | owner states | YES | | |
| PLV-02 | Plant Visit | Is CAPA in V1? (source has no owner/due/status) | Scope | log-only first / include CAPA | log + observation only first | YES | | |
| PLV-03 | Plant Visit | Location/plant and visitor per entry | Not in source | add as new fields / single-site assumption (no) | add fields; legacy rows left blank | NO | | |
| PLV-04 | Plant Visit | Source for June 2026 (exists only as hidden duplicated rows) | Completeness | accept hidden copy / supply sheet | accept after owner confirms | NO (blocks import) | | |
| PLV-05 | Plant Visit | Observation categories/severity list | Not in source | owner list / none | none in V1 | NO | | |

## 6. Disciplinary / SCN (disciplinary-stream blockers only — **do not block Core V1 or GRC**)
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| DSC-01 | Disciplinary | Certified Standing Orders (and service rules) — supply the source documents and versions | Legal snapshot, clause catalogue | none can be built without | supply | YES (stream) | | |
| DSC-02 | Disciplinary | Employee Master source (file/system) | Case subject | file import / HRMS interface | supply | YES (stream) | | |
| DSC-03 | Disciplinary | Disciplinary/competent-authority and appeal matrices | Authority resolution | owner-approved matrix by category/grade/location/severity | supply | YES (stream) | | |
| DSC-04 | Disciplinary | Worker / non-worker classification rule | Applicable law | BFCL rule | supply | YES (stream) | | |
| DSC-05 | Disciplinary | Confidentiality levels and break-glass policy | Need-to-know | (a) none; (b) reason-logged break-glass | (b) | YES (stream) | | |
| DSC-06 | Disciplinary | AI-assisted drafting allowed? | Governance | yes (user-invoked, human approval, flagged) / no | **YES for user-invoked drafting/formatting of notices; human approval mandatory; NO automatic findings, guilt or penalty recommendations** | NO | | |
| DSC-07 | Disciplinary | Email provider | Notices, portal links | Gmail/Workspace, SMTP/ESP, other | decide with CORE-07 (shared) | YES (stream) | | |
| DSC-08 | Disciplinary | OTP provider/channel and approved-contact policy | Employee portal | SMS/email/both | owner choice | YES (stream) | | |
| DSC-09 | Disciplinary | Portal link lifetime; OTP expiry and attempt limits | Security | values from BFCL security policy | owner values | YES (stream) | | |
| DSC-10 | Disciplinary | PDF renderer | Issued documents | server-side service/library | owner/tech choice | YES (stream) | | |
| DSC-11 | Disciplinary | DSC / e-sign requirement | Document signing | approval stamp / scanned signature / DSC / e-sign | legal advice | YES (stream) | | |
| DSC-12 | Disciplinary | Language/translation requirements for notices | Templates | English only / multi-language | owner | NO | | |
| DSC-13 | Disciplinary | Suspension and subsistence-allowance policy and payroll interface | Suspension module | track-only vs payroll integration | track-only; payroll later | YES (stream) | | |
| DSC-14 | Disciplinary | Retention and legal-hold policy; templates (SCN, charge sheet, hearing notice, appointment, final order); deadline/service/appeal rules | Legal config | BFCL/legal supply | supply | YES (stream) | | |

## 7. DEV / privacy
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| PRV-01 | Privacy | May real personal data ever be loaded into DEV? | Test fidelity vs risk | (a) never (pseudonymised/synthetic) ; (b) specific approved subset | (a) | NO | | |
| PRV-02 | Privacy | Approve implementing the repository/CI privacy guard (see `docs/PRIVACY_GUARD_PROPOSAL.md`) | Prevents accidental commits | approve / defer | approve | NO | | |
| PRV-03 | Privacy | Custody of the FULL cleaned files, original workbooks and the pseudonym key (who holds them, where) | Session storage is temporary | owner-controlled secure location | owner custody; none in Git/DEV/CI | NO | | |
| PRV-04 | Privacy | Retention/disposal of source workbooks and cleaned outputs | Data minimisation | define period (value from BFCL) | delete after import acceptance unless owner says otherwise | NO | | |

## 8. Core rollout (Track A) — carried from the production-readiness pack
| ID | Module | Question | Why needed | Options → consequence | Recommendation | Blocks? | Decision | Date |
|---|---|---|---|---|---|---|---|---|
| CORE-01 | Core | Create PROD environment: separate Supabase project, Cloudflare production project/domain | No PROD exists | create now / later | create | YES | | |
| CORE-02 | Core | Backup/PITR plan and one **proven** restore | Currently UNPROVEN | plan + drill | enable PITR, drill before go-live | YES | | |
| CORE-03 | Core | Production Google OAuth client, redirect URLs, secrets custody | Login | BFCL Google Cloud owner | provide | YES | | |
| CORE-04 | Core | Real compliance masters/data source (obligations, applicability, evidence, owners) | Only synthetic samples exist; legal content must come from BFCL | supply workbook/approved list | supply | YES | | |
| CORE-05 | Core | Users, roles, scopes for go-live; role-permission matrix; responsible department on each compliance master | Access and visibility | owner list | owner list | YES | | |
| CORE-06 | Core | Evidence file storage (Drive vs Supabase Storage) | Evidence upload disabled | as GRC-16 | one shared decision | YES (if evidence upload is required at go-live) | | |
| CORE-07 | Core | Email delivery for alerts (provider/credentials) | Email channel inactive | enable / in-app only at go-live | owner choice | NO (in-app works) | | |
| CORE-08 | Core | Scheduler: enable `pg_cron` for the 3 approved jobs; production `UNROUTABLE_ESCALATION` recipients | Automation | manual daily runs until gates met | after gates | YES (decision) / NO (enabling) | | |
| CORE-09 | Core | Retention policy (audit, export log, evidence, notifications) | Governance | indefinite / fixed (value from legal) | value from BFCL | NO | | |
| CORE-10 | Core | Report definitions/targets; the four runner behaviours | Optional | later | later | NO | | |
| CORE-11 | Core | UAT participants/scope, manual accessibility testers, support owner and go-live sign-off criteria | Release gates | named people | owner | YES | | |
