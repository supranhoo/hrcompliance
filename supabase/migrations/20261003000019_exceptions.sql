-- 0019 Central Exception & Ageing engine (Phase 6.6).
-- ONE exception model for every module. Detection is idempotent: at most one ACTIVE exception per detection_key (partial unique index),
-- so repeated/concurrent runs never duplicate. When the underlying condition clears, the exception is auto-resolved (audited).
-- Severity comes from the risk of the rule version / licence, never hard-coded per obligation.
-- Detection rules implemented now: compliance overdue, evidence missing / rejected / expired, licence expired / expiring.
-- Further rules (GRC SLA, ESIC follow-up, CAPA, …) add detectors in their own migrations against the same table.
-- Rollback: drop view v_exception; drop functions app.run_exception_detection, app.detect_exceptions, app.severity_rank; drop tables exception_action, exception.

insert into public.lov_set (code, name, is_system) values ('EXCEPTION_CATEGORY','Exception category',true) on conflict (code) do nothing;
insert into public.lov_value (set_id, code, label, sort_order, color)
select s.id, v.code, v.label, v.ord, v.color from public.lov_set s join (values
  ('compliance_overdue','Compliance overdue',10,'red'), ('evidence_missing','Mandatory evidence missing',20,'red'), ('evidence_rejected','Evidence rejected',30,'amber'),
  ('evidence_expired','Evidence expired',40,'amber'), ('licence_expired','Licence expired',50,'red'), ('licence_expiring','Licence expiring',60,'amber'),
  ('manual','Manually raised',90,'grey')
) as v(code, label, ord, color) on s.code = 'EXCEPTION_CATEGORY' on conflict (set_id, code) do nothing;

insert into public.status_definition (module, code, label, category, color, sort_order, is_initial, is_terminal) values
  ('exception','open','Open','open','red',10,true,false), ('exception','acknowledged','Acknowledged','in_progress','amber',20,false,false),
  ('exception','resolved','Resolved','closed','green',30,false,true), ('exception','waived','Waived','cancelled','grey',40,false,true)
on conflict (module, code) do nothing;
insert into public.status_transition (module, from_status, to_status, requires_reason) values
  ('exception','open','acknowledged',false), ('exception','open','resolved',false), ('exception','acknowledged','resolved',false),
  ('exception','open','waived',true), ('exception','acknowledged','waived',true), ('exception','resolved','open',true), ('exception','waived','open',true)
on conflict (module, from_status, to_status) do nothing;
insert into public.system_config (key, value, description) values
  ('exception.target_days', '{"critical":1,"high":3,"medium":7,"low":14}', 'Days from detection to the resolution target, by severity'),
  ('exception.overdue_grace_days', '0', 'Days after the due date before an unfinished obligation raises an overdue exception')
on conflict (key) do nothing;

create or replace function app.severity_rank(s text) returns int language sql immutable as
$$ select case s when 'critical' then 4 when 'high' then 3 when 'medium' then 2 when 'low' then 1 else 0 end $$;

create table public.exception (
  id uuid primary key default gen_random_uuid(),
  exception_no text not null unique,                  -- EXC-2026-000001
  category text not null,                             -- LOV EXCEPTION_CATEGORY
  severity text not null,                             -- LOV SEVERITY
  description text not null,
  compliance_instance_id uuid references public.compliance_instance(id),
  licence_id uuid references public.licence(id),
  evidence_id uuid references public.evidence(id),
  entity_id uuid not null references public.entity(id),
  location_id uuid references public.location(id),
  detection_key text not null,
  source text not null default 'auto' check (source in ('auto','manual')),
  detected_at timestamptz not null default now(),
  due_date date,                                      -- resolution target
  owner_user_id uuid references public.app_user(id),
  status text not null default 'open',
  resolution text,
  resolved_at timestamptz, resolved_by uuid,
  auto_resolved boolean not null default false,
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint exception_one_parent_ck check (num_nonnulls(compliance_instance_id, licence_id, evidence_id) = 1),
  constraint exception_closed_ck check ((status in ('resolved','waived')) = (resolved_at is not null)),
  constraint exception_resolution_ck check (status not in ('resolved','waived') or length(trim(coalesce(resolution, ''))) > 0)
);
create unique index exception_active_key_uk on public.exception(detection_key) where status in ('open','acknowledged');
create index exception_status_sev_idx on public.exception(status, severity, detected_at);
create index exception_instance_idx on public.exception(compliance_instance_id) where compliance_instance_id is not null;
create index exception_licence_idx on public.exception(licence_id) where licence_id is not null;
create index exception_scope_idx on public.exception(entity_id, location_id);
create index exception_owner_idx on public.exception(owner_user_id) where owner_user_id is not null;

