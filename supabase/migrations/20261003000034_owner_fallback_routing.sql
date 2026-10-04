-- 0034 Configuration-driven owner fallback routing (FU-001).
-- Before: when an alert's recipients include 'owner' but the obligation has no active owner, app.resolve_recipients sent it to users whose role code is the literal 'HEAD_HR'
-- (hardcoded in 0020 and again in the 0033 department-aware version). Now the fallback recipients are the active alert rule OWNER_FALLBACK (roles and/or users, same shape and
-- validation as every other alert rule; 'owner' is not allowed in it), resolved with the same scope rules (entity/location/department). Seeded v1 = role:HEAD_HR so behaviour is unchanged
-- until BFCL edits it on the Alert Rules screen (versioned, reason, audited). alert_routing_validation() warns when it is not configured. If it is empty the alert falls through to D-001.
-- The 4-argument resolver and 2-argument unroutable_recipients become thin wrappers: there is exactly one resolver.
-- Rollback: restore app.resolve_recipients/app.unroutable_recipients/public.alert_routing_validation bodies from 0033/0023; delete from public.config_definition where kind = 'alert_rule' and code = 'OWNER_FALLBACK'.
insert into public.config_definition (kind, code, name, version, status, definition, change_reason, effective_from) values
  ('alert_rule','OWNER_FALLBACK','Owner fallback recipients',1,'active','{"applies":"compliance","offsets":[0],"channels":["in_app"],"recipients":["role:HEAD_HR"]}','Seeded to preserve the previous fallback (Head HR in scope) - BFCL to review', date '2026-01-01')
on conflict (kind, code, version) do nothing;

create or replace function app.resolve_recipients(p_recipients jsonb, p_owner uuid, p_entity uuid, p_location uuid, p_department uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct u from (
    select p_owner as u where exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner') and p_owner is not null
       and exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active')
    union all
    -- owner requested but absent/inactive: the configured OWNER_FALLBACK recipients (never 'owner' itself, so this cannot recurse into the fallback again)
    select f from app.resolve_recipients(
        (select coalesce(jsonb_agg(x), '[]'::jsonb) from app.active_alert_rules() r cross join lateral jsonb_array_elements_text(r.definition -> 'recipients') x where r.code = 'OWNER_FALLBACK' and x <> 'owner'),
        null, p_entity, p_location, p_department) f
     where exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner')
       and (p_owner is null or not exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active'))
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
      join (select substr(r, 6) as code from jsonb_array_elements_text(p_recipients) r where r like 'role:%') rc on rc.code = ro.code
     where app.user_scope_ok(ur.user_id, p_entity, p_location, p_department)
    union all
    select substr(r, 6)::uuid from jsonb_array_elements_text(p_recipients) r where r like 'user:%'
       and exists (select 1 from public.app_user a where a.id = substr(r, 6)::uuid and a.status = 'active')
  ) x where u is not null
$$;
create or replace function app.resolve_recipients(p_recipients jsonb, p_owner uuid, p_entity uuid, p_location uuid) returns setof uuid
language sql stable security definer set search_path = public as $$ select app.resolve_recipients(p_recipients, p_owner, p_entity, p_location, null::uuid) $$;
create or replace function app.unroutable_recipients(p_entity uuid, p_location uuid) returns setof uuid
language sql stable security definer set search_path = public as $$ select app.unroutable_recipients(p_entity, p_location, null::uuid) $$;

-- Alert-rule guard: the fallback list names who to use INSTEAD of the owner, so 'owner' itself is meaningless there.
create or replace function app.owner_fallback_guard() returns trigger language plpgsql as $$
begin
  if new.kind = 'alert_rule' and new.code = 'OWNER_FALLBACK' and exists (select 1 from jsonb_array_elements_text(new.definition -> 'recipients') r where r = 'owner') then
    raise exception 'OWNER_FALLBACK recipients must be roles or users, not owner' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger config_definition_owner_fallback_guard before insert or update on public.config_definition for each row execute function app.owner_fallback_guard();

-- alert_routing_validation: identical to 0023 plus a warning when OWNER_FALLBACK is not configured.
create or replace function public.alert_routing_validation()
 RETURNS TABLE(rule_code text, severity text, problem text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; t text; n int; prod boolean := not app.is_development(); crit boolean; sev text;
begin
  if not (app.has_permission('health.read') or app.has_permission('config.read')) then raise exception 'permission denied' using errcode = '42501'; end if;
  for r in select * from app.active_alert_rules() loop
    crit := coalesce((r.definition ->> 'critical')::boolean, false) or r.code = 'UNROUTABLE_ESCALATION';
    sev := case when crit then 'error' else 'warning' end;
    n := 0;
    for t in select jsonb_array_elements_text(r.definition -> 'recipients') loop
      if t = 'owner' then n := n + 1;
      elsif t like 'role:%' then
        if not exists (select 1 from public.role where code = substr(t, 6)) then rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': no such role'; return next;
        elsif not exists (select 1 from public.user_role ur join public.role ro on ro.id = ur.role_id join public.app_user u on u.id = ur.user_id where ro.code = substr(t, 6) and u.status = 'active') then
          rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': no active user holds this role'; return next;
        else n := n + 1; end if;
      elsif t like 'user:%' then
        if not exists (select 1 from public.app_user u where u.id = substr(t, 6)::uuid and u.status = 'active') then
          rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': user is not active'; return next;
        else n := n + 1; end if;
      end if;
    end loop;
    if n = 0 then rule_code := r.code; severity := sev; problem := 'no valid routing: none of the recipients can currently receive an alert'; return next; end if;
  end loop;
  if not exists (select 1 from app.active_alert_rules() a where a.code = 'UNROUTABLE_ESCALATION') then
    rule_code := 'UNROUTABLE_ESCALATION'; severity := case when prod then 'error' else 'warning' end;
    problem := case when prod then 'BLOCKING for production: no active UNROUTABLE_ESCALATION rule - alerts with no recipient would only appear as exceptions. BFCL must configure escalation recipients'
                    else 'not configured (development: Super Admin fallback is active; production requires BFCL escalation recipients)' end;
    return next;
  end if;
  if not exists (select 1 from app.active_alert_rules() a where a.code = 'OWNER_FALLBACK') then
    rule_code := 'OWNER_FALLBACK'; severity := 'warning';
    problem := 'not configured: when an obligation has no active owner, its alerts have no fallback recipients and fall through to the unroutable escalation';
    return next;
  end if;
  return;
end $function$;
