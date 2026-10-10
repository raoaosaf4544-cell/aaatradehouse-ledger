import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import type { PlantRateRow } from '../lib/types'
import { Bi, Card, ErrorBanner, Kg, Money, SectionTitle, Spinner, todayPK } from './ui'

/**
 * Plant rate check, per month: the real plant bills (5410-5440) against the plant cost the crushes charged to the
 * salt (5490). Every figure is the database's (public.v_plant_rate_check). Nothing changes the rate by itself.
 */
export default function PlantRateCheck() {
  const [rows, setRows] = useState<PlantRateRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const thisMonth = todayPK().slice(0, 7) + '-01'
  const [month, setMonth] = useState(thisMonth)

  useEffect(() => {
    engine.plantRateCheck().then(setRows).catch(setError)
  }, [])

  if (error) return <ErrorBanner error={error} />
  if (!rows) return <Spinner />

  const months = [...new Set([thisMonth, ...rows.map((r) => r.month)])].sort().reverse()
  // a month with no plant bills and no crush has no row: every figure is truly 0
  const r = rows.find((x) => x.month === month) ?? {
    month, actual_bills_paisa: 0, charged_paisa: 0, under_charged_paisa: 0, rock_crushed_grams: 0, suggested_rate_paisa_per_kg: null,
  }
  const diff = r.under_charged_paisa

  return (
    <Card>
      <SectionTitle><Bi en="Plant rate check" ur="پلانٹ ریٹ چیک" /></SectionTitle>
      <select value={month} onChange={(e) => setMonth(e.target.value)} aria-label="Month" className="mb-4 min-h-11 rounded-lg border border-slate-300 bg-white px-3 text-base">
        {months.map((m) => (
          <option key={m} value={m}>{new Date(m + 'T00:00:00').toLocaleDateString('en-PK', { month: 'long', year: 'numeric' })}</option>
        ))}
      </select>
      <dl className="grid grid-cols-1 gap-3 text-base sm:grid-cols-2">
        <div className="rounded-xl bg-slate-50 p-3">
          <dt className="text-sm text-slate-600"><Bi en="Actual plant bills" ur="پلانٹ کے اصل بل" /></dt>
          <dd className="text-xl font-bold"><Money paisa={r.actual_bills_paisa} /></dd>
        </div>
        <div className="rounded-xl bg-slate-50 p-3">
          <dt className="text-sm text-slate-600"><Bi en="Plant cost charged to salt" ur="نمک پر لگایا گیا خرچ" /></dt>
          <dd className="text-xl font-bold"><Money paisa={r.charged_paisa} /></dd>
        </div>
        <div className={`rounded-xl p-3 ${diff > 0 ? 'bg-amber-50 text-amber-900' : diff < 0 ? 'bg-blue-50 text-blue-900' : 'bg-emerald-50 text-emerald-900'}`}>
          <dt className="text-sm"><Bi en="Difference" ur="فرق" /></dt>
          <dd className="text-xl font-bold">
            {diff === 0 ? 'Even — no difference' : <>{diff > 0 ? 'Under-charged' : 'Over-charged'} <Money paisa={Math.abs(diff)} /></>}
          </dd>
        </div>
        <div className="rounded-xl bg-slate-50 p-3">
          <dt className="text-sm text-slate-600"><Bi en="Rock crushed" ur="پسا گیا پتھر" /></dt>
          <dd className="text-xl font-bold"><Kg grams={r.rock_crushed_grams} /></dd>
        </div>
      </dl>
      <p className="mt-4 rounded-xl border-2 border-amber-300 bg-amber-50 p-3 text-base">
        <Bi en="Suggested rate" ur="تجویز کردہ ریٹ" /> = actual bills ÷ kg crushed ={' '}
        {r.suggested_rate_paisa_per_kg == null ? (
          <strong>— (no rock crushed this month)</strong>
        ) : (
          <strong>Rs {(r.suggested_rate_paisa_per_kg / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}/kg</strong>
        )}
      </p>
      <p className="mt-2 text-sm text-slate-600">The difference stays in profit and loss. The rate never changes by itself — Rao decides the next rate on the Crush screen.</p>
    </Card>
  )
}
