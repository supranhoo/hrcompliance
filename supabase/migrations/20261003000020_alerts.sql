-- 0020 Alerts & notifications (Phase 6.6b).
-- Alert timing/recipients/channels are CONFIGURATION (config_definition kind='alert_rule', versioned, immutable once published).
-- Offsets are days relative to the due/expiry date: negative = before (T-30), 0 = due day, positive = after (D+3).
-- Per obligation and rule, the MOST RECENT offset reached within a short catch-up window is notified (a missed night never loses the alert,
-- and an item due today never receives a stale "due in 3 days" reminder);
-- the dedupe key makes repeated runs a no-op. Only OPEN obligations / ACTIVE licences alert. Recipients respect each user's scope.
-- Email is created only when the mail integration is CONFIGURED (system_config integration.gmail); otherwise it is counted as skipped,
-- so a backlog can never be blasted when Gmail is connected later. Alerts never issue formal communications (req. 54).
-- Defaults below are STARTING POINTS for BFCL review, not legal requirements; change them with config_new_version().
-- Rollback: drop functions app.generate_alerts, app.run_alert_generation, app.resolve_recipients, app.user_scope_ok, app.alert_rule_guard; drop table notification;
--           delete from config_definition where code like 'DEFAULT\_%' and kind='alert_rule'.

insert into public.system_config (key, value, description) values
  ('alert.catchup_days', '3', 'An alert offset reached within this many days is still generated (covers missed runs)')
on conflict (key) do nothing;

