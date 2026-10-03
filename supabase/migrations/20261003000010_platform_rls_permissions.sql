-- 0010 Permissions, grants and RLS for 0008/0009 tables. (Every table migration owns its own grants — D-003.)
insert into public.permission (code, module, description) values
  ('health.read','admin','View system health'),
  ('job.read','admin','View scheduled jobs and runs'),
  ('job.manage','admin','Enable/disable and edit job definitions')
on conflict (code) do nothing;

do $$
declare t text;
begin
  -- readable by any provisioned user (UI renders from these); writable with config.write
  foreach t in array array['module_definition','status_definition','status_transition','config_definition']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (app.current_user_id() is not null)', t||'_sel', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (app.has_permission(%L))', t||'_ins', t, 'config.write');
    execute format('create policy %I on public.%I for update to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))', t||'_upd', t, 'config.write', 'config.write');
  end loop;
end $$;

alter table public.system_config enable row level security;  alter table public.system_config force row level security;
grant select, insert, update on public.system_config to authenticated;
create policy system_config_sel on public.system_config for select to authenticated using (app.has_permission('config.read'));
create policy system_config_ins on public.system_config for insert to authenticated with check (app.has_permission('config.write'));
create policy system_config_upd on public.system_config for update to authenticated
  using (app.has_permission('config.write')) with check (app.has_permission('config.write'));

alter table public.job_definition enable row level security;  alter table public.job_definition force row level security;
grant select, update on public.job_definition to authenticated;
create policy job_definition_sel on public.job_definition for select to authenticated using (app.has_permission('job.read'));
create policy job_definition_upd on public.job_definition for update to authenticated
  using (app.has_permission('job.manage')) with check (app.has_permission('job.manage'));

alter table public.job_run enable row level security;  alter table public.job_run force row level security;
grant select on public.job_run to authenticated;     -- no API writes: runners use service_role via app.job_start/job_finish
create policy job_run_sel on public.job_run for select to authenticated using (app.has_permission('job.read'));
