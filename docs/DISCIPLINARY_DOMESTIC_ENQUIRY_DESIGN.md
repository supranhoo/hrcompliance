# Disciplinary, SCN & Domestic Enquiry Management — domain design (Phase 3A)

**Status:** DESIGN ONLY, awaiting owner approval. No migration, no UI, no data, no import. Migrations 0001–0039 stay frozen; `pg_cron` OFF.
**Principles (binding on every section):** (1) the system records and routes; **humans decide** — it never recommends or selects guilt, a finding or a punishment; (2) no legal rule, period, clause, authority, template text or retention period is invented — each is **configuration supplied and approved by BFCL / legal counsel**, versioned and effective-dated; (3) issued documents are immutable; (4) need-to-know access, not "all HR sees all"; (5) disciplinary cases are **never** stored as compliance `exception` records.
No personal data appears in this document.

## Current Capability Reuse
Checked against the schema (migrations 0001–0039):
| Platform capability | Exists today | Reuse for this domain |
|---|---|---|
| Authentication | Google sign-in + Supabase Auth, `app_user` (staff accounts; `employee_code` is only a login attribute, **not** an employee master) | Reuse for staff roles. **Not** suitable for the employee reply portal (employees need no account) |
| Roles / permissions / RLS | roles `SUPER_ADMIN, HEAD_HR, HOD, PLANT_HR, PLANT_WRITER, VIEWER`; 24 permissions; `app.has_permission`, entity/location/department scope (D-038); guarded role/scope admin | Reuse the pattern; **new permissions and roles** are required (a generic HR role must *not* see every case) |
| Immutable audit | `audit_log` with `audit_row` and `audit_immutable` triggers | Reuse as-is for case/document/decision history |
| Attachments / documents | `evidence` (bound to a compliance instance or licence by `evidence_one_parent_ck`), `document_type`, storage providers `google_drive`/`supabase_storage`/`external_link`, SHA-256 field, version/supersede pattern | Reuse the **pattern** (provider, checksum, versioning); **needs a generic attachment link** with per-file confidentiality — the existing table cannot hold case documents |
| Notifications | `notification` (channels `in_app`/`email`, states `queued/delivered/failed`, categories and link kinds limited to compliance); **no delivery provider configured**; job `communication_followup` is a disabled placeholder | Reuse for in-app alerts only. A **shared communications service** is needed (see its section) |
| SLA / ageing | `config_definition` (SLA rules as config), `v_exception` age buckets / `target_breached` pattern | Reuse the concepts for deadlines and ageing views; not the `exception` table |
| Configuration / LOV | `lov_set`/`lov_value`, `status_definition` + `status_transition` (module codes already exist: `disciplinary`, `esic`, `grievance`, `liaison`), `field_definition` + `field_role_access` (field-level view/edit by role) | Reuse for categories, statuses, transitions, field-level access |
| Numbering | `numbering_rule` + `number_counter` (keys incl. `DISC`, yearly reset, width 6) | Reuse; add keys per document type (SCN, charge sheet, hearing notice, order …) |
| Org masters | `entity`, `location`, `department`, `designation`, `authority`, `business_unit`, `unit` | Reuse; GFA/HASP mapping still open (OC-01) |
| Import framework (0031) | generic staged import | **Historical migration only** (no disciplinary source exists) |
| Export logging | `export_log`, `report.export` permission, CSV safety rules | Reuse the pattern; disciplinary exports need their own stricter permission |
| Jobs | `job_definition`, monitor; scheduler OFF | Reminders/ageing jobs only after the scheduler gates in `CRON_PROPOSAL.md` |

## Missing Capabilities
No employee master · no disciplinary/case tables or permissions · no case-level confidentiality / case-team access model · no document template/versioning/PDF/QR service · no shared outbound communications layer or provider · no external (token/OTP) access channel · no legal-configuration registry (law, jurisdiction, Standing Orders, clauses, authority matrix, deadline/deemed-service rules) · no service register · no deadline/extension engine · no legal hold / retention / disposal mechanism · no e-sign/DSC capability · no payroll interface.

