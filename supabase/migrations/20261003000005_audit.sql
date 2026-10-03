-- 0005 Append-only audit log with generic row trigger.
-- Rollback: drop trigger audit_* on tables; drop table audit_log; drop function app.audit_row.
create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid,                              -- auth.users id (null = system/service)
  table_name text not null,
  record_id text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  changed_fields text[],
  old_data jsonb, new_data jsonb,
  reason text,                                -- set per-transaction: select set_config('app.audit_reason','...',true)
  request_id text                             -- set per-transaction: set_config('app.request_id', ...)
);
create index audit_log_record_idx on public.audit_log(table_name, record_id, at desc);
create index audit_log_actor_idx on public.audit_log(actor_id, at desc);
create index audit_log_at_idx on public.audit_log(at desc);

create or replace function app.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_noise text[] := array['updated_at','updated_by','row_version'];
  v_changed text[]; v_id text;
begin
  v_id := coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'code', v_old ->> 'code', v_new ->> 'key', v_old ->> 'key',
                   concat_ws(':', coalesce(v_new, v_old) ->> 'user_id', coalesce(v_new, v_old) ->> 'role_id', coalesce(v_new, v_old) ->> 'permission_code',
                   coalesce(v_new, v_old) ->> 'section_id', coalesce(v_new, v_old) ->> 'field_key', coalesce(v_new, v_old) ->> 'field_id'));
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_changed
      from (select key as k from jsonb_each(v_new)
            where v_old -> key is distinct from v_new -> key and key <> all(v_noise)) d;
    if v_changed is null then return new; end if;     -- only stamp columns changed
  end if;
  insert into public.audit_log (actor_id, table_name, record_id, action, changed_fields, old_data, new_data, reason, request_id)
  values (auth.uid(), tg_table_name, v_id, tg_op, v_changed, v_old, v_new,
          nullif(current_setting('app.audit_reason', true), ''), nullif(current_setting('app.request_id', true), ''));
  return coalesce(new, old);
end $$;

-- Immutability: no UPDATE/DELETE/TRUNCATE on audit_log for anyone (including table owner via normal SQL).
create or replace function app.audit_immutable() returns trigger language plpgsql as $$
begin raise exception 'audit_log is append-only' using errcode = '42501'; end $$;
create trigger audit_log_no_mutation before update or delete on public.audit_log for each row execute function app.audit_immutable();
create trigger audit_log_no_truncate before truncate on public.audit_log for each statement execute function app.audit_immutable();

-- Attach to every business/config table created so far.
do $$
declare t text;
begin
  foreach t in array array['entity','location','business_unit','unit','department','designation','authority','law','document_type',
                           'app_user','role','user_role','user_scope','role_permission','numbering_rule']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()', 'audit_'||t, t);
  end loop;
end $$;
