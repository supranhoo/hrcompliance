> **SUPERSEDED (2026-10-05):** all owner decisions are now tracked in `docs/OWNER_DECISION_PACK_PHASE4.md` (group 8 carries these rows). Kept for history.

# Owner decision pack

Defaults are proposals only; nothing here is decided until the owner confirms. "Before PROD" = must be decided before production go-live.

| # | Decision | Options | Recommended default | Impact | Changeable later? | Before PROD? |
|---|---|---|---|---|---|---|
| 1 | Scheduler rollout gates (pg_cron) | (a) stay manual; (b) enable the 3 approved schedules (compliance 06:30, exception 07:15, alert 07:30 IST daily) after gates; (c) other cadence | (b) only after: UNROUTABLE_ESCALATION configured, 1 week of manual runs clean, backup restore proven, owner sign-off | Automatic obligations/exceptions/alerts; wrong routing = noisy or lost alerts | Yes (schedule is config) | Yes |
| 2 | Production escalation recipients (UNROUTABLE_ESCALATION, OWNER_FALLBACK) | named role / named people / department head | Named role(s) with at least two members, no single person | Unroutable alerts have nobody to reach otherwise | Yes | Yes |
| 3 | Four unimplemented runners (the 4 placeholder jobs) | implement each after behaviour approved; keep disabled; remove | Keep disabled; approve behaviour per job first | Features such as those jobs' outputs don't run; database refuses enabling | Yes | Only if their features are needed at launch |
| 4 | Responsible departments (`compliance_master.owner_department_id`) | assign per obligation; leave blank (global scope) | Assign for every obligation before enabling department-scoped users | Department-scoped users see only obligations of their departments and unassigned ones | Yes | Yes |
| 5 | Role-permission matrix | accept current seeded matrix; adjust per role | Review all 24 permissions per role with HR/compliance leads | Defines who can read/write/export/administer | Yes (Roles screen, audited) | Yes |
| 6 | Retention policy (audit, export log, evidence, notifications) | indefinite; fixed years; per record type | Keep audit/export log indefinitely; evidence per statutory period set by Legal (not invented here) | Storage growth, legal exposure | Yes, but deletion is irreversible | Yes |
| 7 | Report definitions (targets, RAG thresholds, "critical", horizons) | none (current: counts only); owner-defined targets | Define targets/RAG only when Legal/HR provide them (D-042, D-043) | Dashboards stay factual without targets | Yes | No (can launch counts-only) |
| 8 | Source workbooks / real import mappings | provide workbooks; keep manual entry | Provide workbooks; import mappings are not invented | Data load cannot start without them | Yes | Yes if bulk load is required |
| 9 | Backup/restore proof | manual test restore; PITR add-on | Enable PITR + one proven restore | Recovery confidence | Yes | Yes |
| 10 | Super Admin unroutable fallback | DEV-only (current); allowed in PROD | Keep DEV-only | Prevents silent routing to one account in PROD | Yes | Yes (confirm) |
