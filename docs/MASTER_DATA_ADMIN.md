# Master Data Administration (migrations 0026–0030, `apps/web/src/admin/`)

One principle: the admin screens are **another way to enter the same data**. They write to the same tables as everything else (PostgREST under the user's own JWT), so every
constraint, trigger, RLS policy and audit rule applies unchanged. Frontend validation is early feedback; the database is the authority. Nothing here has hardcoded business lists
(risk, criticality, categories, statuses, document types, alert offsets all come from the database); the only constants in `admin/domain.ts` mirror database CHECK constraints.

## Screens (nav group "Master Data" / "Administration")
| Screen | Route | Reads | Writes | Permission (RLS-enforced) |
|---|---|---|---|---|
| Compliance Master | `/admin/compliance-masters` | `v_compliance_master` | `compliance_master` (insert/update, deactivate) | `compliance.manage` |
| Rule Versions | `/admin/rule-versions` | `v_compliance_rule_version` | `compliance_rule_version` (drafts), `compliance_rule_evidence` (drafts), RPCs below | `compliance.manage` |
| Applicability Matrix + Coverage & gaps | `/admin/applicability[/coverage]` | `v_applicability`, `v_compliance_coverage` | `compliance_applicability`, `applicability_replace`, `applicability_end` | `compliance.manage` (+ **F-1 scope**) |
| Licence Types / Licences | `/admin/licence-types`, `/licences` | `licence_type`, `v_licence_status` | `licence_type`, `licence`, `licence_event` | `compliance.manage` / `licence.write` |
| Reference data (entities, locations, laws, authorities, departments, categories, document types) | `/admin/reference/:kind` | the tables | the tables | `master.write` (`compliance.manage` for categories) |
| Lists (LOV), Statuses & transitions, Settings | `/admin/lov`, `/admin/statuses`, `/admin/settings` | `lov_*`, `status_*`, `system_config` | same | `config.write` |
| Alert Rules (+ escalation recipients, routing validation) | `/admin/alert-rules` | `v_alert_rule`, `v_alert_routing_issue` | `config_new_version('alert_rule', …)` | `config.write` |
| Exception Settings | `/admin/exception-config` | `system_config`, `lov_*`, `system_health()` | same | `config.write` |
| Imports | `/admin/imports` | `v_import_batch`, `import_row` | `import_*` functions | `import.manage` / `import.read` |

## Rules the screens enforce (and the database re-enforces)
* **Compliance Master is a stable identity.** `code` can never change (trigger `compliance_master_identity`); deactivate and create a new one instead. The master holds no rule logic.
* **Rule logic is versioned.** An effective (active/retired) version is never edited: "Create new version from this" calls `compliance_rule_new_draft()` (clones the latest version and its
  evidence requirements into one draft). A draft can be edited or discarded (`compliance_rule_discard_draft`); activating requires a **mandatory reason** through the existing
  `compliance_activate_rule_version()` which retires the previous version and runs the **F-2 reconciliation** (future untouched obligations move to the new rule; actioned ones stay pinned).
* **Due-date rule** is structured data (day of month / days after period end / fixed date / one date / days after event) paired to the frequency; plain-language preview; DB check `app.due_rule_is_valid`.
* **Applicability** keeps **F-1**: the matrix and coverage are scope-controlled (a user with no scope sees nothing — fail closed); the base Location Master is readable by all master readers.
  In-effect rows are immutable: *Replace* (new decision starts later, old one ends the day before) or *End*, both with a reason and audited. Conditions are a **whitelisted structured AST**
  (facts from location/entity, fixed operators) — no SQL, no scripting. Specificity: location > business unit > entity > state > establishment type > industry > headcount; equal-specificity
  conflicts (applicable wins) and unmapped gaps are listed under Coverage & gaps.
* **Licences**: `licence_no` is system-assigned; entity cannot change; renewal lead time defaults from the licence type and can be overridden; the expiry state is **derived** from the expiry
  date and `licence.expiry_thresholds`, never typed in. No licence data is invented.
* **Evidence requirements** (per rule-version draft): mandatory/optional, default validity (months from upload unless the uploader gives an expiry), whether a reviewer must verify, an
  instruction text. Requirements of a published version are immutable. Replacing a file keeps the version chain.
* **Lists/statuses/settings**: codes are identities and never change; values are deactivated, never deleted; values/statuses the engines rely on are **protected/system** (labels, colour and order stay editable);
  settings are type- and range-validated in the database (`app.system_config_guard`) and in the UI (`admin/settings.ts`).
* **Alert rules** are versioned data (offsets, channels, recipients `owner | role:CODE | user:uuid`, optional `critical`). **D-001**: configure BFCL's escalation recipients as rule `UNROUTABLE_ESCALATION`;
  `alert_routing_validation()` lists critical rules with no valid routing (blocking in production). Super Admin is never a production recipient.

## Optimistic locking, errors, audit
Updates carry `row_version`; a concurrent change is reported, never overwritten. Database errors are translated to plain language (`admin/errors.ts`). Every change is in the audit history (History tab on each screen).

## Adding another master
Describe it as a `MasterSpec` (fields, columns, filters, permission) and render it with `AdminRegister`; add the route and nav entry. Tests: `admin/*.test.ts(x)` show the pattern; the SQL suites 52–55 cover the backend pieces.
