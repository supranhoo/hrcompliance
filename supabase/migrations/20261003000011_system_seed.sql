-- 0011 System seed required in EVERY environment: roles, role grants, numbering rules, structural LOV sets,
-- module registry, integration placeholders, job definitions. Idempotent (ON CONFLICT DO NOTHING).
-- Contains NO legal/statutory content and NO BFCL business data (req. 79). Dev-only data lives in supabase/seed/.
insert into public.role (code, name, description, is_system) values
  ('SUPER_ADMIN','Super Admin','Full configuration and user administration',true),
  ('HEAD_HR','Head HR','Executive view and management of all HR compliance',true),
  ('PLANT_HR','Plant HR','Operational HR for assigned locations',true),
  ('HOD','Head of Department','Department-level visibility',true),
  ('VIEWER','Viewer','Read-only',true)
on conflict (code) do nothing;

insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on (
     (r.code = 'SUPER_ADMIN')
  or (r.code = 'HEAD_HR'  and p.code in ('master.read','master.write','config.read','audit.read','user.read','health.read','job.read'))
  or (r.code = 'PLANT_HR' and p.code in ('master.read','config.read'))
  or (r.code = 'HOD'      and p.code in ('master.read'))
  or (r.code = 'VIEWER'   and p.code in ('master.read')))
on conflict do nothing;

insert into public.numbering_rule (key, description, reset_policy, pad_width) values
  ('CMP','Compliance instance','yearly',6), ('CTR','Contractor','never',6), ('BILL','Contractor bill','yearly',6),
  ('ESIC','ESIC case','yearly',6), ('GRC','Grievance case','yearly',6), ('DISC','Disciplinary case','yearly',6),
  ('LIA','Government liaison case','yearly',6), ('LIC','Licence','never',6), ('EXC','Exception','yearly',6),
  ('EVD','Evidence','yearly',6), ('COM','Communication','yearly',6)
on conflict (key) do nothing;

insert into public.lov_set (code, name, is_system) values
  ('RISK','Risk level',true), ('SEVERITY','Severity',true), ('FREQUENCY','Frequency',true),
  ('AUTHORITY_TYPE','Authority type',true), ('ESTABLISHMENT_TYPE','Establishment type',true),
  ('DOCUMENT_CATEGORY','Document category',true), ('DISPATCH_MODE','Dispatch mode',true), ('COMMUNICATION_TYPE','Communication type',true)
on conflict (code) do nothing;

insert into public.module_definition (code, name, sort_order) values
  ('compliance','Compliance',10), ('contractor','Contractor Compliance',20), ('licence','Licences',30), ('evidence','Evidence',40),
  ('exception','Exceptions',50), ('esic','ESIC',60), ('grievance','Grievance (GRC)',70), ('disciplinary','Disciplinary',80),
  ('liaison','Government Liaison',90), ('plant_visit','Plant Visit & CAPA',100), ('communication','Communication',110),
  ('admin','Administration',120)
on conflict (code) do nothing;

insert into public.system_config (key, value, description) values
  ('integration.google_drive', '{"state":"NOT_CONFIGURED"}', 'Document storage adapter state'),
  ('integration.gmail',        '{"state":"NOT_CONFIGURED"}', 'Mail adapter state')
on conflict (key) do nothing;

insert into public.job_definition (code, name, description, schedule_cron) values
  ('compliance_generation','Recurring compliance generation','Creates due compliance instances from the compliance master (idempotent by compliance+location+period)','0 1 * * *'),
  ('due_status_refresh','Due-status refresh','Refreshes upcoming/due-soon/overdue states','15 1 * * *'),
  ('licence_expiry_detection','Licence expiry detection','Flags expiring/expired licences','30 1 * * *'),
  ('exception_generation','Exception generation','Evaluates exception rules across modules','45 1 * * *'),
  ('alert_generation','Alert generation','Creates alerts/escalations per alert rules','0 2 * * *'),
  ('communication_followup','Communication follow-up detection','Detects overdue responses','15 2 * * *'),
  ('housekeeping','Housekeeping','Purges expired temporary data','0 3 * * 0')
on conflict (code) do nothing;
