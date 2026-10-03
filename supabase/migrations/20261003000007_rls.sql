-- 0007 Row Level Security + grants. Default posture: deny. anon has no access to anything.
-- Policy model:  read = <module>.read permission,  write = <module>.write permission,  hard DELETE only where noted.
-- Masters use soft-delete (is_active=false); hard DELETE is not granted to API roles.
-- Rollback: alter table ... disable row level security; (re-grant as needed).

-- Supabase (and our test shim) grants ALL on new public tables to anon/authenticated by default; RLS alone is
-- not enough (e.g. an absent DELETE policy silently deletes 0 rows instead of erroring). Reset, then grant minimally.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

-- Permission catalogue (additive; later phases add their own codes in their migrations).
insert into public.permission (code, module, description) values
  ('master.read','master','View organisation & reference masters'),
  ('master.write','master','Create/edit organisation & reference masters'),
  ('config.read','config','View configuration (fields, LOVs, rules, numbering)'),
  ('config.write','config','Edit configuration (fields, LOVs, rules, numbering)'),
  ('user.read','admin','View users, roles, scopes'),
  ('user.admin','admin','Manage users, roles, scopes'),
  ('audit.read','admin','View audit log');

-- ---------- generic masters ----------
do $$
declare t text;
begin
  foreach t in array array['entity','business_unit','unit','department','designation','authority','law','document_type']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (app.has_permission(%L))', t||'_sel', t, 'master.read');
    execute format('create policy %I on public.%I for insert to authenticated with check (app.has_permission(%L))', t||'_ins', t, 'master.write');
    execute format('create policy %I on public.%I for update to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))', t||'_upd', t, 'master.write', 'master.write');
  end loop;
end $$;

-- location: readable by all master readers (needed for pick-lists); writes are scope-restricted.
alter table public.location enable row level security;
alter table public.location force row level security;
grant select, insert, update on public.location to authenticated;
create policy location_sel on public.location for select to authenticated using (app.has_permission('master.read'));
create policy location_ins on public.location for insert to authenticated
  with check (app.has_permission('master.write') and app.in_scope(entity_id, id));
create policy location_upd on public.location for update to authenticated
  using (app.has_permission('master.write') and app.in_scope(entity_id, id))
  with check (app.has_permission('master.write') and app.in_scope(entity_id, id));

-- ---------- configuration ----------
do $$
declare t text;
begin
  foreach t in array array['lov_set','lov_value','rule_definition','field_definition','form_section','form_section_field','field_role_access','numbering_rule']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (app.current_user_id() is not null)', t||'_sel', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (app.has_permission(%L))', t||'_ins', t, 'config.write');
    execute format('create policy %I on public.%I for update to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))', t||'_upd', t, 'config.write', 'config.write');
    execute format('create policy %I on public.%I for delete to authenticated using (app.has_permission(%L))', t||'_del', t, 'config.write');
  end loop;
end $$;
-- System LOV sets can never be hard-deleted from the API.
drop policy lov_set_del on public.lov_set;
create policy lov_set_del on public.lov_set for delete to authenticated using (app.has_permission('config.write') and not is_system);

-- number_counter: no API access at all (allocation only through app.next_business_id).
alter table public.number_counter enable row level security;
alter table public.number_counter force row level security;
revoke all on public.number_counter from authenticated;

-- ---------- identity ----------
alter table public.app_user enable row level security;  alter table public.app_user force row level security;
alter table public.role enable row level security;      alter table public.role force row level security;
alter table public.permission enable row level security; alter table public.permission force row level security;
alter table public.role_permission enable row level security; alter table public.role_permission force row level security;
alter table public.user_role enable row level security;  alter table public.user_role force row level security;
alter table public.user_scope enable row level security; alter table public.user_scope force row level security;

grant select, insert, update on public.app_user to authenticated;
grant select, insert, update, delete on public.role, public.role_permission, public.user_role, public.user_scope to authenticated;
grant select on public.permission to authenticated;

create policy app_user_sel on public.app_user for select to authenticated
  using (auth_user_id = auth.uid() or app.has_permission('user.read') or app.has_permission('user.admin'));
create policy app_user_ins on public.app_user for insert to authenticated with check (app.has_permission('user.admin'));
create policy app_user_upd on public.app_user for update to authenticated
  using (app.has_permission('user.admin')) with check (app.has_permission('user.admin'));

create policy permission_sel on public.permission for select to authenticated using (app.current_user_id() is not null);
create policy role_sel on public.role for select to authenticated using (app.current_user_id() is not null);
create policy role_mod on public.role for all to authenticated
  using (app.has_permission('user.admin') and not is_system) with check (app.has_permission('user.admin') and not is_system);
create policy role_permission_sel on public.role_permission for select to authenticated using (app.current_user_id() is not null);
create policy role_permission_mod on public.role_permission for all to authenticated
  using (app.has_permission('user.admin')) with check (app.has_permission('user.admin'));
create policy user_role_sel on public.user_role for select to authenticated
  using (user_id = app.current_user_id() or app.has_permission('user.read') or app.has_permission('user.admin'));
create policy user_role_mod on public.user_role for all to authenticated
  using (app.has_permission('user.admin')) with check (app.has_permission('user.admin'));
create policy user_scope_sel on public.user_scope for select to authenticated
  using (user_id = app.current_user_id() or app.has_permission('user.read') or app.has_permission('user.admin'));
create policy user_scope_mod on public.user_scope for all to authenticated
  using (app.has_permission('user.admin')) with check (app.has_permission('user.admin'));

-- ---------- audit: readable by audit.read only; never writable via API (rows are written by SECURITY DEFINER trigger) ----------
alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;
revoke all on public.audit_log from authenticated;
grant select on public.audit_log to authenticated;
create policy audit_log_sel on public.audit_log for select to authenticated using (app.has_permission('audit.read'));
