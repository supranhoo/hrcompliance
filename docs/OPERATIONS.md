# Operations

**Status: design only.** Nothing here is configured or tested yet.

* **Bootstrap first Super Admin** (once per environment, by a project owner using the service role / SQL editor):
  `insert into app_user(email,full_name,scope_all) values ('<email>','<name>',true);` then insert into `user_role` with role `SUPER_ADMIN`. The person then signs in with Google.
* **Backups (to define before go-live):** Supabase PITR/daily backups, a monthly restore drill into a scratch project, exported configuration (`field_definition`, `lov_*`, `rule_definition`, `numbering_rule`…) committed or stored in Drive, Drive folder ownership held by a BFCL service account with a second owner. **No backup is configured or verified today.**
* **Jobs / health (Phase 12):** `job_run` table, Job Monitor and System Health pages. Not started.
