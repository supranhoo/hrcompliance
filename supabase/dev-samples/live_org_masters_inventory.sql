-- LIVE ORG MASTERS INVENTORY (read-only, one SELECT, changes nothing). For the Phase 4 master reconciliation (docs/migration/ORG_MASTER_RECONCILIATION.md).
-- The workflow "Verify DEV (live, read-only)" runs this file and publishes ONLY counts and GFA/HASP/Common flags (never the rows). A detailed inventory needs the owner's explicit approval: then paste this ENTIRE file into a new Supabase SQL Editor tab and run it once (organisation master data, no personal data).
-- Shows what already exists in each organisation master so GFA / HASP / Common / departments / designations / authorities are matched to REAL records and nothing is invented.
select 'entity' as master, code, name, null::text as parent_or_link, is_active from public.entity
union all select 'location', l.code, l.name, e.code, l.is_active from public.location l left join public.entity e on e.id = l.entity_id
union all select 'business_unit', b.code, b.name, e.code, b.is_active from public.business_unit b left join public.entity e on e.id = b.entity_id
union all select 'unit', u.code, u.name, coalesce(l.code, bu.code), u.is_active from public.unit u left join public.location l on l.id = u.location_id left join public.business_unit bu on bu.id = u.business_unit_id
union all select 'department', d.code, d.name, p.code, d.is_active from public.department d left join public.department p on p.id = d.parent_id
union all select 'designation', code, name, grade, is_active from public.designation
union all select 'authority', code, name, authority_type, is_active from public.authority
union all select 'COUNT ' || m, null, count(*)::text, null, null from (
  select 'entity' m from public.entity union all select 'location' from public.location union all select 'business_unit' from public.business_unit union all select 'unit' from public.unit
  union all select 'department' from public.department union all select 'designation' from public.designation union all select 'authority' from public.authority) c group by m
order by 1, 2;
-- END OF FILE
