-- Job Monitor read models and safe enable/disable. Rolled back.
\set ON_ERROR_STOP on
begin;
select test.eq('only jobs with a SQL entry point are marked as having a runner', (select string_agg(code, ',' order by code) from public.job_definition where runner is not null), 'alert_generation,compliance_generation,exception_generation');
select test.eq('every declared runner exists in the database', (select count(*) from public.job_definition d where d.runner is not null and to_regprocedure(d.runner) is null), 0::bigint);
delete from public.job_run where job_code in ('compliance_generation');
select app.run_compliance_generation('test');
select test.login('admin@bfcl.test');
select test.eq('status view lists every job', (select count(*) from public.v_job_status), (select count(*) from public.job_definition));
select test.eq('latest run and success are shown', (select last_status || ':' || (last_success_at is not null)::text || ':' || last_environment from public.v_job_status where code='compliance_generation'), 'succeeded:true:test');
select test.eq('a never-run job has no last run', (select last_status is null and failures_24h = 0 from public.v_job_status where code='housekeeping'), true);
select test.eq('run history exposes duration and job name', (select job_name is not null and duration_s is not null from public.v_job_run where job_code='compliance_generation' order by started_at desc limit 1), true);
select test.denied('enable/disable needs a reason', $$select public.job_set_enabled('housekeeping', false, '')$$);
select public.job_set_enabled('housekeeping', false, 'not implemented yet');
select test.eq('job disabled', (select is_enabled from public.job_definition where code='housekeeping'), false);
select test.eq('and audited with the reason', (select count(*) from public.audit_log where table_name='job_definition' and reason='not implemented yet') >= 1, true);
select test.denied('unknown job', $$select public.job_set_enabled('nope', true, 'x')$$);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('a user without job.read sees nothing', (select count(*) from public.v_job_status) + (select count(*) from public.v_job_run), 0::bigint);
select test.denied('and cannot change jobs', $$select public.job_set_enabled('alert_generation', false, 'x')$$);
select test.logout();
rollback;
\echo ALL JOB MONITOR TESTS PASSED
