-- 0022 Status-change RPCs for the UI.
-- A status change that requires a reason needs the reason in the SAME transaction as the UPDATE (it is recorded in the audit log and checked by
-- app.enforce_status). PostgREST cannot do that across two requests, so these functions set the transaction-local audit reason and update.
-- They are SECURITY INVOKER: RLS, scope checks and every trigger apply exactly as for a direct UPDATE; a row outside the caller's scope is "not found".
-- Rollback: drop function public.compliance_set_status, public.exception_set_status;
create or replace function public.compliance_set_status(p_instance uuid, p_status text, p_reason text default null) returns void
language plpgsql security invoker as $$
begin
  if p_reason is not null and length(trim(p_reason)) > 0 then perform set_config('app.audit_reason', trim(p_reason), true); end if;
  update public.compliance_instance set status = p_status where id = p_instance;
  if not found then raise exception 'obligation not found or you do not have permission' using errcode = '42501'; end if;
end $$;

-- resolved / waived need a note (stored as the resolution and as the audit reason); other transitions may carry an optional note
create or replace function public.exception_set_status(p_id uuid, p_status text, p_note text default null) returns void
language plpgsql security invoker as $$
begin
  if p_note is not null and length(trim(p_note)) > 0 then perform set_config('app.audit_reason', trim(p_note), true); end if;
  update public.exception set status = p_status, resolution = case when p_status in ('resolved','waived') then trim(p_note) else resolution end where id = p_id;
  if not found then raise exception 'exception not found or you do not have permission' using errcode = '42501'; end if;
end $$;
revoke all on function public.compliance_set_status(uuid, text, text), public.exception_set_status(uuid, text, text) from public, anon;
grant execute on function public.compliance_set_status(uuid, text, text), public.exception_set_status(uuid, text, text) to authenticated;
