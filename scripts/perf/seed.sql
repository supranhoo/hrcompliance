-- Synthetic performance data. SYNTHETIC ONLY: names, codes and counts are generated; nothing here is BFCL data.
-- Scale (defaults): 4 entities, 24 locations, 8 departments, 60 compliance masters, 10,080 obligations, 25,000 exceptions, 2,000 licences, 22 users.
-- Run on a THROWAWAY database after migrations (scripts/perf/run.sh does everything). Bulk-loads with triggers off (session_replication_role = replica) for speed;
-- the rows respect all column constraints, and unique/partial-unique indexes still apply.
\set ON_ERROR_STOP on
set session_replication_role = replica;
begin;
insert into public.entity (code, name) select 'PERF-E' || g, 'Synthetic Entity ' || g from generate_series(1, 4) g;
insert into public.location (entity_id, code, name, state) select e.id, 'PL' || lpad(((row_number() over (order by e.code, g))::int)::text, 2, '0'), 'Synthetic Site ' || e.code || '-' || g, 'XX' from public.entity e cross join generate_series(1, 6) g where e.code like 'PERF-E%';
insert into public.department (code, name) select 'PD' || g, 'Synthetic Department ' || g from generate_series(1, 8) g;
insert into public.authority (code, name) select 'PAUTH' || g, 'Synthetic Authority ' || g from generate_series(1, 5) g;
insert into public.licence_type (code, name, authority_id, default_risk) select 'PLT' || g, 'Synthetic Licence Type ' || g, (select id from public.authority where code = 'PAUTH' || ((g % 5) + 1)), (array['low','medium','high','critical'])[(g % 4) + 1] from generate_series(1, 10) g;
-- 60 masters: ~3/4 owned by a department, 1/4 entity-wide (no department)
insert into public.compliance_master (code, name, owner_department_id, domain)
  select 'PM' || lpad(g::text, 3, '0'), 'Synthetic Obligation ' || g, case when g % 4 = 0 then null else (select id from public.department where code = 'PD' || ((g % 8) + 1)) end, (array['Labour','Safety','Environment','Payroll'])[(g % 4) + 1] from generate_series(1, 60) g;
