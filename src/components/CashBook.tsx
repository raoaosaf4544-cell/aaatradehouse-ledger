import { useEffect, useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { engine } from '../lib/engine'
import type { CashBookDay } from '../lib/types'
import { Badge, Card, DateField, ErrorBanner, Money, SectionTitle, Spinner, dateInWords, todayPK } from './ui'

/**
 * Cash book, read-only: one day at a time, the way the paper roznamcha is kept — opening balance, every cash line
 * with its running balance, day totals and closing balance. All figures come from the database (v_cash_book,
 * v_cash_days); nothing here can change the books.
 */
export default function CashBook() {
  const [date, setDate] = useState(todayPK)
  const [data, setData] = useState<CashBookDay | null>(null)
  const [error, setError] = useState<unknown>(null)

  useEffect(() => {
    let alive = true
    setData(null)
    setError(null)
    engine
      .cashDay(date)
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(e))
    return () => {
      alive = false
    }
  }, [date])

  const opening = data ? (data.day?.opening_paisa ?? data.before?.closing_paisa ?? 0) : 0
  const closing = data ? (data.day?.closing_paisa ?? opening) : 0
  const navBtn =
    'flex min-h-11 flex-1 items-center justify-center gap-1 rounded-xl border-2 border-slate-300 bg-white px-3 text-base font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50'

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">Cash book</h2>
        <p className="mt-1 text-base text-slate-600">One day at a time — tick each line against the paper roznamcha.</p>
      </div>

      <Card>
        <DateField label="Day" value={date} onChange={(v) => v && setDate(v)} />
        <div className="mt-3 flex gap-2">
          <button type="button" className={navBtn} disabled={!data?.before} onClick={() => data?.before && setDate(data.before.occurred_on)}>
            <ChevronLeft className="h-5 w-5" /> Previous day
          </button>
          <button type="button" className={navBtn} disabled={!data?.after} onClick={() => data?.after && setDate(data.after)}>
            Next day <ChevronRight className="h-5 w-5" />
          </button>
        </div>
        <p className="mt-2 text-sm text-slate-600">Previous / Next jump to the days that have cash entries.</p>
      </Card>

      {error != null && <ErrorBanner error={error} />}
      {!data && error == null && <Spinner />}

      {data && (
        <>
          <Card>
            <div className="flex items-baseline justify-between gap-3">
              <span className="text-base font-semibold text-slate-700">Opening balance — {dateInWords(date)}</span>
              <span className="text-xl font-bold text-slate-900"><Money paisa={opening} /></span>
            </div>
          </Card>

          <Card>
            <SectionTitle>{data.lines.length === 0 ? 'No cash in or out on this day' : `${data.lines.length} line(s) on this day`}</SectionTitle>
            {data.lines.length > 0 && (
              <ol className="divide-y divide-slate-200">
                {data.lines.map((l, i) => (
                  <li key={`${l.event_id}-${l.entry_seq}`} className="py-3">
                    <div className="flex items-start gap-3">
                      <span className="mt-0.5 w-7 shrink-0 text-right text-base font-bold text-slate-600">{i + 1}.</span>
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-mono text-sm text-slate-600">{l.event_ref}</span>
                          {l.source === 'correction' && <Badge tone="amber">correction</Badge>}
                        </div>
                        <div className="mt-0.5 break-words text-base text-slate-900">{l.description}</div>
                        <div className="mt-1 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                          {l.in_paisa > 0 ? (
                            <span className="text-base font-semibold text-emerald-800">In <Money paisa={l.in_paisa} /></span>
                          ) : (
                            <span className="text-base font-semibold text-rose-800">Out <Money paisa={l.out_paisa} /></span>
                          )}
                          <span className="text-sm text-slate-600">Balance <Money paisa={l.balance_paisa} /></span>
                        </div>
                      </div>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>

          <Card>
            <SectionTitle>Day totals</SectionTitle>
            <div className="space-y-2 text-base">
              <div className="flex justify-between gap-3">
                <span className="text-slate-700">Money in</span>
                <span className="font-semibold text-emerald-800"><Money paisa={data.day?.in_paisa ?? 0} /></span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-slate-700">Money out</span>
                <span className="font-semibold text-rose-800"><Money paisa={data.day?.out_paisa ?? 0} /></span>
              </div>
              <div className="flex items-baseline justify-between gap-3 border-t border-slate-200 pt-2">
                <span className="font-semibold text-slate-800">Closing balance</span>
                <span className="text-xl font-bold text-slate-900"><Money paisa={closing} /></span>
              </div>
            </div>
          </Card>
        </>
      )}
    </div>
  )
}
