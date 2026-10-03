-- EXCEPTION-AGEING FIXTURE (DEVELOPMENT ONLY, synthetic). Run after uat_engine_demo.sql, as postgres, in the SQL editor.
-- Exceptions are always created "today", so the older ageing buckets (8-30, 31-90, 90+) cannot occur naturally for weeks. To see them in the UI this script
-- BACK-DATES the detection time of up to three SAMPLE exceptions (about 10, 40 and 100 days). detected_at is immutable for every API user; this is a table-owner
-- fixture that lifts the guard for this transaction only. It does not touch any non-SAMPLE record. Removed together with the samples.
begin;
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
end $g$;
alter table public.exception disable trigger exception_guard;
with pick as (
  select x.id, row_number() over (order by x.detected_at) rn from public.exception x join public.entity e on e.id = x.entity_id
   where e.code = 'SAMPLE-ENT' and x.status in ('open','acknowledged') and x.detected_at > now() - interval '5 days' order by x.detected_at limit 3)
update public.exception x set detected_at = now() - (case p.rn when 1 then interval '10 days' when 2 then interval '40 days' else interval '100 days' end),
       due_date = current_date - (case p.rn when 1 then 7 when 2 then 37 else 97 end)
  from pick p where x.id = p.id;
alter table public.exception enable trigger exception_guard;
commit;
select age_bucket, count(*) as exceptions, count(*) filter (where target_breached) as target_breached from public.v_exception where status in ('open','acknowledged') group by 1 order by 1;