insert into public.compliance_rule_version (compliance_id, version, status, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 1, 'active', 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', (array['low','medium','high','critical'])[(abs(hashtext(code)) % 4) + 1], date '2020-01-01' from public.compliance_master where code like 'PM%';

-- users: perf_admin (all locations), perf_scoped (entity PERF-E1 + two departments), 20 plain owners
insert into auth.users (id, email) select gen_random_uuid(), 'perf_admin@perf.test' union all select gen_random_uuid(), 'perf_scoped@perf.test';
insert into public.app_user (email, status, scope_all, auth_user_id) select a.email, 'active', a.email = 'perf_admin@perf.test', a.id from auth.users a where a.email like 'perf\_%@perf.test';
insert into public.user_role (user_id, role_id) select u.id, r.id from public.app_user u join public.role r on r.code = case when u.email = 'perf_admin@perf.test' then 'SUPER_ADMIN' else 'HEAD_HR' end where u.email like 'perf\_%@perf.test';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email = 'perf_scoped@perf.test' and e.code = 'PERF-E1';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'department', d.id from public.app_user u, public.department d where u.email = 'perf_scoped@perf.test' and d.code in ('PD1','PD2');
insert into public.app_user (email, status) select 'owner' || g || '@perf.test', 'active' from generate_series(1, 20) g;

-- 60 masters x 24 locations x 7 periods = 10,080 obligations spread over 18 months back to 3 months ahead
create temp table _owners as select id, row_number() over (order by email) as rn from public.app_user where email like 'owner%@perf.test';
insert into public.compliance_instance (instance_no, compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, status, completed_on, source, owner_user_id)
select 'PCI-' || lpad((row_number() over (order by m.code, l.code, k))::text, 7, '0'), m.id, v.id, l.entity_id, l.id, x.ps, x.ps + 27, x.ps + 44, y.st,
       case when y.st = 'completed' then x.ps + 44 + (case when x.r < 0.15 then 5 else -2 end) end, 'generated', (select id from _owners where rn = 1 + (abs(hashtext(m.code || l.code)) % 20))
  from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l, generate_series(-15, 3, 3) k,
       lateral (select (date_trunc('month', current_date) + make_interval(months => k))::date as ps, random() as r) x,
       lateral (select case when x.ps + 44 < current_date - 20 then (case when x.r < 0.78 then 'completed' when x.r < 0.90 then 'open' else 'not_applicable' end)
                            when x.ps + 44 < current_date then (case when x.r < 0.5 then 'completed' else 'open' end)
                            else (case when x.r < 0.2 then 'in_progress' else 'open' end) end as st) y
 where m.code like 'PM%' and l.code like 'PL%';

-- 2,000 licences, ~12% already expired, expiries up to 36 months ahead
insert into public.licence (licence_no, licence_type_id, entity_id, location_id, authority_id, licence_number, issue_date, expiry_date, lifecycle_status)
select 'PLIC-' || lpad(g::text, 6, '0'), t.id, l.entity_id, l.id, t.authority_id, 'PN-' || g, current_date - 700, current_date + ((g * 37) % 1200) - 150, 'active'
  from generate_series(1, 2000) g join public.licence_type t on t.code = 'PLT' || ((g % 10) + 1) join public.location l on l.code = 'PL' || lpad(((g % 24) + 1)::text, 2, '0');

-- 25,000 exceptions: 80% on obligations (a quarter of them manual), 20% on licences; ~35% open/acknowledged, rest resolved/waived (history)
create temp table _ci as select id, entity_id, location_id, row_number() over () as rn from public.compliance_instance;
create temp table _li as select id, entity_id, location_id, row_number() over () as rn from public.licence;
insert into public.exception (exception_no, category, severity, description, compliance_instance_id, licence_id, entity_id, location_id, detection_key, source, detected_at, due_date, status, resolved_at, resolution)
select 'PEXC-' || lpad(g::text, 7, '0'), c.cat, (array['low','medium','high','critical'])[(g % 4) + 1], 'Synthetic exception ' || g,
       case when c.kind = 'ci' then ci.id end, case when c.kind = 'li' then li.id end, coalesce(ci.entity_id, li.entity_id, (select id from public.entity where code = 'PERF-E1')), coalesce(ci.location_id, li.location_id),
       'perf:' || g, case when c.cat = 'manual' then 'manual' else 'auto' end, now() - make_interval(days => (g * 7) % 400), (current_date - ((g * 7) % 400))::date + 7, c.st,
       case when c.st in ('resolved','waived') then now() - make_interval(days => (g * 3) % 300) end, case when c.st in ('resolved','waived') then 'synthetic' end
  from generate_series(1, 25000) g
  cross join lateral (select case when g % 100 < 80 then 'ci' else 'li' end as kind,
                             case when g % 100 < 80 then (array['compliance_overdue','evidence_missing','evidence_rejected','manual'])[(g % 4) + 1] else (array['licence_expired','licence_expiring'])[(g % 2) + 1] end as cat,
                             case when g % 20 < 7 then (case when g % 2 = 0 then 'open' else 'acknowledged' end) when g % 20 < 19 then 'resolved' else 'waived' end as st) c
  left join _ci ci on c.kind = 'ci' and ci.rn = 1 + (g % (select count(*) from _ci))
  left join _li li on c.kind = 'li' and li.rn = 1 + (g % (select count(*) from _li));
commit;
reset session_replication_role;
analyze;
select 'entities' as what, count(*) from public.entity where code like 'PERF-E%' union all select 'locations', count(*) from public.location where code like 'PL%' union all select 'masters', count(*) from public.compliance_master where code like 'PM%'
 union all select 'obligations', count(*) from public.compliance_instance union all select 'exceptions', count(*) from public.exception union all select 'licences', count(*) from public.licence;
