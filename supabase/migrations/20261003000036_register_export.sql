-- 0036 Register export: permission + append-only export log + read model.
-- Exporting is a data-leaving-the-system event, so it is (a) a separate permission (report.export), (b) always logged with who/what/filters/row count, (c) fail-closed: the UI downloads only after the log row exists.
-- The rows themselves are fetched through the normal RLS-protected views, so an export can never contain more than the user can already see (role permissions AND entity/location/department scope).
-- Granted by default to SUPER_ADMIN and HEAD_HR; everything else is a role-permission change on the Roles & Permissions screen (audited). No edit/delete of log rows through the API.
-- Rollback: drop view public.v_export_log; drop function public.export_record(text, jsonb, int, boolean); drop table public.export_log; delete from public.role_permission where permission_code = 'report.export'; delete from public.permission where code = 'report.export'.
insert into public.permission(code, module, description) values ('report.export', 'report', 'Export registers to CSV (logged)') on conflict do nothing;
insert into public.role_permission(role_id, permission_code) select id, 'report.export' from public.role where code in ('SUPER_ADMIN','HEAD_HR') on conflict do nothing;

create table public.export_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_user(id),
  register text not null check (register ~ '^[a-z][a-z0-9_-]{1,60}$'),
  filters jsonb not null default '{}'::jsonb,
  row_count int not null check (row_count >= 0),
  limit_reached boolean not null default false,
  created_at timestamptz not null default now()
);
create index export_log_user_idx on public.export_log(user_id, created_at desc);
alter table public.export_log enable row level security; alter table public.export_log force row level security;
grant select, insert on public.export_log to authenticated;
create policy export_log_sel on public.export_log for select to authenticated
  using (user_id = app.current_user_id() or app.has_permission('audit.read'));
create policy export_log_ins on public.export_log for insert to authenticated
  with check (user_id = app.current_user_id() and app.has_permission('report.export'));

create or replace function public.export_record(p_register text, p_filters jsonb, p_row_count int, p_limit_reached boolean) returns uuid
language plpgsql security invoker as $$
declare id uuid;
begin
  if not app.has_permission('report.export') then raise exception 'you do not have permission to export' using errcode = '42501'; end if;
  insert into public.export_log(user_id, register, filters, row_count, limit_reached) values (app.current_user_id(), p_register, coalesce(p_filters, '{}'::jsonb), p_row_count, coalesce(p_limit_reached, false)) returning export_log.id into id;
  return id;
end $$;
revoke all on function public.export_record(text, jsonb, int, boolean) from public, anon;
grant execute on function public.export_record(text, jsonb, int, boolean) to authenticated;

create view public.v_export_log with (security_invoker = true) as
select l.id, l.created_at, l.register, l.filters, l.row_count, l.limit_reached, u.email::text as user_email, u.full_name
  from public.export_log l left join public.app_user u on u.id = l.user_id;
grant select on public.v_export_log to authenticated;