-- ---------- alert rule shape (validated in the database; no code, only data) ----------
-- {"applies":"compliance|licence","offsets":[-30,-7,0,1],"channels":["in_app","email"],"recipients":["owner","role:HEAD_HR","user:<uuid>"],"when":{rule AST}}
create or replace function app.alert_rule_guard() returns trigger language plpgsql as $$
declare d jsonb := new.definition; o jsonb; ok boolean := true;
begin
  if new.kind <> 'alert_rule' then return new; end if;
  if jsonb_typeof(d -> 'offsets') is distinct from 'array' or jsonb_array_length(d -> 'offsets') = 0 then raise exception 'alert_rule needs a non-empty offsets array' using errcode = '23514'; end if;
  for o in select * from jsonb_array_elements(d -> 'offsets') loop
    if jsonb_typeof(o) <> 'number' or (o #>> '{}') !~ '^-?\d{1,3}$' or abs((o #>> '{}')::int) > 365 then raise exception 'alert offsets must be whole days between -365 and 365' using errcode = '23514'; end if;
  end loop;
  if jsonb_typeof(d -> 'channels') is distinct from 'array' or jsonb_array_length(d -> 'channels') = 0
     or exists (select 1 from jsonb_array_elements_text(d -> 'channels') c where c not in ('in_app','email')) then
    raise exception 'alert channels must be a non-empty subset of in_app, email' using errcode = '23514';
  end if;
  if jsonb_typeof(d -> 'recipients') is distinct from 'array' or jsonb_array_length(d -> 'recipients') = 0
     or exists (select 1 from jsonb_array_elements_text(d -> 'recipients') r where r !~ '^(owner|role:[A-Z][A-Z0-9_]{1,40}|user:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') then
    raise exception 'alert recipients must be owner, role:<ROLE_CODE> or user:<uuid>' using errcode = '23514';
  end if;
  if coalesce(d ->> 'applies', 'compliance') not in ('compliance','licence') then raise exception 'alert applies must be compliance or licence' using errcode = '23514'; end if;
  return new;
end $$;
create trigger config_alert_rule_guard before insert or update on public.config_definition for each row execute function app.alert_rule_guard();

insert into public.config_definition (kind, code, name, version, status, definition, change_reason, effective_from) values
  ('alert_rule','DEFAULT_COMPLIANCE_ALERT','Default compliance reminders',1,'active','{"applies":"compliance","offsets":[-7,-3,0,1],"channels":["in_app","email"],"recipients":["owner"]}','Initial default - review with BFCL', date '2026-01-01'),
  ('alert_rule','DEFAULT_COMPLIANCE_ESCALATION','Default compliance escalation',1,'active','{"applies":"compliance","offsets":[3,7],"channels":["in_app","email"],"recipients":["role:HEAD_HR"]}','Initial default - review with BFCL', date '2026-01-01'),
  ('alert_rule','DEFAULT_LICENCE_ALERT','Default licence expiry alerts',1,'active','{"applies":"licence","offsets":[-90,-60,-30,-15,-7,0,1],"channels":["in_app","email"],"recipients":["owner","role:HEAD_HR"]}','Initial default - review with BFCL', date '2026-01-01')
on conflict (kind, code, version) do nothing;

-- ---------- scope / recipients ----------
create or replace function app.user_scope_ok(p_user uuid, p_entity uuid, p_location uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_user u where u.id = p_user and u.status = 'active' and (u.scope_all
           or exists (select 1 from public.user_scope s where s.user_id = u.id and ((s.scope_type = 'entity' and s.scope_id = p_entity) or (s.scope_type = 'location' and s.scope_id = p_location)))))
$$;

-- owner -> the owner if active, otherwise the Head HR role (an obligation without an owner must never go silent)
create or replace function app.resolve_recipients(p_recipients jsonb, p_owner uuid, p_entity uuid, p_location uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct u from (
    select p_owner as u where exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner') and p_owner is not null
       and exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active')
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
     where ro.code = 'HEAD_HR' and exists (select 1 from jsonb_array_elements_text(p_recipients) r where r = 'owner')
       and (p_owner is null or not exists (select 1 from public.app_user a where a.id = p_owner and a.status = 'active'))
       and app.user_scope_ok(ur.user_id, p_entity, p_location)
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
      join (select substr(r, 6) as code from jsonb_array_elements_text(p_recipients) r where r like 'role:%') rc on rc.code = ro.code
     where app.user_scope_ok(ur.user_id, p_entity, p_location)
    union all
    select substr(r, 6)::uuid from jsonb_array_elements_text(p_recipients) r where r like 'user:%'
       and exists (select 1 from public.app_user a where a.id = substr(r, 6)::uuid and a.status = 'active')
  ) x where u is not null
$$;

-- ---------- notifications ----------
create table public.notification (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_user(id),
  channel text not null check (channel in ('in_app','email')),
  category text not null check (category in ('compliance_reminder','compliance_escalation','licence_expiry')),
  title text not null,
  body text,
  link_kind text not null check (link_kind in ('compliance_instance','licence','exception')),
  link_id uuid not null,
  dedupe_key text not null unique,
  status text not null default 'delivered' check (status in ('queued','delivered','failed')),   -- in_app = delivered at creation; email = queued for the mail adapter
  created_at timestamptz not null default now(),
  delivered_at timestamptz default now(),
  read_at timestamptz,
  error text
);
create index notification_user_idx on public.notification(user_id, created_at desc);
create index notification_unread_idx on public.notification(user_id) where read_at is null and channel = 'in_app';
create index notification_queue_idx on public.notification(created_at) where status = 'queued';

-- users may only mark their own notification read/unread
create or replace function app.notification_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and (new.id, new.user_id, new.channel, new.category, new.title, new.body, new.link_kind, new.link_id, new.dedupe_key, new.status, new.created_at, new.delivered_at, new.error)
     is distinct from (old.id, old.user_id, old.channel, old.category, old.title, old.body, old.link_kind, old.link_id, old.dedupe_key, old.status, old.created_at, old.delivered_at, old.error) then
    raise exception 'only read state can be changed on a notification' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger notification_guard before update on public.notification for each row execute function app.notification_guard();

-- ---------- generation ----------
create or replace function app.generate_alerts() returns jsonb
language plpgsql security definer set search_path = public as $$
declare catchup int; email_on boolean; n_c int := 0; n_l int := 0; n_skip int := 0;
begin
  catchup := coalesce((select (value #>> '{}')::int from public.system_config where key = 'alert.catchup_days'), 3);
  email_on := coalesce((select value ->> 'state' from public.system_config where key = 'integration.gmail'), 'NOT_CONFIGURED') = 'CONFIGURED';

  with rules as (
    select distinct on (code) code, definition from public.config_definition
     where kind = 'alert_rule' and status = 'active' and (effective_from is null or effective_from <= current_date) and (effective_to is null or effective_to >= current_date)
     order by code, version desc),
  inst as (
    select i.id, i.instance_no, i.due_date, i.entity_id, i.location_id, i.owner_user_id, m.code as mcode,
           coalesce(v.alert_rule_code, 'DEFAULT_COMPLIANCE_ALERT') as ac, coalesce(v.escalation_rule_code, 'DEFAULT_COMPLIANCE_ESCALATION') as ec
      from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id
     where i.status in ('open','in_progress')),
  fired as (
    select distinct on (inst.id, r.code) inst.*, r.code as rule_code, r.definition, (o.v)::int as off, (t.code = inst.ec and t.code <> inst.ac) as is_esc
      from inst cross join lateral (values (inst.ac), (inst.ec)) t(code)
      join rules r on r.code = t.code and coalesce(r.definition ->> 'applies', 'compliance') = 'compliance'
      cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
     where inst.due_date + (o.v)::int <= current_date and inst.due_date + (o.v)::int >= current_date - catchup
     order by inst.id, r.code, (o.v)::int desc),      -- only the MOST RECENT reached offset: no stale "due in 3 days" on the due date
  targets as (
    select f.*, ch.channel, rc.u as user_id
      from fired f
      cross join lateral jsonb_array_elements_text(f.definition -> 'channels') ch(channel)
      cross join lateral app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id) rc(u)),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select user_id, channel, case when is_esc then 'compliance_escalation' else 'compliance_reminder' end,
           case when off < 0 then mcode || ' due in ' || (-off) || ' day(s)' when off = 0 then mcode || ' is due today' else mcode || ' overdue by ' || off || ' day(s)' end,
           instance_no || ' - due ' || due_date, 'compliance_instance', id,
           'ci:' || id || ':' || rule_code || ':' || off || ':' || user_id || ':' || channel,
           case when channel = 'email' then 'queued' else 'delivered' end, case when channel = 'email' then null else now() end
      from targets where channel = 'in_app' or email_on
    on conflict (dedupe_key) do nothing returning 1)
  select count(*) into n_c from ins;

  with rules as (
    select distinct on (code) code, definition from public.config_definition
     where kind = 'alert_rule' and status = 'active' and (effective_from is null or effective_from <= current_date) and (effective_to is null or effective_to >= current_date)
     order by code, version desc),
  fired as (
    select distinct on (l.id, r.code) l.id, l.licence_no, l.expiry_date, l.entity_id, l.location_id, l.owner_user_id, t.name as tname, r.code as rule_code, r.definition, (o.v)::int as off
      from public.licence l join public.licence_type t on t.id = l.licence_type_id
      join rules r on r.code = 'DEFAULT_LICENCE_ALERT'
      cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
     where l.lifecycle_status = 'active' and l.expiry_date is not null and l.renewal_status <> 'renewed'
       and l.expiry_date + (o.v)::int <= current_date and l.expiry_date + (o.v)::int >= current_date - catchup
     order by l.id, r.code, (o.v)::int desc),
  targets as (
    select f.*, ch.channel, rc.u as user_id from fired f
      cross join lateral jsonb_array_elements_text(f.definition -> 'channels') ch(channel)
      cross join lateral app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id) rc(u)),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select user_id, channel, 'licence_expiry',
           case when off < 0 then tname || ' expires in ' || (-off) || ' day(s)' when off = 0 then tname || ' expires today' else tname || ' expired ' || off || ' day(s) ago' end,
           licence_no || ' - expiry ' || expiry_date, 'licence', id,
           'lic:' || id || ':' || rule_code || ':' || off || ':' || user_id || ':' || channel,
           case when channel = 'email' then 'queued' else 'delivered' end, case when channel = 'email' then null else now() end
      from targets where channel = 'in_app' or email_on
    on conflict (dedupe_key) do nothing returning 1)
  select count(*) into n_l from ins;

  return jsonb_build_object('compliance_notifications', n_c, 'licence_notifications', n_l, 'email_enabled', email_on);
end $$;

create or replace function app.run_alert_generation(p_env text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j record; res jsonb;
begin
  select * into j from app.job_start('alert_generation', to_char(current_date, 'YYYY-MM-DD'), p_env, 'schedule');
  if not j.should_run then return jsonb_build_object('ran', false, 'reason', j.reason); end if;
  begin
    res := app.generate_alerts();
    perform app.job_finish(j.run_id, true, (res ->> 'compliance_notifications')::int + (res ->> 'licence_notifications')::int, null);
    return res || jsonb_build_object('ran', true);
  exception when others then
    perform app.job_finish(j.run_id, false, null, jsonb_build_object('message', sqlerrm, 'state', sqlstate));
    return jsonb_build_object('ran', true, 'error', sqlerrm);
  end;
end $$;
revoke all on function app.generate_alerts(), app.run_alert_generation(text) from public;
grant execute on function app.generate_alerts(), app.run_alert_generation(text) to service_role;

-- ---------- RLS: a user sees and marks only their own notifications ----------
alter table public.notification enable row level security; alter table public.notification force row level security;
grant select, update on public.notification to authenticated;
create policy notification_sel on public.notification for select to authenticated using (user_id = app.current_user_id());
create policy notification_upd on public.notification for update to authenticated using (user_id = app.current_user_id()) with check (user_id = app.current_user_id());
