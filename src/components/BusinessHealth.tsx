import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import type { BusinessHealth as BH, BusinessTrendRow } from '../lib/types'
import { BOOKS_START, Bi, Card, ErrorBanner, Money, Spinner, todayPK } from './ui'

/**
 * Business health / کاروبار کا حال — salt business only. Every number is the database's (public.business_health),
 * whose totals are the ledger's own; a figure that cannot be worked out shows "—" with the reason.
 */

const SINCE_START = 'start'
const monthName = (m: string) => new Date(m + 'T00:00:00').toLocaleDateString('en-PK', { month: 'long', year: 'numeric' })
const lastDay = (m: string) => {
  const d = new Date(m + 'T00:00:00')
  return new Date(d.getFullYear(), d.getMonth() + 1, 0).toLocaleDateString('en-CA')
}
const kg = (g: number) => (g / 1000).toLocaleString('en-PK', { maximumFractionDigits: 1 })
const rs = (p: number) => `Rs ${(p / 100).toLocaleString('en-PK', { maximumFractionDigits: 0 })}`

function months(): string[] {
  const out: string[] = []
  const end = todayPK().slice(0, 7)
  let [y, m] = BOOKS_START.slice(0, 7).split('-').map(Number)
  while (`${y}-${String(m).padStart(2, '0')}` <= end) {
    out.unshift(`${y}-${String(m).padStart(2, '0')}-01`)
    m === 12 ? ((m = 1), y++) : m++
  }
  return out
}

export default function BusinessHealth() {
  const [period, setPeriod] = useState(todayPK().slice(0, 7) + '-01')
  const [h, setH] = useState<BH | null>(null)
  const [start, setStart] = useState<BH | null>(null)
  const [trend, setTrend] = useState<BusinessTrendRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)

  useEffect(() => {
    setH(null)
    setError(null)
    const p = period === SINCE_START ? engine.businessHealth(null, null) : engine.businessHealth(period, lastDay(period))
    p.then(setH).catch(setError)
  }, [period])
  useEffect(() => {
    engine.businessHealth(null, null).then(setStart).catch(() => setStart(null))
    engine.businessTrend().then(setTrend).catch(() => setTrend(null))
  }, [])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-2xl font-bold text-slate-800"><Bi en="Business health" ur="کاروبار کا حال" /></h2>
        <select value={period} onChange={(e) => setPeriod(e.target.value)} aria-label="Period" className="min-h-11 rounded-lg border border-slate-300 bg-white px-3 text-base">
          {months().map((m) => <option key={m} value={m}>{monthName(m)}</option>)}
          <option value={SINCE_START}>Since start / شروع سے</option>
        </select>
      </div>
      {error != null && <ErrorBanner error={error} />}
      {!h ? error == null && <Spinner /> : <Page h={h} start={start} trend={trend} />}
    </div>
  )
}

function Section({ n, en, ur, children }: { n: number; en: string; ur: string; children: React.ReactNode }) {
  return (
    <Card>
      <h3 className="mb-3 text-lg font-bold text-slate-800">{n}. <Bi en={en} ur={ur} /></h3>
      {children}
    </Card>
  )
}

function Row({ label, children, strong }: { label: React.ReactNode; children: React.ReactNode; strong?: boolean }) {
  return (
    <div className={`flex items-baseline justify-between gap-3 border-b border-slate-100 py-1.5 text-base ${strong ? 'font-bold' : ''}`}>
      <span className="text-slate-700">{label}</span>
      <span className="text-right font-mono tabular-nums">{children}</span>
    </div>
  )
}

const Dash = ({ why }: { why: string }) => <span className="text-slate-500">— <span className="font-sans text-sm">({why})</span></span>