create table public.exception_action (
  id uuid primary key default gen_random_uuid(),
  exception_id uuid not null references public.exception(id),
  action_type text not null check (action_type in ('detected','comment','assigned','status_change','auto_resolved','escalated')),
  note text,
  created_at timestamptz not null default now(), created_by uuid
);
create index exception_action_idx on public.exception_action(exception_id, created_at);

create trigger exception_no_assign before insert on public.exception for each row execute function app.assign_business_id('EXC','exception_no');
create trigger exception_cat_lov before insert or update on public.exception for each row execute function app.validate_lov('EXCEPTION_CATEGORY','category');
create trigger exception_sev_lov before insert or update on public.exception for each row execute function app.validate_lov('SEVERITY','severity');
create trigger exception_status before insert or update on public.exception for each row execute function app.enforce_status('exception','status');

-- derive scope from the parent; manual rows get a unique key; closing stamps resolver; identity immutable
create or replace function app.exception_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ci public.compliance_instance; li public.licence; ev public.evidence;
begin
  if tg_op = 'INSERT' then
    if num_nonnulls(new.compliance_instance_id, new.licence_id, new.evidence_id) <> 1 then raise exception 'an exception must be attached to exactly one record' using errcode = '23514'; end if;
    if new.compliance_instance_id is not null then select * into ci from public.compliance_instance where id = new.compliance_instance_id; new.entity_id := ci.entity_id; new.location_id := ci.location_id;
    elsif new.licence_id is not null then select * into li from public.licence where id = new.licence_id; new.entity_id := li.entity_id; new.location_id := li.location_id;
    else select * into ev from public.evidence where id = new.evidence_id; new.entity_id := ev.entity_id; new.location_id := ev.location_id; end if;
    if new.entity_id is null then raise exception 'unknown parent record' using errcode = '22023'; end if;
    if new.source = 'manual' then new.detection_key := 'manual:' || new.id::text; new.category := coalesce(new.category, 'manual'); end if;
    if new.due_date is null then
      new.due_date := current_date + coalesce((select (value ->> new.severity)::int from public.system_config where key = 'exception.target_days'), 7);
    end if;
  else
    if (new.exception_no, new.compliance_instance_id, new.licence_id, new.evidence_id, new.entity_id, new.location_id, new.detection_key, new.source, new.detected_at, new.category)
       is distinct from (old.exception_no, old.compliance_instance_id, old.licence_id, old.evidence_id, old.entity_id, old.location_id, old.detection_key, old.source, old.detected_at, old.category) then
      raise exception 'exception identity is immutable' using errcode = '42501';
    end if;
  end if;
  if new.status in ('resolved','waived') then
    if tg_op = 'INSERT' or old.status not in ('resolved','waived') then new.resolved_at := now(); new.resolved_by := auth.uid(); end if;
  else
    new.resolved_at := null; new.resolved_by := null; new.auto_resolved := false;
    if tg_op = 'UPDATE' and old.status in ('resolved','waived') then new.resolution := null; end if;
  end if;
  return new;
end $$;
create trigger exception_guard before insert or update on public.exception for each row execute function app.exception_guard();
create trigger exception_stamp before insert or update on public.exception for each row execute function app.stamp_row();
create trigger audit_exception after insert or update or delete on public.exception for each row execute function app.audit_row();

-- timeline: created + status changes recorded automatically
create or replace function app.exception_timeline() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.exception_action (exception_id, action_type, note) values (new.id, 'detected', case when new.source = 'auto' then 'Detected automatically' else 'Raised manually' end);
  elsif new.status is distinct from old.status then
    insert into public.exception_action (exception_id, action_type, note)
    values (new.id, case when new.auto_resolved then 'auto_resolved' else 'status_change' end,
            old.status || ' -> ' || new.status || coalesce(': ' || nullif(current_setting('app.audit_reason', true), ''), coalesce(': ' || new.resolution, '')));
  elsif new.owner_user_id is distinct from old.owner_user_id then
    insert into public.exception_action (exception_id, action_type, note) values (new.id, 'assigned', 'Owner changed');
  end if;
  return null;
end $$;
create trigger exception_timeline after insert or update on public.exception for each row execute function app.exception_timeline();
create trigger exception_action_stamp before insert on public.exception_action for each row execute function app.stamp_created();

