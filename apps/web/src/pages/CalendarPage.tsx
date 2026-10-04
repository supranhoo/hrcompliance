import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { Badge, Button, Drawer, EmptyState, ErrorState, Skeleton, cx } from '../components/ui'
import { dueStateBadge, titleCase } from '../lib/badges'
import { groupByDate, monthMatrix, rangeFor, shift, weekDays, worstState, type CalItem } from '../lib/calendar'
import { isoDate } from '../lib/urlFilters'

type View = 'month' | 'week' | 'agenda'
const DOT: Record<string, string> = { overdue: 'bg-status-crit', due_soon: 'bg-status-warn', upcoming: 'bg-status-info', completed: 'bg-status-ok', not_applicable: 'bg-muted' }

function Chip({ it, onClick }: { it: CalItem; onClick: () => void }) {
  const b = dueStateBadge[it.due_state] ?? dueStateBadge.upcoming
  return <button type="button" onClick={onClick} title={`${it.compliance_name} · ${it.location_code} · ${b.label}`} className="flex w-full items-center gap-1 truncate rounded px-1 py-0.5 text-left text-xs hover:bg-canvas">
    <span aria-hidden className={cx('size-2 shrink-0 rounded-full', DOT[it.due_state])} /><span className="truncate">{it.compliance_code} · {it.location_code}</span><span className="sr-only">{b.label}</span></button>
}

