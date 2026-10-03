-- 0030 Read models for alert-rule administration: v_alert_rule (every version of every rule with its parts split out) and v_alert_routing_issue
-- (the D-001 routing validation as a register). Both run with the caller's rights; the validation function still requires health.read or config.read.
-- Rollback: drop view public.v_alert_routing_issue, public.v_alert_rule;
create view public.v_alert_rule with (security_invoker = true) as
select c.id, c.code, c.name, c.version, c.status, coalesce(c.definition ->> 'applies', 'compliance') as applies, c.definition -> 'offsets' as offsets, c.definition -> 'channels' as channels,
       c.definition -> 'recipients' as recipients, coalesce((c.definition ->> 'critical')::boolean, false) as critical, c.definition, c.effective_from, c.effective_to, c.change_reason, c.row_version,
       (c.version = max(c.version) over (partition by c.code)) as is_latest
  from public.config_definition c where c.kind = 'alert_rule';
grant select on public.v_alert_rule to authenticated;

create view public.v_alert_routing_issue with (security_invoker = true) as
select v.rule_code, v.severity, v.problem from public.alert_routing_validation() v;
grant select on public.v_alert_routing_issue to authenticated;