## Proposed Workflow
`Incident → Preliminary Fact Finding → [decision: SCN required?] → SCN (draft → review → approve → issue) → Service → Employee Reply (portal or recorded physical reply) → Decision after SCN → [Charge Sheet → Domestic Enquiry → Findings/Enquiry Report → Representation → Final Order] → Appeal/Review → Closure`
Decision points are **human gates** with mandatory reasons: (G1) SCN required or not, after preliminary facts; (G2) outcome after SCN (accepted / counselling or advisory where approved / warning where legally and policy-wise permitted / seek clarification / charge sheet / domestic enquiry / closure); (G3) ex-parte proceeding (controlled gate); (G4) disciplinary authority's decision on the enquiry findings and on action; (G5) appeal outcome. Every gate stores: decider (role + person), authority basis (matrix version), reason text, timestamp; transitions are enforced by a configurable state machine (`status_transition`), and the system never pre-selects an outcome.
Preliminary Fact Finding is a **separate stage** from the formal domestic enquiry (different officer role, different record, not disclosed as an enquiry proceeding). A case may end at any stage (closure with reason).
Case states (concept): `INCIDENT_REPORTED → PFF_IN_PROGRESS → PFF_COMPLETE → SCN_DRAFTING → SCN_ISSUED → AWAITING_REPLY → REPLY_RECEIVED → DECISION_PENDING → CHARGE_SHEET_ISSUED → ENQUIRY_IN_PROGRESS → FINDINGS_SUBMITTED → REPRESENTATION_PENDING → FINAL_ORDER_PENDING → ORDER_ISSUED → APPEAL_WINDOW → APPEAL_PENDING → CLOSED`, plus `ON_HOLD` and `WITHDRAWN`. Per-charge sub-lifecycle is separate (below).

## Proposed Domain Model
Conceptual objects (names are design-level; relationships shown):
- **`disc_case`** — case no. (numbering), incident date/time, entity/location/department, employee (FK to the future employee master), employee category/status, reporting person, allegation summary, status, confidentiality level, case team. 1→1 `disc_legal_snapshot`; 1→many everything below.
- **`disc_preliminary`** (PFF) — fact-finding officer, preliminary facts, witnesses, initial documents, outcome, **SCN-required decision** (G1).
- **`disc_legal_snapshot`** — immutable record of the rules applicable **on the incident date** (applicable law, jurisdiction/appropriate government, establishment/location, worker/non-worker category, Certified Standing Orders version, service-rule/policy version, misconduct/discipline clause(s)), stored as resolved values **plus** the registry version ids they came from. Never recalculated from "latest"; a correction creates a new snapshot version with reason and link.
- **Legal registry (configuration):** law, jurisdiction, standing-orders document + versions (effective-dated), clause catalogue, policy versions, worker-category classification, deadline rules, deemed-service rules, appeal rules, subsistence rules, retention rules. Each has a **legal source reference, effective dates, approved-by/approved-at** and cannot be activated unapproved.
- **`disc_authority_matrix` (versioned)** — rules keyed by employee category/grade, entity/location, case nature/severity, applicable standing orders/service rules → competent/disciplinary authority role (and appeal authority). **Never named individuals** — it resolves to a role/position; the person actually deciding is recorded on the decision with the matrix version.
- **`disc_document` + `disc_document_version`** — every formal document (see lifecycle section) with template version, numbering, hash, file reference, review/approval/issue stamps, service history.
- **`disc_service` (notice service register)** — per document and per attempt: mode, sent/delivered dates, acknowledgement, returned/bounced, refusal + witness/proof, postal/courier reference, evidence attachments, deemed-service outcome (rule-driven).
- **`disc_deadline`** + **`disc_extension`** — original due date, rule version, extension request/reason/decision/revised date, reminders, overdue state, calendar/working-day rule.
- **`disc_portal_access` / `disc_portal_event`** — token hash, expiry, OTP state, revocation, minimal security events.
- **`disc_reply`** — draft (mutable) and final (immutable) reply, attachments, declaration, receipt; or a **recorded physical reply** with evidence.
- **`disc_decision`** — gate decisions (G1/G2/G4/G5): outcome, reason, authority, matrix version.
- **`disc_charge`** (multiple per case) — charge no., statement of imputation, clause/legal basis, relied-upon documents, witnesses, employee reply, **its own lifecycle and final finding** (Proved / Not Proved / Partly Proved).
- **`disc_enquiry`** — appointment order, IO, PO, defence assistant, conflict declarations, recusals, replacements (reason), employee objections, hearings (`disc_hearing`: date/time/place/mode, language/interpreter, attendance, adjournments, next date, non-appearance + proof), witnesses (`disc_witness`: management/employee, sequence), examinations (in-chief, cross, re-examination), exhibits (`disc_exhibit`: numbering, admission/denial), proceedings/minutes, **ex-parte gate** record.
- **`disc_findings` / `disc_enquiry_report`** — charge-wise finding, evidence relied upon, reasoning, report date, IO signature/approval method; AI-assist metadata.
- **`disc_representation`**, **`disc_final_order`** — report communication, deadline, representation received, DA review, per-charge agree/disagree + reason, proposed/final action, speaking order, approval, immutable issued order.
- **`disc_suspension`** (+ review, revocation, subsistence reference) — see its section.
- **`disc_appeal`** — appeal allowed?, due date, authority (matrix), filed date, grounds, documents, hearing, decision/order, service, review/revision, closure.
- **`disc_material_access`** — per-document disclosure classification and grants to the employee/representative.
- **`disc_legal_hold`**, **`disc_retention`** — see privacy section.
- **Shared services (not disciplinary-specific):** communications (`comm_*`), documents/templates/PDF, generic attachments, numbering, deadlines — designed once, usable by GRC, liaison and other modules.

