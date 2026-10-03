-- 0012 Least privilege on a Supabase-managed helper found by the live security audit (2026-10-03).
-- public.rls_auto_enable() is the event-trigger helper behind the "Automatic RLS" setting. It is owned by the platform,
-- but it was executable by PUBLIC/authenticated. Event-trigger functions are not meant to be called through the Data API,
-- and execute rights are only checked when the event trigger is created, so revoking API execute does not stop it firing.
-- Guarded: a no-op on databases where the helper does not exist (e.g. a bare local Postgres).
-- Rollback: grant execute on function public.rls_auto_enable() to authenticated;  (not recommended)
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;
