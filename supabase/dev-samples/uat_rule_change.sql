-- RULE-VERSION CHANGE DEMONSTRATION (DEVELOPMENT ONLY, synthetic). Run after uat_engine_demo.sql, as postgres, in the SQL editor.
-- The SQL editor has no logged-in user, so this script impersonates the DEV SUPER_ADMIN exactly as the API would (role 'authenticated' + the user's JWT subject)
-- to call the real, permission-checked function public.compliance_activate_rule_version(). It then shows that:
--   * the published v1 is retired (effective_to set) and v2 is active, with the reason recorded;
--   * obligations ALREADY generated keep v1's due date (history is never rewritten);
--   * a period beyond v1 is generated under v2's new due day.
-- F-2 (owner decision, migration 0025): obligations a person has acted on, and all history, stay pinned to v1; FUTURE UNTOUCHED system-generated obligations from the effective date
-- are superseded and regenerated under v2 (audited, no duplicates).
begin;
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
  if not exists (select 1 from public.app_user u where u.auth_user_id is not null and u.status = 'active') then raise exception 'No linked active user: sign in once with the dev admin account first'; end if;
end $g$;
create temp table _rc (n serial primary key, step text, result text, detail jsonb);
select set_config('uat.start', date_trunc('month', current_date + interval '1 month')::date::text, true);
select set_config('request.jwt.claim.sub', (select u.auth_user_id::text from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role r on r.id = ur.role_id
                                            where r.code = 'SUPER_ADMIN' and u.auth_user_id is not null and u.status = 'active' order by u.created_at limit 1), true);
set local role authenticated;
  insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, evidence_required, effective_from)
  select m.id, 'internal', 'monthly', '{"type":"day_of_month","day":20,"month_offset":1}', 'high', 'critical', true, current_setting('uat.start')::date
    from public.compliance_master m
   where m.code = 'SAMPLE-MONTHLY' and not exists (select 1 from public.compliance_rule_version r where r.compliance_id = m.id and r.version >= 2);
  select public.compliance_activate_rule_version(r.id, 'UAT: due day moves from the 15th to the 20th') from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id
   where m.code = 'SAMPLE-MONTHLY' and r.status = 'draft' and r.version = 2;
reset role;
insert into _rc(step, result, detail)
select 'v2 created and activated through the API role (needs compliance.manage; reason mandatory)', case when exists (select 1 from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id where m.code = 'SAMPLE-MONTHLY' and r.version = 2 and r.status = 'active') then 'PASS' else 'FAIL' end,
       jsonb_build_object('effective_from', current_setting('uat.start'), 'created_by_is_dev_admin', (select r.created_by is not null from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id where m.code = 'SAMPLE-MONTHLY' and r.version = 2));
select app.generate_compliance_instances(current_setting('uat.start')::date, (current_setting('uat.start')::date + interval '1 month - 1 day')::date);
insert into _rc(step, result, detail)
select 'v1 retired, v2 active, reason recorded', case when count(*) filter (where r.status = 'retired' and r.effective_to = current_setting('uat.start')::date - 1) = 1 and count(*) filter (where r.status = 'active') = 1 then 'PASS' else 'FAIL' end,
       jsonb_agg(jsonb_build_object('version', r.version, 'status', r.status, 'effective_from', r.effective_from, 'effective_to', r.effective_to, 'due_day', r.due_rule ->> 'day', 'reason', r.change_reason) order by r.version)
  from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id where m.code = 'SAMPLE-MONTHLY';
insert into _rc(step, result, detail)
select 'history before the effective date keeps v1 (due on the 15th)', case when count(*) > 0 and bool_and(extract(day from i.due_date) = 15) then 'PASS' else 'INFO' end,
       jsonb_build_object('obligations_checked', count(*), 'due_days', coalesce(jsonb_agg(distinct extract(day from i.due_date)), '[]'::jsonb))
  from public.compliance_instance i join public.compliance_rule_version r on r.id = i.rule_version_id and r.version = 1 join public.compliance_master m on m.id = i.compliance_id
 where m.code = 'SAMPLE-MONTHLY' and i.status <> 'superseded' and i.period_start < current_setting('uat.start')::date;
insert into _rc(step, result, detail)
select 'F-2: future untouched obligations were superseded and re-created under v2 (no duplicates)',
       case when count(*) filter (where s.status = 'superseded') > 0 and count(*) filter (where s.status = 'superseded' and s.superseded_by is null) = 0
             and not exists (select 1 from public.compliance_instance d where d.status <> 'superseded' group by d.compliance_id, d.location_id, d.period_start having count(*) > 1) then 'PASS' else 'INFO' end,
       jsonb_build_object('superseded', count(*) filter (where s.status = 'superseded'), 'note', 'INFO = no untouched future SAMPLE-MONTHLY obligation existed in the generator horizon')
  from public.compliance_instance s join public.compliance_master m on m.id = s.compliance_id where m.code = 'SAMPLE-MONTHLY' and s.period_start >= current_setting('uat.start')::date;
insert into _rc(step, result, detail)
select 'F-2: actioned obligations stay pinned (report lists them for a person)', 'INFO', jsonb_build_object('pinned_listed', (select count(*) from public.compliance_reconciliation_report((select id from public.compliance_master where code = 'SAMPLE-MONTHLY'))));
insert into _rc(step, result, detail)
select 'a period under v2 is generated with the new due day (20th)', case when count(*) > 0 and bool_and(extract(day from i.due_date) = 20) then 'PASS' else 'FAIL' end,
       jsonb_build_object('obligations', count(*), 'period_start', min(i.period_start), 'due_dates', jsonb_agg(distinct i.due_date))
  from public.compliance_instance i join public.compliance_rule_version r on r.id = i.rule_version_id and r.version = 2 join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-MONTHLY';
commit;
select n, step, result, detail from _rc order by n;