## Roles & Segregation
Proposed roles (staff roles map to the existing role/permission/RLS pattern; the employee uses the portal, not a role):
| Role | Core permissions (concept) |
|---|---|
| HR Case Initiator | create incident, add facts/documents; **cannot** approve or issue |
| HR Case Manager | manage case workflow, draft documents, record service/replies; sees only assigned/in-scope cases |
| Preliminary Fact-Finding Officer | record PFF only; no access to later-stage decisions |
| Disciplinary Authority | decide G1/G2/G4; approve/issue final order (authority resolved from the matrix) |
| Inquiry Officer | conduct hearings, record proceedings, submit findings; no access to PFF working notes unless disclosed |
| Presenting Officer | present management case; sees management evidence; no access to IO deliberations |
| Legal Reviewer | review documents/templates; read-only on case content |
| Appeal Authority | decide appeals; no prior role in the same case |
| Auditor / read-only | read-only, content-redacted by default; audit trail access |
| Employee external portal | token-scoped: own SCN/charge sheet/notices/permitted material; submit reply |
**Segregation safeguards (configurable matrix, default DENY for conflicting combinations, exceptions only by recorded reason and approval):** the same person cannot hold, in one case, more than one of {PFF Officer, Inquiry Officer, Presenting Officer, Disciplinary Authority, Appeal Authority}; the initiator/author of a document cannot be its sole approver; IO and PO must be different people and neither may be the DA or a witness; a person with a conflict declaration is blocked from the role; an appeal authority may not have decided the order; the employee's own case is never visible to that employee's staff account (self-case block). The conflict matrix and any permitted overlaps are an owner/legal decision.
**Access model:** visibility = RLS entity/location/department scope **and** case-team membership **and** case confidentiality level (not scope alone). Normal HR users and `HEAD_HR` do not automatically see every case. Elevated "break-glass" access, if the owner wants it, needs a reason and is audited.

## Employee Reply Portal Design
Employee needs **no HRMS account**. Access is through a narrowly scoped server function (Edge Function / RPC) that verifies the token — not through the staff RLS path and never with a broad service credential exposed to the browser.
- **Token:** random case-specific token (≥ 128 bits from a CSPRNG), delivered by the approved channel; **only a hash is stored**; short-lived, expiring, revocable, single case/employee scope; case ids in URLs are never sequential or guessable.
- **OTP:** one-time code to an approved contact (channel/provider owner decision); stored hashed, short expiry, limited attempts; **attempt/rate limiting** per token and per source, lock-out with HR notification; token revocation by HR at any time.
- **Allowed actions:** view the SCN and annexures (watermark/verification reference), save draft, type reply, attach files (type/size limits, malware scanning where provider supports), declaration/confirmation, **final submit**. After submit the reply is immutable; an acknowledgement/receipt PDF (number, timestamp, hash) is produced and communicated. Drafts are mutable and not visible to management.
- **Isolation:** no listing, search or access to any other case or employee; every call re-validates token + OTP session; tokens never grant staff access.
- **Security audit events (minimal):** token issued/revoked/expired, OTP sent/failed/verified, view, draft saved, submitted, with timestamp and outcome. Do **not** store invasive device data; a coarse keyed hash of the network address only if the owner approves it for abuse control.
- **Non-digital route:** HR records a **physical reply** (received date, mode, who received, scan of the reply, service/submission evidence) as a first-class reply with the same immutability once recorded; the case workflow treats both identically.
Owner decisions: OTP provider/channel, approved-contact policy, language support, accessibility requirements, link lifetime.

