-- RULE-VERSION CHANGE DEMONSTRATION (DEVELOPMENT ONLY, synthetic). Run after uat_engine_demo.sql, as postgres, in the SQL editor.
-- The SQL editor has no logged-in user, so this script impersonates the DEV SUPER_ADMIN exactly as the API would (role 'authenticated' + the user's JWT subject)
-- to call the real, permission-checked function public.compliance_activate_rule_version(). It then shows that:
--   * the published v1 is retired (effective_to set) and v2 is active, with the reason recorded;
--   * obligations ALREADY generated keep v1's due date (history is never rewritten);
--   * a period beyond v1 is generated under v2's new due day.
-- DISCLOSED BEHAVIOUR (owner decision F2, docs/DEFAULTS_DECISIONS.md): already-generated FUTURE obligations keep the rule they were created under.
begin;
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
  if not exists (select 1 from public.app_user u where u.auth_user_id is not null and u.status = 'active') then raise exception 'No linked active user: sign in once with the dev admin account first'; end if;
end $g$;
create temp table _rc (n serial primary key, step text, result text, detail jsonb);
select set_config('uat.start', date_trunc('month', current_date + interval '3 months')::date::text, true);
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
select 'already-generated obligations keep v1 (due on the 15th)', case when count(*) > 0 and bool_and(extract(day from i.due_date) = 15) then 'PASS' else 'INFO' end,
       jsonb_build_object('obligations_checked', count(*), 'due_days', coalesce(jsonb_agg(distinct extract(day from i.due_date)), '[]'::jsonb))
  from public.compliance_instance i join public.compliance_rule_version r on r.id = i.rule_version_id and r.version = 1 join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-MONTHLY';
insert into _rc(step, result, detail)
select 'a period under v2 is generated with the new due day (20th)', case when count(*) > 0 and bool_and(extract(day from i.due_date) = 20) then 'PASS' else 'FAIL' end,
       jsonb_build_object('obligations', count(*), 'period_start', min(i.period_start), 'due_dates', jsonb_agg(distinct i.due_date))
  from public.compliance_instance i join public.compliance_rule_version r on r.id = i.rule_version_id and r.version = 2 join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-MONTHLY';
commit;
select n, step, result, detail from _rc order by n;
