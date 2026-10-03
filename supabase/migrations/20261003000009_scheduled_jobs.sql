-- 0009 Scheduled job framework: definitions, idempotent/retry-safe runs, system health RPC.
-- Runners (Edge Functions / pg_cron) call app.job_start / app.job_finish with the service role. Nothing here is API-writable.
-- Rollback: drop function public.system_health, app.job_finish, app.job_start; drop table job_run, job_definition.

create table public.job_definition (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  name text not null, description text,
  schedule_cron text,                         -- documentation/metadata for the scheduler (null = manual only)
  is_enabled boolean not null default true,
  max_attempts int not null default 3 check (max_attempts between 1 and 10),
  timeout_seconds int not null default 900 check (timeout_seconds between 10 and 86400),
  retry_backoff_seconds int not null default 300 check (retry_backoff_seconds >= 0),
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);

create table public.job_run (
  id uuid primary key default gen_random_uuid(),
  job_code text not null references public.job_definition(code),
  idempotency_key text not null,              -- e.g. '2026-10' for a monthly run: one logical run per key
  status text not null default 'running' check (status in ('running','succeeded','failed','retry_wait','skipped')),
  attempt int not null default 1,
  triggered_by text not null default 'schedule' check (triggered_by in ('schedule','manual','retry')),
  environment text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  records_processed int check (records_processed is null or records_processed >= 0),
  error_detail jsonb,
  next_retry_at timestamptz,
  created_at timestamptz not null default now(),
  unique (job_code, idempotency_key)
);
create index job_run_recent_idx on public.job_run(job_code, started_at desc);
create index job_run_failed_idx on public.job_run(started_at desc) where status in ('failed','retry_wait');

-- Claim a run. Returns run_id and whether the caller should execute. Concurrency-safe (unique key + row lock).
create or replace function app.job_start(p_job text, p_key text, p_env text default null, p_trigger text default 'schedule')
returns table (run_id uuid, should_run boolean, reason text)
language plpgsql security definer set search_path = public as $$
declare d public.job_definition; r public.job_run;
begin
  select * into d from public.job_definition where code = p_job;
  if not found then raise exception 'Unknown job %', p_job using errcode = '22023'; end if;
  if not d.is_enabled then return query select null::uuid, false, 'job disabled'; return; end if;

  insert into public.job_run (job_code, idempotency_key, environment, triggered_by)
  values (p_job, p_key, p_env, p_trigger)
  on conflict (job_code, idempotency_key) do nothing returning * into r;
  if found then return query select r.id, true, 'started'; return; end if;

  select * into r from public.job_run where job_code = p_job and idempotency_key = p_key for update;
  if r.status = 'succeeded' then return query select r.id, false, 'already succeeded'; return; end if;
  if r.status = 'running' and r.started_at > now() - make_interval(secs => d.timeout_seconds) then
    return query select r.id, false, 'already running'; return;
  end if;
  if r.attempt >= d.max_attempts then
    return query select r.id, false, 'max attempts reached'; return;
  end if;
  if r.status = 'retry_wait' and r.next_retry_at > now() then
    return query select r.id, false, 'waiting for retry window'; return;
  end if;
  -- failed, retry_wait (due) or stale 'running' (crashed runner): reclaim
  update public.job_run set status = 'running', attempt = attempt + 1, started_at = now(), completed_at = null,
         triggered_by = 'retry', next_retry_at = null where id = r.id;
  return query select r.id, true, 'retry';
end $$;

create or replace function app.job_finish(p_run uuid, p_ok boolean, p_records int default null, p_error jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare r public.job_run; d public.job_definition;
begin
  select * into r from public.job_run where id = p_run for update;
  if not found then raise exception 'Unknown run %', p_run using errcode = '22023'; end if;
  select * into d from public.job_definition where code = r.job_code;
  if p_ok then
    update public.job_run set status = 'succeeded', completed_at = now(), records_processed = p_records, error_detail = null, next_retry_at = null where id = p_run;
  elsif r.attempt < d.max_attempts then
    update public.job_run set status = 'retry_wait', completed_at = now(), records_processed = p_records, error_detail = p_error,
           next_retry_at = now() + make_interval(secs => d.retry_backoff_seconds * r.attempt) where id = p_run;
  else
    update public.job_run set status = 'failed', completed_at = now(), records_processed = p_records, error_detail = p_error, next_retry_at = null where id = p_run;
  end if;
end $$;
revoke all on function app.job_start(text, text, text, text), app.job_finish(uuid, boolean, int, jsonb) from public;
grant execute on function app.job_start(text, text, text, text), app.job_finish(uuid, boolean, int, jsonb) to service_role;

create trigger job_definition_stamp before insert or update on public.job_definition for each row execute function app.stamp_row();
create trigger audit_job_definition after insert or update or delete on public.job_definition for each row execute function app.audit_row();

-- System health snapshot for the admin page. Contains no secrets, hostnames or keys.
create or replace function public.system_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_schema text; v_last jsonb; v_failed jsonb; v_cfg jsonb;
begin
  if not app.has_permission('health.read') then raise exception 'permission denied' using errcode = '42501'; end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_schema;
  end if;
  select to_jsonb(j) into v_last from (select job_code, status, started_at, completed_at, records_processed from public.job_run order by started_at desc limit 1) j;
  select to_jsonb(j) into v_failed from (select job_code, status, started_at, attempt, error_detail ->> 'message' as message
                                           from public.job_run where status in ('failed','retry_wait') order by started_at desc limit 1) j;
  select coalesce(jsonb_object_agg(replace(key, 'integration.', ''), value -> 'state'), '{}'::jsonb) into v_cfg
    from public.system_config where key like 'integration.%';
  return jsonb_build_object(
    'database', jsonb_build_object('connected', true, 'server_time', now(), 'postgres_major', current_setting('server_version_num')::int / 10000),
    'schema_version', v_schema,
    'integrations', v_cfg,
    'latest_job', v_last, 'latest_failed_job', v_failed,
    'jobs_failed_24h', (select count(*) from public.job_run where status in ('failed','retry_wait') and started_at > now() - interval '24 hours'));
end $$;
revoke all on function public.system_health() from public, anon;
grant execute on function public.system_health() to authenticated;