## Document Lifecycle & PDF Design
Every formal document (SCN, charge sheet, hearing notice, appointment order, enquiry report communication, representation notice, final order, appeal order, acknowledgement) follows `DRAFT → UNDER_REVIEW → APPROVED → ISSUED → SERVED`, with controlled terminal/side states `WITHDRAWN`, `CANCELLED`, `SUPERSEDED`.
- **Immutability:** once `ISSUED` the content, template version and file are frozen; the stored **SHA-256** of the issued PDF is the integrity anchor. No silent edits: a correction creates a **new document/version** with a mandatory reason, linked to the prior one (which becomes `SUPERSEDED`/`WITHDRAWN`); service history stays attached to the version actually served.
- **Stored per document:** document number (numbering rule per type), template + version, generated by, reviewed by, approved by, issued by, timestamps, content hash, file reference, service history, verification reference.
- **Templates:** configurable, versioned, effective-dated (SCN, charge sheet, hearing notice, appointment order, final order …) with approved merge fields; template text comes from BFCL/legal — none is invented. Language/translation rules are an owner decision.
- **PDF / print / email:** PDF produced by a server-side renderer from the approved version (renderer choice open); print uses the same PDF; email via the shared communications service; each rendition carries the document number and a **verification reference / QR** pointing to a minimal verification page (document type, number, issue date, hash match — **no personal data**).
- **Signing:** none assumed. Options (approval-stamp only, scanned wet signature, DSC, Aadhaar e-sign) are an owner/legal decision; the lifecycle records the method used.
- **AI assistance:** AI may help format or draft text only when explicitly invoked by a user; AI-assisted drafts are flagged in audit metadata (who invoked, which version) until a human approves the final text; AI never produces findings, guilt, or punishment recommendations and is never invoked automatically.

## Communication Service Design
A **reusable communications layer**, not email code inside the disciplinary module. Used by SCN, charge sheet, hearing notice, reminders, enquiry-report communication, representation notice, final order, appeal communication and future modules (GRC, liaison, alerts).
Concept: `comm_template` (versioned) → `comm_message` (channel, recipient reference not copy, subject, body/attachment references, linked business object, idempotency key, state) → `comm_attempt` (provider response, timestamps). **States:** `queued → sending → sent → delivered` (where the provider reports it) / `bounced` / `failed` / `retrying` / `cancelled`. Content and history are retained and immutable after send; retries and back-off are configurable; provider webhooks update delivery state; failures raise a task for HR (a failed notice is a *service failure* in the register). The existing `notification` table stays the in-app alert store (or is bridged); it cannot serve as the outbound layer today (compliance-only categories/links, three states, no provider). Provider selection and credentials are an **owner decision**; the layer is provider-agnostic (adapter per provider). Logs avoid personal content; message bodies are stored under the same confidentiality as the case.

## Legal / Standing Order Configuration
Everything legal is **configuration, not code**, versioned and effective-dated, each entry carrying a legal source reference and approver:
- **Applicability snapshot inputs:** applicable law, jurisdiction/appropriate government, establishment/location, worker/non-worker category (classification rule supplied by BFCL), Certified Standing Orders document + version in force on the incident date, service rule/policy version, misconduct/discipline clause catalogue.
- **Authority matrix** (versioned; roles, not people), **appeal matrix**.
- **Deadline rules:** period length, calendar vs working days (working-day calendar), start event, reminder offsets, extension limits — **no period is hard-coded**; an unapproved rule blocks use.
- **Deemed-service rules** per service mode, if any are legally recognised — configuration only.
- **Hearing/adjournment, ex-parte, appeal, suspension/subsistence and retention rules** likewise.
The case stores the **snapshot** at incident date (and the rule versions applied at each later step); changing the registry never rewrites an existing case. The Standing Orders and clause text must be supplied by BFCL (not provided). Legal review of the configured rule set is a go-live gate.

