-- 0032 Job Monitor read model + safe enable/disable.
-- job_definition.runner names the SQL entry point of a job (null = no runner exists yet, so the job can be described but not scheduled). v_job_status joins each job with
-- its latest run, latest success and recent failures. job_set_enabled() changes the enabled flag with a mandatory reason (audited). Scheduling itself (pg_cron) is NOT touched here
-- and remains OFF until the schedules are approved (docs/CRON_PROPOSAL.md); nothing in this migration can start an engine.
-- Rollback: drop function public.job_set_enabled(text, boolean, text); drop view public.v_job_status, public.v_job_run; alter table public.job_definition drop column runner.
alter table public.job_definition add column runner text check (runner is null or runner ~ '^app\.[a-z_]+\(text\)$');
update public.job_definition set runner = case code
  when 'compliance_generation' then 'app.run_compliance_generation(text)' when 'exception_generation' then 'app.run_exception_detection(text)' when 'alert_generation' then 'app.run_alert_generation(text)' end
 where code in ('compliance_generation','exception_generation','alert_generation');

create view public.v_job_status with (security_invoker = true) as
select d.id, d.code, d.name, d.description, d.schedule_cron, d.is_enabled, d.max_attempts, d.timeout_seconds, d.retry_backoff_seconds, d.runner, d.row_version,
       (d.runner is not null) as has_runner,
       lr.status as last_status, lr.started_at as last_started_at, lr.completed_at as last_completed_at, lr.records_processed as last_records, lr.environment as last_environment,
       lr.error_detail ->> 'warning' as last_warning, lr.error_detail ->> 'message' as last_message,
       ls.started_at as last_success_at,
       (select count(*) from public.job_run f where f.job_code = d.code and f.status in ('failed','retry_wait') and f.started_at > now() - interval '24 hours') as failures_24h
  from public.job_definition d
  left join lateral (select * from public.job_run r where r.job_code = d.code order by r.started_at desc limit 1) lr on true
  left join lateral (select started_at from public.job_run r where r.job_code = d.code and r.status = 'succeeded' order by r.started_at desc limit 1) ls on true;
grant select on public.v_job_status to authenticated;

create view public.v_job_run with (security_invoker = true) as
select r.id, r.job_code, d.name as job_name, r.idempotency_key, r.status, r.attempt, r.triggered_by, r.environment, r.started_at, r.completed_at, r.records_processed,
       extract(epoch from (r.completed_at - r.started_at))::numeric(10,2) as duration_s, r.error_detail ->> 'message' as error_message, r.error_detail ->> 'warning' as warning, r.next_retry_at
  from public.job_run r join public.job_definition d on d.code = r.job_code;
grant select on public.v_job_run to authenticated;

create or replace function public.job_set_enabled(p_code text, p_enabled boolean, p_reason text) returns void
language plpgsql security invoker as $$
begin
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required to enable or disable a job' using errcode = '22023'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.job_definition set is_enabled = p_enabled where code = p_code;
  if not found then raise exception 'job not found or you do not have permission' using errcode = '42501'; end if;
end $$;
revoke all on function public.job_set_enabled(text, boolean, text) from public, anon;
grant execute on function public.job_set_enabled(text, boolean, text) to authenticated;
