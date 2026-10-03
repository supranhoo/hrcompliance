-- 0004 Concurrency-safe human-readable business IDs (CMP-2026-000001, CTR-000001, ...).
-- One atomic UPSERT..RETURNING per call: row lock serialises concurrent callers, no duplicates, no gaps on success.
-- Gapless: the counter update commits or rolls back together with the calling transaction.
-- Rollback: drop function app.next_business_id; drop table number_counter, numbering_rule;

create table public.numbering_rule (
  key text primary key check (key ~ '^[A-Z]{2,6}$'),
  description text,
  reset_policy text not null check (reset_policy in ('yearly','never')),
  pad_width int not null default 6 check (pad_width between 3 and 10),
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
create trigger numbering_rule_stamp before insert or update on public.numbering_rule for each row execute function app.stamp_row();

create table public.number_counter (
  rule_key text not null references public.numbering_rule(key),
  period_key text not null,                  -- 'ALL' or year e.g. '2026'
  last_value bigint not null default 0,
  primary key (rule_key, period_key)
);

create or replace function app.next_business_id(p_key text, p_on date default current_date) returns text
language plpgsql security definer set search_path = public as $$
declare r public.numbering_rule; v_period text; v_val bigint;
begin
  select * into r from public.numbering_rule where key = p_key;
  if not found then raise exception 'Unknown numbering rule %', p_key using errcode = '22023'; end if;
  v_period := case r.reset_policy when 'yearly' then to_char(p_on, 'YYYY') else 'ALL' end;
  insert into public.number_counter as c (rule_key, period_key, last_value) values (p_key, v_period, 1)
  on conflict (rule_key, period_key) do update set last_value = c.last_value + 1
  returning last_value into v_val;
  return p_key || '-' || case when r.reset_policy = 'yearly' then v_period || '-' else '' end || lpad(v_val::text, r.pad_width, '0');
end $$;
revoke all on function app.next_business_id(text, date) from public;
grant execute on function app.next_business_id(text, date) to service_role;