## Domestic Enquiry Controls
- **Appointment & roles:** appointment order (controlled document); IO, PO, defence assistant/representative; each appointee signs a **conflict-of-interest declaration**; recusal and replacement of IO/PO recorded with reason; employee objection to IO/PO (where applicable) recorded with the decision on it.
- **Hearing management:** hearing notice (document + service), date/time/place/mode (in person/virtual as permitted), language/interpreter requirement, attendance, adjournments (reason, requested-by, next date), non-appearance with service proof.
- **Evidence:** management and employee witness lists with sequence; examination in-chief / cross / re-examination records; exhibits numbered with admission/denial per document; proceedings/minutes (controlled, signed-off by method per owner decision).
- **Ex-parte safeguard (controlled gate):** a missed hearing alone never opens an ex-parte route. The gate is available only when a **configurable prerequisite checklist** is satisfied and evidenced — for example valid notice/service proven, opportunity actually given, absence recorded, adjournment/opportunity history present — and then only by an **authorized decision with written reason** (G3). The checklist items and thresholds are legal-review configuration; the system enforces completeness, it does not decide.
- **Charge-wise lifecycle:** each charge moves independently (open → evidence → finding), supporting different results per charge.
- **No auto-conclusions:** the system never generates the substantive finding; AI help is limited to explicitly invoked formatting/drafting with flagged metadata until human approval.

## Suspension & Subsistence Design
Track **rule, period and status only** — **no payroll engine**. Records: suspension order (controlled document), effective date, reason/basis, competent authority (matrix), review dates and review outcomes, revocation/reinstatement, enquiry-delay **ageing** with **attribution of delay** (reason catalogue, e.g. management / employee / enquiry / external — categories owner-defined), subsistence-allowance **rule version** (configuration with legal source), and references for amounts due/paid (reference numbers/amount fields entered or received from payroll). Calculation and payment belong to payroll when that capability is defined; the disciplinary module exposes an interface (read of period/rule, write-back of payment reference). Payroll interface and the subsistence rule are open dependencies.

## Privacy / Retention / Legal Hold
- **Classification:** all content is highly confidential personal employment data; attachments carry their own classification (e.g. general / confidential / privileged-legal); **privileged or confidential materials are never disclosed automatically** — disclosure to the employee is an explicit, recorded classification per document (`disc_material_access`), not inferred.
- **Access:** need-to-know (scope + case team + confidentiality level); field-level permissions (reuse `field_role_access`); no case content in generic dashboards beyond counts the viewer is entitled to; attachment access checks on every read.
- **Audit of sensitive reads** where warranted: viewing a case file, a confidential/privileged attachment, or an export is logged (who/when/what object; no content).
- **Exports:** restricted by a separate permission, redaction of sensitive fields by default, logged like `export_log`.
- **Retention:** retention rules are configuration (class of record → period → trigger → action) — **no period is assumed**; BFCL/legal must approve. **Legal hold:** a hold flag on a case suspends disposal and blocks edits to retention; set/released with reason, authority and audit. **Archival:** closed cases move to a read-only archive state with unchanged access control. **Controlled disposal:** only after retention expiry, no hold, and two-person approval, producing a disposal certificate and an audit entry; backups follow the same policy.
- **DEV:** only pseudonymised or synthetic data until the owner explicitly approves real personal data.

