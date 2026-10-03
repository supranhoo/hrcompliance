-- 0029 Evidence requirement configuration. Per rule version and document type a requirement now also carries:
--   * validity_months    - default expiry applied to uploaded evidence (counted from the upload date) when the uploader gives no explicit expiry;
--   * requires_verification - false = evidence of that document is recorded as verified on upload (audited as "not required"); true (default) = pending review;
--   * help_text          - instruction shown to the person uploading.
-- Requirements of a published rule version stay immutable (existing guard). The new-draft clone copies the new columns. Document types get format checks
-- (MIME syntax) so the admin screen and imports cannot store garbage. Verification itself still needs evidence.verify; the evidence chain is untouched.
-- Rollback: restore app.evidence_before_insert and public.compliance_rule_new_draft from 0018/0026; alter table compliance_rule_evidence drop columns validity_months, requires_verification, help_text;
--           alter table document_type drop constraint document_type_mime_ck.
alter table public.compliance_rule_evidence
  add column validity_months int check (validity_months is null or validity_months between 1 and 600),
  add column requires_verification boolean not null default true,
  add column help_text text check (help_text is null or length(help_text) <= 500);

alter table public.document_type add constraint document_type_mime_ck
  check (cardinality(allowed_mime_types) between 1 and 20 and array_to_string(allowed_mime_types, ',') ~ '^[A-Za-z0-9][A-Za-z0-9.+-]*/[A-Za-z0-9][A-Za-z0-9.+*-]*(,[A-Za-z0-9][A-Za-z0-9.+-]*/[A-Za-z0-9][A-Za-z0-9.+*-]*)*$');

CREATE OR REPLACE FUNCTION app.evidence_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare req public.compliance_rule_evidence; dt public.document_type; ci public.compliance_instance; li public.licence; flagged boolean := coalesce(current_setting('app.evidence_replace', true), '') = '1';
begin
  if num_nonnulls(new.compliance_instance_id, new.licence_id) <> 1 then raise exception 'evidence must be attached to exactly one parent record' using errcode = '23514'; end if;
  if new.compliance_instance_id is not null then
    select * into ci from public.compliance_instance where id = new.compliance_instance_id;
    if not found then raise exception 'unknown compliance instance' using errcode = '22023'; end if;
    new.entity_id := ci.entity_id; new.location_id := ci.location_id;
    new.period_start := coalesce(new.period_start, ci.period_start); new.period_end := coalesce(new.period_end, ci.period_end);
  else
    select * into li from public.licence where id = new.licence_id;
    if not found then raise exception 'unknown licence' using errcode = '22023'; end if;
    new.entity_id := li.entity_id; new.location_id := li.location_id;
  end if;
  select * into dt from public.document_type where id = new.document_type_id and is_active;
  if not found then raise exception 'unknown or inactive document type' using errcode = '22023'; end if;
  if not (lower(new.mime_type) = any (select lower(x) from unnest(dt.allowed_mime_types) x)) then
    raise exception 'file type % is not allowed for document type %', new.mime_type, dt.code using errcode = '23514';
  end if;
  if new.size_bytes > dt.max_size_mb::bigint * 1024 * 1024 then
    raise exception 'file exceeds the % MB limit for document type %', dt.max_size_mb, dt.code using errcode = '23514';
  end if;
  if not flagged then
    if new.supersedes_id is not null then raise exception 'use evidence_replace() to add a new version' using errcode = '42501'; end if;
    new.version := 1; new.is_current := true; new.replace_reason := null;
  end if;
  new.uploaded_by := coalesce(auth.uid(), new.uploaded_by); new.uploaded_at := now();
  select * into req from public.compliance_rule_evidence r where new.compliance_instance_id is not null and r.document_type_id = new.document_type_id
     and r.rule_version_id = (select rule_version_id from public.compliance_instance where id = new.compliance_instance_id);
  if found and new.expiry_date is null and req.validity_months is not null then new.expiry_date := (current_date + make_interval(months => req.validity_months))::date; end if;   -- default validity counted from the upload date
  if found and not req.requires_verification then
    new.verification_status := 'verified'; new.verified_by := null; new.verified_at := now(); new.verification_remarks := 'Verification not required for this document (rule configuration)';
  else
    new.verification_status := 'pending_review'; new.verified_by := null; new.verified_at := null; new.verification_remarks := null;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.compliance_rule_new_draft(p_compliance uuid, p_effective_from date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare src public.compliance_rule_version; v_new uuid;
begin
  if not app.has_permission('compliance.manage') then raise exception 'permission denied' using errcode = '42501'; end if;
  if exists (select 1 from public.compliance_rule_version where compliance_id = p_compliance and status = 'draft') then
    raise exception 'a draft version already exists for this compliance: edit or discard it first' using errcode = '23505';
  end if;
  select * into src from public.compliance_rule_version where compliance_id = p_compliance order by version desc limit 1;
  if not found then raise exception 'this compliance has no rule version to copy; create the first version instead' using errcode = '22023'; end if;
  insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, period_start_month, due_rule, risk_level, criticality, evidence_required,
                                              alert_rule_code, escalation_rule_code, effective_from, custom)
  values (src.compliance_id, src.compliance_type, src.frequency, src.period_start_month, src.due_rule, src.risk_level, src.criticality, src.evidence_required,
          src.alert_rule_code, src.escalation_rule_code, coalesce(p_effective_from, greatest(src.effective_from + 1, current_date)), src.custom)
  returning id into v_new;
  insert into public.compliance_rule_evidence (rule_version_id, document_type_id, is_mandatory, validity_months, requires_verification, help_text)
  select v_new, e.document_type_id, e.is_mandatory, e.validity_months, e.requires_verification, e.help_text from public.compliance_rule_evidence e where e.rule_version_id = src.id;
  return v_new;
end $function$;