function Page({ h, start, trend }: { h: BH; start: BH | null; trend: BusinessTrendRow[] | null }) {
  const net = h.net_profit_paisa
  const customers = h.gross.customers
  const top = customers.slice(0, 5)
  const bottom = customers.length > 5 ? customers.slice(-5).reverse() : []
  const bagsNeeded = h.break_even.bags_needed
  const pct = bagsNeeded ? Math.min(100, Math.round((h.break_even.bags_sold / bagsNeeded) * 100)) : 0

  return (
    <>
      <p className="text-sm text-slate-500">{h.from} to {h.to} ({h.days} days) · salt business only · from the books</p>

      <Section n={1} en="Sales" ur="فروخت">
        <Row label="Total sales" strong><Money paisa={h.sales.total_paisa} /></Row>
        <Row label="Salt sold">{kg(h.sales.grams)} kg = {h.sales.bags.toLocaleString()} bags of 50 kg</Row>
        {h.sales.by_product.map((p) => (
          <Row key={p.code} label={<>· {p.name} ({kg(p.grams)} kg)</>}><Money paisa={p.revenue_paisa} /></Row>
        ))}
        {h.sales.adjustments_paisa !== 0 && <Row label="· Adjustments (corrections, not on a sale line)"><Money paisa={h.sales.adjustments_paisa} /></Row>}
        <Row label="Cash received on the sale"><Money paisa={h.sales.cash_paisa} /></Row>
        <Row label="Udhaar (on credit)"><Money paisa={h.sales.udhaar_paisa} /></Row>
        {h.sales.advance_paisa > 0 && <Row label="From customer advances"><Money paisa={h.sales.advance_paisa} /></Row>}
      </Section>

      <Section n={2} en="Gross profit" ur="مجموعی منافع">
        <Row label="Sales"><Money paisa={h.sales.total_paisa} /></Row>
        <Row label="− Cost of salt sold"><Money paisa={h.gross.cogs_paisa} /></Row>
        <Row label="= Gross profit" strong><Money paisa={h.gross.profit_paisa} /></Row>
        <Row label="Margin">{h.gross.margin_pct != null ? `${h.gross.margin_pct}%` : <Dash why="no sales" />}</Row>
        <Row label="Profit per kg">{h.gross.per_kg_paisa != null ? rs(h.gross.per_kg_paisa) : <Dash why="no salt sold" />}</Row>
        <Row label="Profit per 50 kg bag">{h.gross.per_bag_paisa != null ? rs(h.gross.per_bag_paisa) : <Dash why="no salt sold" />}</Row>
        {h.sales.by_product.map((p) => (
          <Row key={p.code} label={<>· {p.name}</>}><Money paisa={p.profit_paisa} /></Row>
        ))}
        {h.gross.cogs_adjustments_paisa !== 0 && <Row label="· Cost adjustments (corrections)"><Money paisa={-h.gross.cogs_adjustments_paisa} /></Row>}
        {top.length > 0 && (
          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <div className="text-sm font-semibold text-emerald-700">Top customers by profit</div>
              {top.map((c) => <Row key={c.name} label={c.name}><Money paisa={c.profit_paisa} /></Row>)}
            </div>
            {bottom.length > 0 && (
              <div>
                <div className="text-sm font-semibold text-rose-700">Bottom customers by profit</div>
                {bottom.map((c) => <Row key={c.name} label={c.name}><Money paisa={c.profit_paisa} /></Row>)}
              </div>
            )}
          </div>
        )}
        {h.gross.below_cost.length > 0 && (
          <div className="mt-3 rounded-xl bg-rose-50 p-3">
            <div className="text-sm font-semibold text-rose-800">Sold below cost / لاگت سے کم</div>
            {h.gross.below_cost.map((b) => (
              <div key={b.sale_ref + b.product} className="text-sm text-rose-900">
                {b.date} · {b.sale_ref} · {b.customer} · {b.product} {kg(b.grams)} kg: sold {rs(b.revenue_paisa)}, cost {rs(b.cogs_paisa)}
              </div>
            ))}
          </div>
        )}
      </Section>

      <Section n={3} en="Running costs" ur="روزمرہ اخراجات">
        <Row label={<>Plant (bills {rs(h.costs.plant_bills_paisa)} − charged to salt {rs(h.costs.plant_charged_paisa)})</>}><Money paisa={h.costs.plant_paisa} /></Row>
        <Row label="Labour"><Money paisa={h.costs.labour_paisa} /></Row>
        <Row label="Transport / kiraya, fuel, travel"><Money paisa={h.costs.transport_paisa} /></Row>
        <Row label="Packing"><Money paisa={h.costs.packing_paisa} /></Row>
        <Row label="Shop & admin, utilities, repairs"><Money paisa={h.costs.shop_admin_paisa} /></Row>
        <Row label="Site meals & other"><Money paisa={h.costs.other_paisa} /></Row>
        <Row label="= Running costs" strong><Money paisa={h.costs.running_paisa} /></Row>
        <Row label="One-time setup costs (apart)"><Money paisa={h.costs.one_time_paisa} /></Row>
      </Section>

      <Section n={4} en="Net profit" ur="خالص منافع">
        <div className={`rounded-2xl p-4 text-center ${net >= 0 ? 'bg-emerald-50 text-emerald-800' : 'bg-rose-50 text-rose-800'}`}>
          <div className="text-4xl font-bold"><Money paisa={net} /></div>
          <div className="mt-1 text-lg font-semibold">{net >= 0 ? <Bi en="profit" ur="منافع" /> : <Bi en="loss" ur="نقصان" />}</div>
        </div>
        <div className="mt-2 text-sm text-slate-600">
          Gross profit {rs(h.gross.profit_paisa)} + other income {rs(h.other_income_paisa)} − running costs {rs(h.costs.running_paisa)} − one-time {rs(h.costs.one_time_paisa)}
        </div>
      </Section>

      <Section n={5} en="Break-even" ur="برابر">
        {bagsNeeded == null ? (
          <Row label="Bags per month needed to cover costs"><Dash why={h.break_even.why_not ?? 'cannot be worked out'} /></Row>
        ) : (
          <>
            <Row label="Bags needed to cover running costs">{bagsNeeded.toLocaleString()} bags</Row>
            <Row label="Bags sold">{h.break_even.bags_sold.toLocaleString()} bags</Row>
            <div className="mt-2 h-4 w-full overflow-hidden rounded-full bg-slate-200" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
              <div className={`h-full ${pct >= 100 ? 'bg-emerald-500' : 'bg-amber-500'}`} style={{ width: `${pct}%` }} />
            </div>
            <div className="mt-1 text-sm text-slate-600">{pct}% of the way — running costs ÷ gross profit per bag ({h.gross.per_bag_paisa != null ? rs(h.gross.per_bag_paisa) : '—'})</div>
          </>
        )}
      </Section>

      <Section n={6} en="Cash position (now)" ur="نقدی">
        <Row label="Cash + bank"><Money paisa={h.cash.cash_paisa + h.cash.bank_paisa} /></Row>
        <Row label="Udhaar to collect"><Money paisa={h.cash.udhaar_paisa} /></Row>
        {h.cash.debtors.map((d) => (
          <Row key={d.name} label={<span className={d.days != null && d.days > 30 ? 'font-semibold text-rose-700' : ''}>· {d.name}{d.days != null && ` — ${d.days} days`}</span>}>
            <Money paisa={d.owed_paisa} />
          </Row>
        ))}
        <Row label="We owe (suppliers + wages)"><Money paisa={h.cash.suppliers_paisa + h.cash.wages_paisa} /></Row>
        <Row label="Advances given to workers"><Money paisa={h.cash.advances_paisa} /></Row>
        <Row label="Cash after collecting and paying everyone" strong><Money paisa={h.cash.after_all_paisa} /></Row>
      </Section>

      <Section n={7} en="Ghar vs business" ur="گھر بمقابلہ کاروبار">
        <Row label="Taken for ghar (drawings)"><Money paisa={h.ghar.drawings_paisa} /></Row>
        <Row label="Net profit"><Money paisa={net} /></Row>
        {h.ghar.more_than_profit && (
          <p className="mt-2 rounded-lg bg-rose-50 px-3 py-2 text-base font-semibold text-rose-800">Ghar is taking more than the business earns {h.days > 31 ? 'so far' : 'this month'}.</p>
        )}
      </Section>

      <Section n={8} en="Return" ur="منافع کی شرح">
        <Row label={`This period (on capital ${rs(h.return.capital_paisa)})`}>{h.return.pct != null ? `${h.return.pct}%` : <Dash why="no owner capital" />}</Row>
        <Row label="Since start">{start?.return.pct != null ? `${start.return.pct}%` : <Dash why="not loaded" />}</Row>
        <p className="mt-2 text-sm text-slate-500">Early months are usually negative while the business sets up.</p>
      </Section>

      <Section n={9} en="Stock" ur="اسٹاک">
        <Row label={`Rock ${kg(h.stock.rock_grams)} kg`}><Money paisa={h.stock.rock_paisa} /></Row>
        <Row label={`Crushed salt ${kg(h.stock.crushed_grams)} kg`}><Money paisa={h.stock.crushed_paisa} /></Row>
        <Row label="Days of stock left">
          {h.stock.days_left != null ? `${h.stock.days_left} days (at ${h.stock.kg_sold_per_day} kg a day)` : <Dash why="no salt sold in this period" />}
        </Row>
      </Section>

      {trend && trend.length >= 2 && (
        <Section n={10} en="Trend" ur="رجحان">
          <Trend rows={trend} />
        </Section>
      )}

      <p className="text-sm text-slate-500">
        Other activities (not in salt profit): goats {rs(h.other_activities.goats_paisa)} held as an asset.
      </p>
    </>
  )
}