## Register & Dashboard Design
**Permanent Disciplinary Register** (one row per case; sensitive columns subject to field-level permission and export rules): case no.; employee; employee code; entity/location/department; incident date; allegation/category; Standing Order/policy clause; SCN no./date; service date; reply due; reply received; charge sheet no./date; enquiry initiated; IO; PO; hearings (count, next date); suspension status; enquiry report date; charge-wise result; final action/order (no. and date); appeal (status/decision); final closure; ageing (days since incident / since stage start). Rows outside a user's access are not shown, counted or hinted.
**Dashboard metrics (counts and ageing only; no targets, no RAG thresholds):** open incidents · SCN awaiting issue · SCN awaiting reply · reply overdue · charge sheets open · enquiries pending · hearing due · adjourned cases · suspension cases · ageing buckets 30 / >60 / >90 days · enquiry report pending · representation pending · final orders pending · appeals pending · service failures. Each tile drills into the register filtered the same way; drill-down and counts honour RLS **and** case confidentiality (no existence leakage through totals). Targets/SLAs appear only once approved rules exist.

## Dependencies & Owner Decisions
**Not available / not provided — nothing here may be invented:**
Employee Master source (missing) · BFCL Certified Standing Orders / source document · approved disciplinary / competent-authority matrix · worker vs non-worker classification · SCN, charge-sheet, hearing-notice, enquiry-appointment and final-order templates · appeal/review rules · reply/deadline rules · service rules (incl. any deemed service) · suspension/subsistence rules · retention / legal-hold policy · email provider · OTP provider · PDF generation approach · signing / DSC / e-sign decision · payroll interface for subsistence · language/translation rules · attachment storage choice (existing: Google Drive / Supabase Storage / external link).
**Owner decisions required:** approve this domain design and the "dedicated transactional domain" (not `exception`); role set and segregation matrix incl. any permitted overlaps; confidentiality levels and break-glass policy; provider choices (email, OTP, PDF, e-sign); portal link lifetime/OTP policy/language; document set and who approves what; whether AI-assisted drafting is allowed at all and for which documents; DEV data policy; retention and legal-hold governance; which dashboard counts management may see without case access.
**Historical migration:** the source audit found **no disciplinary workbook**. No import mapping is designed from unrelated files. If historical cases are supplied later they get a separate, audited mapping; the transactional UI/API is the primary creation path.

## Recommended Build Sequence
Each step is a new migration set (never touching 0001–0039), RLS-first, live-verified and hash-locked, and **blocked until its inputs exist**; legal review of configuration is a gate before any real case is used.
0. **Prerequisites/foundations:** Employee Master (needs a source file); legal-configuration registry (Standing Orders, clauses, matrices, rules — needs BFCL/legal content); generic attachments with confidentiality; case-access (case team + confidentiality) framework; document/template/PDF/hash service; communications service core (provider decision). Several of these also serve GRC/liaison, so they are built once as shared services.
1. **Case + Preliminary Fact Finding + legal snapshot + authority matrix + register skeleton.**
2. **SCN document lifecycle + service register + deadline/extension engine + recorded physical reply.**
3. **Employee reply portal** (token/OTP) and digital reply with receipt.
4. **Decision gates + charge sheet** (multi-charge).
5. **Domestic enquiry** (appointment, conflicts, hearings, witnesses/exhibits, adjournments, ex-parte gate) **+ suspension tracking.**
6. **Findings/enquiry report, representation, final order, appeal/review, closure.**
7. **Dashboard, restricted exports, retention/legal hold/archival; UAT with legal review.**
Relation to the approved module order (`PHASE3_TARGET_DESIGN.md`): masters → GRC → liaison → contractor → plant visit proceeds independently; the shared services (documents, communications, attachments) are best introduced with the first module that needs them and then reused here. Disciplinary build starts only after the employee master, Standing Orders, authority matrix and provider decisions are available.

## Roadmap Changes
Applied in `docs/IMPLEMENTATION_PLAN.md` (current status updated, history untouched): source workbooks received and audited; Phase 1 audit, Phase 2 cleaning (corrected) and Phase 3 mapping/design recorded as done; migrations 0001–0039 recorded as frozen/locked; generic "Cases" replaced by **9d Disciplinary, SCN & Domestic Enquiry Management** (with 9a GRC, 9b Liaison, 9c Plant Visit as separate rows); Contractor Cost separated from Contractor Compliance; Communications recorded as a shared service; "Import mappings: blocked, no workbooks" replaced by the real status (mapped, not implemented, waiting on modules and owner decisions; no disciplinary source). `FROZEN.md` and `PRODUCTION_READINESS.md` updated for 0039 and the received files.