-- ---------- detection ----------
create or replace function app.detect_exceptions() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_found int := 0; v_new int := 0; v_resolved int := 0; n int; grace int;
begin
  grace := coalesce((select (value #>> '{}')::int from public.system_config where key = 'exception.overdue_grace_days'), 0);
  drop table if exists _det;
  create temp table _det (key text primary key, category text, severity text, descr text, instance_id uuid, licence_id uuid, evidence_id uuid, owner uuid) on commit drop;

  -- A. obligations past due (+grace) and not finished; severity = rule risk
  insert into _det
  select 'compliance_overdue:' || i.id, 'compliance_overdue', v.risk_level,
         'Compliance ' || m.code || ' (' || i.instance_no || ') for ' || to_char(i.period_start, 'Mon YYYY') || ' at ' || l.code || ' was due ' || i.due_date || ' and is not complete',
         i.id, null, null, i.owner_user_id
    from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id join public.location l on l.id = i.location_id
   where i.status in ('open','in_progress') and i.due_date + grace < current_date;

  -- B. mandatory evidence absent: after the due date, or when the obligation was completed without it
  insert into _det
  select 'evidence_missing:' || i.id || ':' || rq.document_type_id, 'evidence_missing', v.risk_level,
         'Mandatory document "' || dt.name || '" is missing for ' || i.instance_no, i.id, null, null, i.owner_user_id
    from public.compliance_instance i join public.compliance_rule_version v on v.id = i.rule_version_id and v.evidence_required
    join public.compliance_rule_evidence rq on rq.rule_version_id = v.id and rq.is_mandatory join public.document_type dt on dt.id = rq.document_type_id
   where i.status <> 'not_applicable' and (i.status = 'completed' or i.due_date < current_date)
     and not exists (select 1 from public.evidence e where e.compliance_instance_id = i.id and e.document_type_id = rq.document_type_id and e.is_current);

  -- C. rejected / expired current evidence for obligations that still need it
  insert into _det
  select 'evidence_rejected:' || e.id, 'evidence_rejected', v.risk_level, 'Evidence ' || e.evidence_no || ' was rejected: ' || coalesce(e.verification_remarks, ''), null, null, e.id, i.owner_user_id
    from public.evidence e join public.compliance_instance i on i.id = e.compliance_instance_id join public.compliance_rule_version v on v.id = i.rule_version_id
   where e.is_current and e.verification_status = 'rejected' and i.status <> 'not_applicable';
  insert into _det
  select 'evidence_expired:' || e.id, 'evidence_expired', coalesce(v.risk_level, li.risk_level, 'medium'), 'Evidence ' || e.evidence_no || ' expired on ' || e.expiry_date,
         null, null, e.id, coalesce(i.owner_user_id, li.owner_user_id)
    from public.evidence e left join public.compliance_instance i on i.id = e.compliance_instance_id left join public.compliance_rule_version v on v.id = i.rule_version_id left join public.licence li on li.id = e.licence_id
   where e.is_current and e.expiry_date is not null and e.expiry_date < current_date and coalesce(i.status, 'open') <> 'not_applicable' and coalesce(li.lifecycle_status, 'active') = 'active';

  -- D. licences: expired (critical when the licence itself is high/critical risk) and inside the renewal window
  insert into _det
  select 'licence_expired:' || li.id, 'licence_expired', case when app.severity_rank(coalesce(li.risk_level, 'medium')) >= 3 then 'critical' else 'high' end,
         'Licence ' || li.licence_no || ' (' || t.name || ') expired on ' || li.expiry_date, null, li.id, null, li.owner_user_id
    from public.licence li join public.licence_type t on t.id = li.licence_type_id where li.lifecycle_status = 'active' and li.expiry_date is not null and li.expiry_date < current_date;
  insert into _det
  select 'licence_expiring:' || li.id, 'licence_expiring', coalesce(li.risk_level, 'medium'),
         'Licence ' || li.licence_no || ' (' || t.name || ') expires on ' || li.expiry_date || ' (' || (li.expiry_date - current_date) || ' days)', null, li.id, null, li.owner_user_id
    from public.licence li join public.licence_type t on t.id = li.licence_type_id
   where li.lifecycle_status = 'active' and li.expiry_date is not null and li.expiry_date >= current_date and (li.expiry_date - current_date) <= li.renewal_lead_days
     and li.renewal_status not in ('renewed');
  select count(*) into v_found from _det;

  -- raise (idempotent by detection_key)
  with ins as (
    insert into public.exception (category, severity, description, compliance_instance_id, licence_id, evidence_id, entity_id, detection_key, source, owner_user_id)
    select d.category, d.severity, d.descr, d.instance_id, d.licence_id, d.evidence_id, null::uuid, d.key, 'auto', d.owner from _det d
    on conflict (detection_key) where status in ('open','acknowledged') do nothing returning 1)
  select count(*) into v_new from ins;

  -- auto-resolve cleared conditions (never touches manual exceptions)
  perform set_config('app.audit_reason', 'Condition cleared automatically', true);
  update public.exception x set status = 'resolved', resolution = 'Condition cleared automatically', auto_resolved = true
   where x.source = 'auto' and x.status in ('open','acknowledged') and not exists (select 1 from _det d where d.key = x.detection_key);
  get diagnostics v_resolved = row_count;
  perform set_config('app.audit_reason', '', true);
  return jsonb_build_object('conditions_found', v_found, 'raised', v_new, 'auto_resolved', v_resolved);
end $$;

create or replace function app.run_exception_detection(p_env text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j record; res jsonb;
begin
  select * into j from app.job_start('exception_generation', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24'), p_env, 'schedule');
  if not j.should_run then return jsonb_build_object('ran', false, 'reason', j.reason); end if;
  begin
    res := app.detect_exceptions();
    perform app.job_finish(j.run_id, true, (res ->> 'raised')::int, null);
    return res || jsonb_build_object('ran', true);
  exception when others then
    perform app.job_finish(j.run_id, false, null, jsonb_build_object('message', sqlerrm, 'state', sqlstate));
    return jsonb_build_object('ran', true, 'error', sqlerrm);
  end;
end $$;
revoke all on function app.detect_exceptions(), app.run_exception_detection(text) from public;
grant execute on function app.detect_exceptions(), app.run_exception_detection(text) to service_role;

-- ---------- ageing view (derived) ----------
create view public.v_exception with (security_invoker = true) as
select x.id, x.exception_no, x.category, x.severity, x.description, x.status, x.source, x.detected_at, x.due_date, x.owner_user_id,
       x.compliance_instance_id, x.licence_id, x.evidence_id, x.entity_id, x.location_id, x.resolution, x.resolved_at, x.auto_resolved,
       case when x.resolved_at is null then current_date - x.detected_at::date else x.resolved_at::date - x.detected_at::date end as age_days,
       case when x.resolved_at is not null then 'closed'
            when current_date - x.detected_at::date <= 7 then '0-7'
            when current_date - x.detected_at::date <= 30 then '8-30'
            when current_date - x.detected_at::date <= 90 then '31-90' else '90+' end as age_bucket,
       (x.resolved_at is null and x.due_date is not null and x.due_date < current_date) as target_breached
  from public.exception x;

-- ---------- permissions, grants, RLS ----------
insert into public.permission (code, module, description) values
  ('exception.read','exception','View exceptions'), ('exception.write','exception','Acknowledge, assign, resolve, waive and raise exceptions')
on conflict (code) do nothing;
alter table public.exception enable row level security;        alter table public.exception force row level security;
alter table public.exception_action enable row level security; alter table public.exception_action force row level security;
grant select, insert, update on public.exception to authenticated;
grant select, insert on public.exception_action to authenticated;
grant select on public.v_exception to authenticated;
create policy exception_sel on public.exception for select to authenticated using (app.has_permission('exception.read') and app.scope_ok(entity_id, location_id));
create policy exception_ins on public.exception for insert to authenticated with check (app.has_permission('exception.write') and source = 'manual' and app.scope_ok(entity_id, location_id));
create policy exception_upd on public.exception for update to authenticated
  using (app.has_permission('exception.write') and app.scope_ok(entity_id, location_id)) with check (app.has_permission('exception.write') and app.scope_ok(entity_id, location_id));
create policy exception_action_sel on public.exception_action for select to authenticated
  using (app.has_permission('exception.read') and exists (select 1 from public.exception x where x.id = exception_id and app.scope_ok(x.entity_id, x.location_id)));
create policy exception_action_ins on public.exception_action for insert to authenticated
  with check (action_type = 'comment' and app.has_permission('exception.write') and exists (select 1 from public.exception x where x.id = exception_id and app.scope_ok(x.entity_id, x.location_id)));
insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on p.code like 'exception.%' where
     r.code in ('SUPER_ADMIN','HEAD_HR','PLANT_HR') or (r.code in ('HOD','VIEWER') and p.code = 'exception.read')
on conflict do nothing;