function Trend({ rows }: { rows: BusinessTrendRow[] }) {
  const max = Math.max(1, ...rows.flatMap((r) => [Math.abs(r.sales_paisa), Math.abs(r.gross_profit_paisa), Math.abs(r.net_profit_paisa)]))
  const bars: { key: keyof BusinessTrendRow; label: string; cls: string }[] = [
    { key: 'sales_paisa', label: 'Sales', cls: 'bg-slate-500' },
    { key: 'gross_profit_paisa', label: 'Gross', cls: 'bg-emerald-500' },
    { key: 'net_profit_paisa', label: 'Net', cls: 'bg-blue-500' },
  ]
  return (
    <div className="space-y-3">
      {rows.map((r) => (
        <div key={r.month}>
          <div className="text-sm font-semibold text-slate-700">{monthName(r.month)}</div>
          {bars.map((b) => {
            const v = r[b.key] as number
            return (
              <div key={b.key} className="flex items-center gap-2 text-xs">
                <span className="w-12 text-slate-500">{b.label}</span>
                <div className="h-3 flex-1 rounded bg-slate-100">
                  <div className={`h-3 rounded ${v < 0 ? 'bg-rose-500' : b.cls}`} style={{ width: `${(Math.abs(v) / max) * 100}%` }} />
                </div>
                <span className="w-24 text-right font-mono">{rs(v)}</span>
              </div>
            )
          })}
        </div>
      ))}
    </div>
  )
}
