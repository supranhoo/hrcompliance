-- 0033 Users, roles, permissions and scope administration (backend).
-- Permissions stay the single source of truth: the same role_permission rows feed my_access() (UI visibility) and app.has_permission() (RLS), so nothing here hardcodes a role name.
-- New permission role.admin separates "who may edit what roles can do / who holds which role" from user.admin ("who is a user, active or not, and which locations they see"),
-- so granting user administration to e.g. HEAD_HR cannot become self-promotion. Only SUPER_ADMIN holds role.admin by default.
-- Guards are triggers, so they hold for every path (API, RPC, SQL editor): (1) continuity - at least one active, signed-in user must keep role.admin, checked at commit so a
-- multi-row change that ends valid is allowed; (2) self-lockout - removing your own user.admin / role.admin, or disabling yourself, needs an explicit confirmation flag that only the RPCs set;
-- (3) role codes and linked emails are immutable. Role/user changes go through reason-mandatory, audited RPCs (SECURITY INVOKER: RLS and table audit triggers still apply).
-- Department scope (owner decision): department is an ADDITIONAL dimension only where the protected resource has one. A compliance obligation's department is its Compliance Master's
-- owner_department_id (null = not department-specific -> existing entity/location rules). New overloads app.in_scope/scope_ok/user_scope_ok take a department; the existing 2-dimension functions are untouched.
-- scope_all bypasses everything; global masters (location, entity, compliance master, reference/config) stay globally readable. Department scope narrows an entity/location scope, it never grants access by itself.
-- Rollback: restore the 0015/0020/0023/0024 policy and function bodies (department-aware policies, generate_alerts, compliance_coverage); drop the 3-arg/4-arg overloads and app.compliance_department/app.instance_department; drop the RPCs and views below; drop triggers *_continuity/*_selflock/role_code_immutable/app_user_identity_guard; restore policies role_mod, role_permission_mod, user_role_mod to user.admin; delete role.admin from permission.
insert into public.permission(code, module, description) values ('role.admin', 'user', 'Administer roles, role permissions and role assignments') on conflict do nothing;
insert into public.role_permission(role_id, permission_code) select id, 'role.admin' from public.role where code = 'SUPER_ADMIN' on conflict do nothing;

drop policy role_mod on public.role;
create policy role_mod on public.role for all to authenticated
  using (app.has_permission('role.admin') and not is_system) with check (app.has_permission('role.admin') and not is_system);
drop policy role_permission_mod on public.role_permission;
create policy role_permission_mod on public.role_permission for all to authenticated
  using (app.has_permission('role.admin')) with check (app.has_permission('role.admin'));
drop policy user_role_mod on public.user_role;
create policy user_role_mod on public.user_role for all to authenticated
  using (app.has_permission('role.admin')) with check (app.has_permission('role.admin'));

-- ---- guards ----
create or replace function app.admin_holders() returns bigint language sql stable security definer set search_path = public as $$
  select count(distinct u.id) from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role_permission rp on rp.role_id = ur.role_id
   where u.status = 'active' and u.auth_user_id is not null and rp.permission_code = 'role.admin'
$$;
revoke all on function app.admin_holders() from public, anon, authenticated;

create or replace function app.guard_continuity() returns trigger language plpgsql security definer set search_path = public as $$
declare lost boolean := false;
begin
  if tg_table_name = 'user_role' then
    lost := tg_op in ('DELETE','UPDATE') and exists (select 1 from public.role_permission rp where rp.role_id = old.role_id and rp.permission_code = 'role.admin');
  elsif tg_table_name = 'role_permission' then
    lost := tg_op in ('DELETE','UPDATE') and old.permission_code = 'role.admin';
  elsif tg_table_name = 'app_user' then
    lost := tg_op in ('DELETE','UPDATE') and old.status = 'active' and old.auth_user_id is not null and (tg_op = 'DELETE' or new.status <> 'active' or new.auth_user_id is null);
  end if;
  if lost and app.admin_holders() = 0 then
    raise exception 'at least one active user must keep role administration (role.admin); this change would leave none' using errcode = 'AD001';
  end if;
  return null;
end $$;
create constraint trigger user_role_continuity after update or delete on public.user_role deferrable initially deferred for each row execute function app.guard_continuity();
create constraint trigger role_permission_continuity after update or delete on public.role_permission deferrable initially deferred for each row execute function app.guard_continuity();
create constraint trigger app_user_continuity after update or delete on public.app_user deferrable initially deferred for each row execute function app.guard_continuity();

-- Permissions the caller holds, optionally ignoring one role (what would remain after removing it).
create or replace function app.actor_perms(p_without_role uuid default null) returns setof text language sql stable security definer set search_path = public as $$
  select distinct rp.permission_code from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role_permission rp on rp.role_id = ur.role_id
   where u.auth_user_id = auth.uid() and u.status = 'active' and ur.role_id is distinct from p_without_role
$$;
revoke all on function app.actor_perms(uuid) from public, anon, authenticated;

create or replace function app.guard_selflock() returns trigger language plpgsql security definer set search_path = public as $$
declare actor uuid := app.current_user_id(); crit constant text[] := array['user.admin','role.admin']; lost text[];
begin
  if actor is null or current_setting('app.confirm_self_lockout', true) = 'yes' then return coalesce(new, old); end if;
  if tg_table_name = 'user_role' then
    if old.user_id <> actor then return coalesce(new, old); end if;
    select array_agg(rp.permission_code) into lost from public.role_permission rp where rp.role_id = old.role_id and rp.permission_code = any(crit)
      and rp.permission_code not in (select * from app.actor_perms(old.role_id));
  elsif tg_table_name = 'role_permission' then
    if old.permission_code <> all(crit) or not exists (select 1 from public.user_role ur where ur.user_id = actor and ur.role_id = old.role_id) then return coalesce(new, old); end if;
    select array_agg(old.permission_code) into lost where old.permission_code not in (select * from app.actor_perms(old.role_id));
  elsif tg_table_name = 'app_user' then
    if old.id = actor and (tg_op = 'DELETE' or new.status <> 'active') then lost := array['your own access']; end if;
  end if;
  if coalesce(cardinality(lost), 0) > 0 then
    raise exception 'this change removes your own administrative access (%): confirm explicitly to proceed', array_to_string(lost, ', ') using errcode = 'AD002';
  end if;
  return coalesce(new, old);
end $$;
create trigger user_role_selflock before update or delete on public.user_role for each row execute function app.guard_selflock();
create trigger role_permission_selflock before update or delete on public.role_permission for each row execute function app.guard_selflock();
create trigger app_user_selflock before update or delete on public.app_user for each row execute function app.guard_selflock();

create or replace function app.role_code_immutable() returns trigger language plpgsql as $$
begin if new.code is distinct from old.code then raise exception 'a role code never changes' using errcode = '22023'; end if; return new; end $$;
create trigger role_code_immutable before update on public.role for each row execute function app.role_code_immutable();

create or replace function app.app_user_identity_guard() returns trigger language plpgsql as $$
begin
  if old.auth_user_id is not null and new.email is distinct from old.email then raise exception 'the email of a signed-in user cannot be changed' using errcode = '22023'; end if;
  return new;
end $$;
create trigger app_user_identity_guard before update on public.app_user for each row execute function app.app_user_identity_guard();

-- ---- read models ----
create view public.v_role_admin with (security_invoker = true) as
select r.id, r.code, r.name, r.description, r.is_system, r.row_version,
       coalesce((select array_agg(rp.permission_code order by rp.permission_code) from public.role_permission rp where rp.role_id = r.id), '{}') as permissions,
       (select count(*) from public.user_role ur where ur.role_id = r.id) as user_count,
       exists (select 1 from public.role_permission rp where rp.role_id = r.id and rp.permission_code = 'role.admin') as grants_role_admin
  from public.role r;
grant select on public.v_role_admin to authenticated;

create view public.v_user_admin with (security_invoker = true) as
select u.id, u.email::text as email, u.full_name, u.status, u.scope_all, u.last_login_at, (u.auth_user_id is not null) as signed_in, u.row_version,
       coalesce((select array_agg(r.code order by r.code) from public.user_role ur join public.role r on r.id = ur.role_id where ur.user_id = u.id), '{}') as roles,
       (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'entity') as entity_scopes,
       (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'location') as location_scopes,
       (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'department') as department_scopes,
       exists (select 1 from public.user_role ur join public.role_permission rp on rp.role_id = ur.role_id where ur.user_id = u.id and rp.permission_code = 'role.admin') as is_role_admin
  from public.app_user u;
grant select on public.v_user_admin to authenticated;

create view public.v_user_scope with (security_invoker = true) as
select s.id, s.user_id, s.scope_type, s.scope_id, coalesce(e.code, l.code, d.code) as code, coalesce(e.name, l.name, d.name) as name
  from public.user_scope s left join public.entity e on s.scope_type = 'entity' and e.id = s.scope_id left join public.location l on s.scope_type = 'location' and l.id = s.scope_id
  left join public.department d on s.scope_type = 'department' and d.id = s.scope_id;
grant select on public.v_user_scope to authenticated;

-- ---- RPCs (invoker; reason mandatory; GUC confirms a deliberate self-change) ----
create or replace function app.admin_begin(p_perm text, p_reason text, p_confirm boolean) returns void language plpgsql as $$
begin
  if not app.has_permission(p_perm) then raise exception 'you do not have permission (%)', p_perm using errcode = '42501'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required' using errcode = '22023'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  perform set_config('app.confirm_self_lockout', case when p_confirm then 'yes' else 'no' end, true);
end $$;
revoke all on function app.admin_begin(text, text, boolean) from public, anon;
grant execute on function app.admin_begin(text, text, boolean) to authenticated;

create or replace function public.role_save(p_code text, p_name text, p_description text, p_permissions text[], p_reason text, p_confirm_self boolean default false) returns uuid
language plpgsql security invoker as $$
declare rid uuid; bad text[]; perms text[] := coalesce(p_permissions, '{}');
begin
  perform app.admin_begin('role.admin', p_reason, p_confirm_self);
  if p_code is null or p_code !~ '^[A-Z][A-Z0-9_]{1,40}$' then raise exception 'role code must be upper-case letters, digits or underscore' using errcode = '22023'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'role name is required' using errcode = '22023'; end if;
  select array_agg(x) into bad from unnest(perms) x where x not in (select code from public.permission);
  if bad is not null then raise exception 'unknown permission(s): %', array_to_string(bad, ', ') using errcode = '22023'; end if;
  select id into rid from public.role where code = p_code;
  if rid is null then insert into public.role(code, name, description) values (p_code, trim(p_name), nullif(trim(coalesce(p_description,'')), '')) returning id into rid;
  else
    update public.role set name = trim(p_name), description = nullif(trim(coalesce(p_description,'')), '') where id = rid and (name, description) is distinct from (trim(p_name), nullif(trim(coalesce(p_description,'')), ''));
  end if;
  delete from public.role_permission where role_id = rid and permission_code <> all(perms);
  insert into public.role_permission(role_id, permission_code) select rid, x from unnest(perms) x on conflict do nothing;
  return rid;
end $$;

create or replace function public.user_invite(p_email text, p_full_name text, p_roles text[], p_reason text) returns uuid
language plpgsql security invoker as $$
declare uid uuid; em text := lower(trim(coalesce(p_email,'')));
begin
  perform app.admin_begin('user.admin', p_reason, false);
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'a valid email is required' using errcode = '22023'; end if;
  insert into public.app_user(email, full_name, status) values (em, nullif(trim(coalesce(p_full_name,'')), ''), 'invited') returning id into uid;
  if coalesce(cardinality(p_roles), 0) > 0 then perform public.user_set_roles(uid, p_roles, p_reason, false); end if;
  return uid;
end $$;

create or replace function public.user_set_roles(p_user uuid, p_roles text[], p_reason text, p_confirm_self boolean default false) returns void
language plpgsql security invoker as $$
declare ids uuid[]; roles text[] := coalesce(p_roles, '{}');
begin
  perform app.admin_begin('role.admin', p_reason, p_confirm_self);
  if not exists (select 1 from public.app_user where id = p_user) then raise exception 'user not found' using errcode = '42501'; end if;
  select array_agg(id) into ids from public.role where code = any(roles);
  if coalesce(cardinality(ids), 0) <> cardinality(roles) then raise exception 'unknown role in the list' using errcode = '22023'; end if;
  delete from public.user_role where user_id = p_user and role_id <> all(coalesce(ids, '{}'));
  insert into public.user_role(user_id, role_id, assigned_by) select p_user, id, app.current_user_id() from public.role where code = any(roles) on conflict do nothing;
end $$;

create or replace function public.user_set_status(p_user uuid, p_status text, p_reason text, p_confirm_self boolean default false) returns void
language plpgsql security invoker as $$
declare linked boolean;
begin
  perform app.admin_begin('user.admin', p_reason, p_confirm_self);
  if p_status not in ('active','disabled') then raise exception 'status must be active or disabled' using errcode = '22023'; end if;
  select auth_user_id is not null into linked from public.app_user where id = p_user;
  if not found then raise exception 'user not found' using errcode = '42501'; end if;
  update public.app_user set status = case when p_status = 'active' and not linked then 'invited' else p_status end where id = p_user;
end $$;

create or replace function public.user_set_scope(p_user uuid, p_scope_all boolean, p_entities uuid[], p_locations uuid[], p_departments uuid[], p_reason text) returns void
language plpgsql security invoker as $$
declare ents uuid[] := coalesce(p_entities,'{}'); locs uuid[] := coalesce(p_locations,'{}'); deps uuid[] := coalesce(p_departments,'{}'); everything boolean := coalesce(p_scope_all, false);
begin
  perform app.admin_begin('user.admin', p_reason, false);
  if not exists (select 1 from public.app_user where id = p_user) then raise exception 'user not found' using errcode = '42501'; end if;
  if everything then ents := '{}'; locs := '{}'; deps := '{}'; end if;     -- All locations bypasses entity, location and department limits
  if exists (select 1 from unnest(ents) x where x not in (select id from public.entity)) then raise exception 'unknown legal entity in scope' using errcode = '22023'; end if;
  if exists (select 1 from unnest(locs) x where x not in (select id from public.location)) then raise exception 'unknown location in scope' using errcode = '22023'; end if;
  if exists (select 1 from unnest(deps) x where x not in (select id from public.department)) then raise exception 'unknown department in scope' using errcode = '22023'; end if;
  if not everything and cardinality(ents) + cardinality(locs) = 0 then raise exception 'choose all locations or at least one entity/location (a department only narrows an entity or location scope)' using errcode = '22023'; end if;
  update public.app_user set scope_all = everything where id = p_user;
  delete from public.user_scope where user_id = p_user and not ((scope_type = 'entity' and scope_id = any(ents)) or (scope_type = 'location' and scope_id = any(locs)) or (scope_type = 'department' and scope_id = any(deps)));
  insert into public.user_scope(user_id, scope_type, scope_id) select p_user, 'entity', x from unnest(ents) x on conflict do nothing;
  insert into public.user_scope(user_id, scope_type, scope_id) select p_user, 'location', x from unnest(locs) x on conflict do nothing;
  insert into public.user_scope(user_id, scope_type, scope_id) select p_user, 'department', x from unnest(deps) x on conflict do nothing;
end $$;

do $$ declare f text; begin
  foreach f in array array['role_save(text,text,text,text[],text,boolean)','user_invite(text,text,text[],text)','user_set_roles(uuid,text[],text,boolean)','user_set_status(uuid,text,text,boolean)','user_set_scope(uuid,boolean,uuid[],uuid[],uuid[],text)'] loop
    execute format('revoke all on function public.%s from public, anon', f); execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;

-- ====================== Department scope ======================
-- Department of a protected resource. null = not department-specific.
create or replace function app.compliance_department(p_compliance uuid) returns uuid language sql stable security definer set search_path = public as $$
  select owner_department_id from public.compliance_master where id = p_compliance
$$;
create or replace function app.instance_department(p_instance uuid) returns uuid language sql stable security definer set search_path = public as $$
  select m.owner_department_id from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id where i.id = p_instance
$$;
revoke all on function app.compliance_department(uuid), app.instance_department(uuid) from public, anon;
grant execute on function app.compliance_department(uuid), app.instance_department(uuid) to authenticated;

-- Existing entity/location rule AND (department is null OR the user holds that department). scope_all bypasses all three.
create or replace function app.in_scope(p_entity uuid, p_location uuid, p_department uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_user u
    where u.auth_user_id = auth.uid() and u.status = 'active'
      and (u.scope_all
        or ((exists (select 1 from public.user_scope s where s.user_id = u.id and ((s.scope_type = 'entity' and s.scope_id = p_entity) or (s.scope_type = 'location' and s.scope_id = p_location))))
            and (p_department is null or exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type = 'department' and s.scope_id = p_department)))))
$$;
create or replace function app.scope_ok(p_entity uuid, p_location uuid, p_department uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare e uuid := p_entity;
begin
  if p_location is not null and e is null then select entity_id into e from public.location where id = p_location; end if;
  if e is null and p_location is null then
    return exists (select 1 from public.app_user u where u.auth_user_id = auth.uid() and u.status = 'active' and u.scope_all);
  end if;
  return app.in_scope(e, p_location, p_department);
end $$;
create or replace function app.user_scope_ok(p_user uuid, p_entity uuid, p_location uuid, p_department uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_user u where u.id = p_user and u.status = 'active' and (u.scope_all
           or (exists (select 1 from public.user_scope s where s.user_id = u.id and ((s.scope_type = 'entity' and s.scope_id = p_entity) or (s.scope_type = 'location' and s.scope_id = p_location)))
               and (p_department is null or exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type = 'department' and s.scope_id = p_department)))))
$$;
revoke all on function app.in_scope(uuid, uuid, uuid), app.scope_ok(uuid, uuid, uuid), app.user_scope_ok(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function app.in_scope(uuid, uuid, uuid), app.scope_ok(uuid, uuid, uuid) to authenticated;

-- Department-aware policies on the resources that have a department dimension (an obligation's department = its master's owner department).
-- Licences, locations, entities and all reference/config masters are unchanged.
drop policy appl_ins on public.compliance_applicability; drop policy appl_sel on public.compliance_applicability; drop policy appl_upd on public.compliance_applicability;
create policy appl_ins on public.compliance_applicability for insert to authenticated with check (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
create policy appl_sel on public.compliance_applicability for select to authenticated using (app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
create policy appl_upd on public.compliance_applicability for update to authenticated using (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)))
  with check (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));

drop policy ci_sel on public.compliance_instance; drop policy ci_upd on public.compliance_instance;
create policy ci_sel on public.compliance_instance for select to authenticated using (app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
create policy ci_upd on public.compliance_instance for update to authenticated using (app.has_permission('compliance.write') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)))
  with check (app.has_permission('compliance.write') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));

drop policy evidence_ins on public.evidence; drop policy evidence_sel on public.evidence; drop policy evidence_upd on public.evidence;
create policy evidence_ins on public.evidence for insert to authenticated with check (app.has_permission('evidence.write') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
create policy evidence_sel on public.evidence for select to authenticated using (app.has_permission('evidence.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
create policy evidence_upd on public.evidence for update to authenticated
  using (app.has_permission('evidence.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)) and (app.has_permission('evidence.write') or app.has_permission('evidence.verify')))
  with check (app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));

drop policy exception_ins on public.exception; drop policy exception_sel on public.exception; drop policy exception_upd on public.exception;
create policy exception_ins on public.exception for insert to authenticated with check (app.has_permission('exception.write') and source = 'manual' and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
create policy exception_sel on public.exception for select to authenticated using (app.has_permission('exception.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
create policy exception_upd on public.exception for update to authenticated using (app.has_permission('exception.write') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)))
  with check (app.has_permission('exception.write') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));

drop policy exception_action_ins on public.exception_action; drop policy exception_action_sel on public.exception_action;
create policy exception_action_ins on public.exception_action for insert to authenticated with check (action_type = 'comment' and app.has_permission('exception.write')
  and exists (select 1 from public.exception x where x.id = exception_action.exception_id and app.scope_ok(x.entity_id, x.location_id, app.instance_department(x.compliance_instance_id))));
create policy exception_action_sel on public.exception_action for select to authenticated using (app.has_permission('exception.read')
  and exists (select 1 from public.exception x where x.id = exception_action.exception_id and app.scope_ok(x.entity_id, x.location_id, app.instance_department(x.compliance_instance_id))));

-- Coverage (what applies where) is scope-controlled the same way.
create or replace function public.compliance_coverage(p_on date default current_date)
returns table (compliance_id uuid, compliance_code text, location_id uuid, location_code text, decision text, effective_status text, conflict boolean, missing_facts text[])
language sql stable as $$
  select c.id, c.code, l.id, l.code, coalesce(r.decision, 'unmapped'), coalesce(r.effective_status, 'unmapped'), coalesce(r.conflict, false), coalesce(r.missing_facts, '{}'::text[])
    from public.compliance_master c
    cross join public.location l
    left join lateral app.applicability_for(c.id, l.id, p_on) r on true
   where c.is_active and l.is_active
     and (auth.uid() is null or app.scope_ok(l.entity_id, l.id, c.owner_department_id))
   order by c.code, l.code
$$;

-- Alert recipients obey the same rule: nobody is told about an obligation they could not open.
create or replace function app.resolve_recipients(p_recipients jsonb, p_owner uuid, p_entity uuid, p_location uuid, p_department uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct u from (
    select p_owner as u where exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner') and p_owner is not null
       and exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active')
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
     where ro.code = 'HEAD_HR' and exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner')
       and (p_owner is null or not exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active'))
       and app.user_scope_ok(ur.user_id, p_entity, p_location, p_department)
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
      join (select substr(r, 6) as code from jsonb_array_elements_text(p_recipients) r where r like 'role:%') rc on rc.code = ro.code
     where app.user_scope_ok(ur.user_id, p_entity, p_location, p_department)
    union all
    select substr(r, 6)::uuid from jsonb_array_elements_text(p_recipients) r where r like 'user:%'
       and exists (select 1 from public.app_user a where a.id = substr(r, 6)::uuid and a.status = 'active')
  ) x where u is not null
$$;
create or replace function app.unroutable_recipients(p_entity uuid, p_location uuid, p_department uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct u from (
    select rc.u from app.active_alert_rules() r
      cross join lateral app.resolve_recipients(
        (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements_text(r.definition -> 'recipients') x where x <> 'owner'), null, p_entity, p_location, p_department) rc(u)
     where r.code = 'UNROUTABLE_ESCALATION'
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
     where app.is_development() and ro.code = 'SUPER_ADMIN' and app.user_scope_ok(ur.user_id, p_entity, p_location, p_department)
  ) x where u is not null
$$;
revoke all on function app.resolve_recipients(jsonb, uuid, uuid, uuid, uuid), app.unroutable_recipients(uuid, uuid, uuid) from public, anon, authenticated;

-- generate_alerts: identical to 0023 except the department of each fired obligation is carried into recipient resolution.
create or replace function app.generate_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare catchup int; email_on boolean; n_c int := 0; n_l int := 0; n_u int := 0; n_x int := 0; n_x2 int := 0;
begin
  catchup := coalesce((select (value #>> '{}')::int from public.system_config where key = 'alert.catchup_days'), 3);
  email_on := coalesce((select value ->> 'state' from public.system_config where key = 'integration.gmail'), 'NOT_CONFIGURED') = 'CONFIGURED';
  drop table if exists _fired;
  create temp table _fired (kind text, id uuid, label text, sub text, entity_id uuid, location_id uuid, owner_user_id uuid, rule_code text, definition jsonb, off int, is_esc boolean, department_id uuid) on commit drop;

  insert into _fired
  with rules as (select * from app.active_alert_rules()),
  inst as (
    select i.id, i.instance_no, i.due_date, i.entity_id, i.location_id, i.owner_user_id, m.code as mcode, m.owner_department_id as dept,
           coalesce(v.alert_rule_code, 'DEFAULT_COMPLIANCE_ALERT') as ac, coalesce(v.escalation_rule_code, 'DEFAULT_COMPLIANCE_ESCALATION') as ec
      from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id
     where i.status in ('open','in_progress'))
  select distinct on (inst.id, r.code) 'compliance', inst.id,
         case when (o.v)::int < 0 then inst.mcode || ' due in ' || (-(o.v)::int) || ' day(s)' when (o.v)::int = 0 then inst.mcode || ' is due today' else inst.mcode || ' overdue by ' || (o.v) || ' day(s)' end,
         inst.instance_no || ' - due ' || inst.due_date, inst.entity_id, inst.location_id, inst.owner_user_id, r.code, r.definition, (o.v)::int, (t.code = inst.ec and t.code <> inst.ac), inst.dept
    from inst cross join lateral (values (inst.ac), (inst.ec)) t(code)
    join rules r on r.code = t.code and coalesce(r.definition ->> 'applies', 'compliance') = 'compliance'
    cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
   where inst.due_date + (o.v)::int <= current_date and inst.due_date + (o.v)::int >= current_date - catchup
   order by inst.id, r.code, (o.v)::int desc;                  -- only the MOST RECENT reached offset

  insert into _fired
  with rules as (select * from app.active_alert_rules())
  select distinct on (l.id, r.code) 'licence', l.id,
         case when (o.v)::int < 0 then t.name || ' expires in ' || (-(o.v)::int) || ' day(s)' when (o.v)::int = 0 then t.name || ' expires today' else t.name || ' expired ' || (o.v) || ' day(s) ago' end,
         l.licence_no || ' - expiry ' || l.expiry_date, l.entity_id, l.location_id, l.owner_user_id, r.code, r.definition, (o.v)::int, false, null::uuid
    from public.licence l join public.licence_type t on t.id = l.licence_type_id
    join rules r on r.code = 'DEFAULT_LICENCE_ALERT'
    cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
   where l.lifecycle_status = 'active' and l.expiry_date is not null and l.renewal_status <> 'renewed'
     and l.expiry_date + (o.v)::int <= current_date and l.expiry_date + (o.v)::int >= current_date - catchup
   order by l.id, r.code, (o.v)::int desc;

  -- routed alerts (unchanged behaviour)
  with targets as (
    select f.*, ch.channel, rc.u as user_id from _fired f
      cross join lateral jsonb_array_elements_text(f.definition -> 'channels') ch(channel)
      cross join lateral app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id, f.department_id) rc(u)),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select user_id, channel, case when kind = 'licence' then 'licence_expiry' when is_esc then 'compliance_escalation' else 'compliance_reminder' end, label, sub,
           case when kind = 'licence' then 'licence' else 'compliance_instance' end, id,
           case when kind = 'licence' then 'lic:' else 'ci:' end || id || ':' || rule_code || ':' || off || ':' || user_id || ':' || channel,
           case when channel = 'email' then 'queued' else 'delivered' end, case when channel = 'email' then null else now() end
      from targets where channel = 'in_app' or email_on
    on conflict (dedupe_key) do nothing returning category)
  select count(*) filter (where category <> 'licence_expiry'), count(*) filter (where category = 'licence_expiry') into n_c, n_l from ins;

  -- D-001: fired alerts whose rule resolves to NOBODY -> durable alert_unroutable notification to the escalation recipients
  with unrouted as (
    select f.* from _fired f where not exists (select 1 from app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id, f.department_id))),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select u.uid, 'in_app', 'alert_unroutable', 'UNROUTED: ' || f.label, f.sub || ' - rule ' || f.rule_code || ' has no valid recipient; delivered to the escalation recipients so it is not lost',
           case when f.kind = 'licence' then 'licence' else 'compliance_instance' end, f.id,
           'unr:' || f.kind || ':' || f.id || ':' || f.rule_code || ':' || f.off || ':' || u.uid, 'delivered', now()
      from unrouted f cross join lateral app.unroutable_recipients(f.entity_id, f.location_id, f.department_id) u(uid)
    on conflict (dedupe_key) do nothing returning 1)
  select count(*) into n_u from ins;
  -- fired alerts that reached nobody at all (the exception from detect_exceptions makes these visible as well)
  select count(*) into n_x from _fired f
   where not exists (select 1 from app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id, f.department_id))
     and not exists (select 1 from app.unroutable_recipients(f.entity_id, f.location_id, f.department_id));

  return jsonb_build_object('compliance_notifications', n_c, 'licence_notifications', n_l, 'unroutable_notifications', n_u, 'unreachable', n_x, 'email_enabled', email_on);
end $function$;
