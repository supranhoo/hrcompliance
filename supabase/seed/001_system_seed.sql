-- System seed: roles, role->permission grants, numbering rules, structural LOV sets.
-- Deliberately contains NO legal/statutory content (requirement 79) and no BFCL business data.
-- Idempotent: safe to re-run.
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
  or (r.code = 'HEAD_HR'  and p.code in ('master.read','master.write','config.read','audit.read','user.read'))
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

-- Structural LOV sets (values are admin-managed; none seeded beyond what the engine itself needs).
insert into public.lov_set (code, name, is_system) values
  ('RISK','Risk level',true), ('SEVERITY','Severity',true), ('FREQUENCY','Frequency',true),
  ('AUTHORITY_TYPE','Authority type',true), ('ESTABLISHMENT_TYPE','Establishment type',true),
  ('DOCUMENT_CATEGORY','Document category',true), ('DISPATCH_MODE','Dispatch mode',true), ('COMMUNICATION_TYPE','Communication type',true)
on conflict (code) do nothing;