/** Month / Week / Agenda over the compliance_calendar RPC. The server returns only the visible range; nothing is filtered in the browser. */
export function CalendarPage() {
  const [view, setView] = useState<View>('month')
  const [anchor, setAnchor] = useState(() => new Date())
  const [day, setDay] = useState<string | null>(null)
  const { from, to } = rangeFor(view, anchor)
  const q = useQuery({ queryKey: ['calendar', from, to], enabled: !!supabase, placeholderData: (p) => p, queryFn: async (): Promise<CalItem[]> => {
    const { data, error } = await supabase!.rpc('compliance_calendar', { p_from: from, p_to: to }); if (error) throw error; return (data ?? []) as CalItem[] } })
  const items = q.data ?? []; const byDate = groupByDate(items)
  const today = isoDate(new Date())
  const title = view === 'month' ? anchor.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }) : `${from} → ${to}`
  const dayItems = day ? (byDate.get(day) ?? []) : []
  const cell = (d: Date, compact: boolean) => { const k = isoDate(d); const list = byDate.get(k) ?? []; const inMonth = d.getMonth() === anchor.getMonth()
    return (
      <div key={k} className={cx('min-h-24 border-b border-r border-line p-1', !inMonth && view === 'month' && 'bg-canvas/60 text-muted')}>
        <button type="button" onClick={() => setDay(k)} className={cx('mb-1 flex w-full items-center justify-between text-xs', k === today && 'font-semibold text-blue')} aria-label={`${k}, ${list.length} item(s)`}><span>{d.getDate()}</span>{list.length > 0 && <span className={cx('size-2 rounded-full', DOT[worstState(list)])} aria-hidden />}</button>
        {list.slice(0, compact ? 3 : 8).map((it) => <Chip key={it.instance_id} it={it} onClick={() => setDay(k)} />)}
        {list.length > (compact ? 3 : 8) && <button type="button" className="text-xs text-blue hover:underline" onClick={() => setDay(k)}>+{list.length - (compact ? 3 : 8)} more</button>}
      </div>) }
  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-xl font-semibold text-navy">Compliance Calendar</h1>
        <div className="flex items-center gap-2">
          <div role="group" aria-label="View" className="flex overflow-hidden rounded border border-line">{(['month', 'week', 'agenda'] as View[]).map((v) => <button key={v} type="button" aria-pressed={view === v} onClick={() => setView(v)} className={cx('px-3 py-1 text-sm', view === v ? 'bg-navy text-white' : 'bg-white hover:bg-canvas')}>{titleCase(v)}</button>)}</div>
          <Button variant="secondary" aria-label="Previous" onClick={() => setAnchor(shift(view, anchor, -1))}>‹</Button>
          <Button variant="secondary" onClick={() => setAnchor(new Date())}>Today</Button>
          <Button variant="secondary" aria-label="Next" onClick={() => setAnchor(shift(view, anchor, 1))}>›</Button>
        </div>
      </div>
      <p className="text-sm font-medium text-ink" aria-live="polite">{title}</p>
      <ul className="flex flex-wrap gap-3 text-xs text-muted" aria-label="Legend">{Object.entries(dueStateBadge).map(([k, b]) => <li key={k} className="flex items-center gap-1"><span className={cx('size-2 rounded-full', DOT[k])} aria-hidden />{b.label}</li>)}</ul>
      {q.error ? <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} /> : q.isLoading ? <Skeleton rows={6} className="h-8" /> : (
        <>
          {view === 'month' && <div className="overflow-hidden rounded-lg border border-line bg-white"><div className="grid grid-cols-7 border-b border-line bg-canvas text-center text-xs font-medium text-muted">{['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => <div key={d} className="py-1">{d}</div>)}</div><div className="grid grid-cols-7 border-l border-t border-line">{monthMatrix(anchor.getFullYear(), anchor.getMonth()).map((d) => cell(d, true))}</div></div>}
          {view === 'week' && <div tabIndex={0} role="region" aria-label="Week view, scrollable" className="overflow-x-auto rounded-lg border border-line bg-white"><div className="grid min-w-[40rem] grid-cols-7 border-l border-t border-line">{weekDays(anchor).map((d) => cell(d, false))}</div></div>}
          {view === 'agenda' && (items.length === 0 ? <EmptyState title="Nothing due in this period" description="Only obligations in your scope are shown." /> : (
            <ol className="space-y-3">{[...byDate.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, list]) => (
              <li key={date} className="rounded-lg border border-line bg-white p-3"><h2 className="text-sm font-semibold text-navy">{new Date(date + 'T00:00:00').toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}</h2>
                <ul className="mt-2 divide-y divide-line">{list.map((it) => { const b = dueStateBadge[it.due_state] ?? dueStateBadge.upcoming; return <li key={it.instance_id} className="flex items-center justify-between gap-2 py-1.5 text-sm"><Link className="min-w-0 hover:underline" to={`/compliance?q=${encodeURIComponent(it.instance_no)}`}><span className="block truncate">{it.compliance_name}</span><span className="text-xs text-muted">{it.instance_no} · {it.location_code}</span></Link><Badge tone={b.tone}>{b.label}</Badge></li> })}</ul></li>))}</ol>))}
          {view !== 'agenda' && items.length === 0 && <p className="text-sm text-muted">Nothing due in this period.</p>}
        </>)}
      <Drawer open={!!day} onClose={() => setDay(null)} title={day ? new Date(day + 'T00:00:00').toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : ''}>
        {dayItems.length === 0 ? <p className="text-sm text-muted">Nothing due on this day.</p> : (
          <ul className="space-y-2">{dayItems.map((it) => { const b = dueStateBadge[it.due_state] ?? dueStateBadge.upcoming; return (
            <li key={it.instance_id} className="rounded border border-line p-2 text-sm"><div className="flex items-start justify-between gap-2"><div className="min-w-0"><p className="font-medium">{it.compliance_name}</p><p className="text-xs text-muted">{it.instance_no} · {it.location_code} · {titleCase(it.risk_level)} risk</p></div><Badge tone={b.tone}>{b.label}</Badge></div>
              <Link className="mt-2 inline-block text-blue hover:underline" to={`/compliance?q=${encodeURIComponent(it.instance_no)}`}>Open in register</Link></li>) })}</ul>)}
      </Drawer>
    </section>
  )
}
