# Source → Target Data Map  (TEMPLATE — **no source files have been received**)

Nothing below is derived from data. It defines the structure of the map that will be completed, sheet by sheet, once the workbooks are supplied
and profiled (`python3 scripts/migration/profile_workbooks.py data/source docs/migration/profile`).

## Per-sheet record (one block per worksheet)
| Field | Content |
|---|---|
| Source file / worksheet / state (visible, hidden, utility) | |
| Business purpose | agreed with BFCL after reading the profile |
| Row count, header row, key candidate columns | from profiler |
| Classification | master / transaction / configuration / calculated / historical-only |
| Target table(s) | e.g. `compliance_master`, `licence`, `compliance_instance`, `evidence` (Phase 6, built) or future module tables |
| Duplicate rule | business key + DB constraint (e.g. `UNIQUE(authority_id, licence_number)`) |
| Validation / data-quality issues | `#REF!`/`#NAME?` cells, mixed date formats, status spellings, missing keys, orphan references |

## Per-column record
| Source column | Inferred type | Formula / lookup | Target table.column | Transformation | Validation | Notes |
|---|---|---|---|---|---|---|

## Mapping targets that already exist (Phase 6) — candidates only, to be confirmed against the profile
| Likely source content | Target |
|---|---|
| Licence / registration registers (number, authority, issue/expiry, renewal) | `licence_type`, `licence`, `licence_event`; authorities → `authority` |
| Statutory calendars / compliance trackers | `compliance_master` + `compliance_rule_version` (frequency, due rule) + `compliance_applicability`; completed history → `compliance_instance` (`source='import'`) |
| Evidence indexes / Drive links | `evidence` (storage_file_id = Drive id) |
| Open issues / pending actions | `exception` (manual) |
Everything else (ESIC, GRC, disciplinary, liaison, plant visit, contractor bills/compliance) waits for its module and for the audit.

## Reconciliation (filled per import run)
| Source sheet | Source rows | Inserted | Updated | Duplicate | Skipped | Error | Unmapped | Financial total (src vs db) |
|---|---|---|---|---|---|---|---|---|
