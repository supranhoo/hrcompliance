-- 0035 Jobs without a runner are disabled definitions, and cannot be enabled until a runner exists.
-- Owner decision (2026-10-04): due_status_refresh, licence_expiry_detection, communication_followup and housekeeping have no agreed module behaviour or acceptance rules, so no runner is invented.
-- They are kept as DISABLED definitions (the schedule_cron stays as the approved placeholder, D-036). A trigger now refuses to enable any job whose runner is null, whatever the path
-- (Job Monitor RPC, API, SQL editor). Adding a runner later is a deliberate migration that sets job_definition.runner for that code; only then can the job be enabled.
-- Rollback: drop trigger job_definition_requires_runner on public.job_definition; drop function app.job_requires_runner(); update public.job_definition set is_enabled = true where code in ('due_status_refresh','licence_expiry_detection','communication_followup','housekeeping').
create or replace function app.job_requires_runner() returns trigger language plpgsql as $$
begin
  if new.runner is null and new.is_enabled then
    if tg_op = 'INSERT' then new.is_enabled := false;        -- a new definition without a runner starts disabled (also keeps the idempotent seed re-run working)
    elsif not old.is_enabled then
      raise exception 'job % has no runner yet, so it cannot be enabled until its behaviour is agreed and implemented', new.code using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

-- disable first (the guard is added after, so this statement is never blocked by it), with an audit reason
select set_config('app.audit_reason', 'No runner exists yet; module behaviour to be agreed (owner decision 2026-10-04)', true);
update public.job_definition set is_enabled = false where runner is null and is_enabled;

create trigger job_definition_requires_runner before insert or update on public.job_definition for each row execute function app.job_requires_runner();
