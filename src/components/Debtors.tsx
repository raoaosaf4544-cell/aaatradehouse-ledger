import { useEffect, useState } from 'react'
import { HandCoins } from 'lucide-react'
import { engine } from '../lib/engine'
import type { DebtorRow, DispatchAllocationRow, SalesTotals } from '../lib/types'
import { gramsToKg } from '../lib/types'
import { SaveControls, SavedBanner, useSafeSave } from './SafeSave'
import {
  Badge,
  Card,
  DateField,
  EmptyState,
  ErrorBanner,
  Field,
  inputCls,
  SectionTitle,
  ShowMore,
  Spinner,
  StatCard,
  todayPK,
  usePaged,
} from './ui'
import { EntryMenu } from './EntryActions'

/**
 * Debtors & Sales — who owes what, every invoice with its exact COGS and
 * gross margin (from public.v_sales), per-batch allocation drill-down
 * (public.v_dispatch_allocations), and customer payment recording.
 */
export default function Debtors({ onPosted }: { onPosted: () => void }) {
  const [debtors, setDebtors] = useState<DebtorRow[] | null>(null)
  const [totals, setTotals] = useState<SalesTotals | null>(null)
  const sales = usePaged((limit, offset) => engine.sales(limit, offset))
  const [allocsBySale, setAllocsBySale] = useState<Record<string, DispatchAllocationRow[]>>({})
  const [error, setError] = useState<unknown>(null)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [payFor, setPayFor] = useState<string | null>(null)
  const [payOwed, setPayOwed] = useState(0) // shown as a hint only; the amount starts empty
  const [payAmount, setPayAmount] = useState('')
  const [payDate, setPayDate] = useState(todayPK)
  const [payNote, setPayNote] = useState('')
  const paySafe = useSafeSave()

  useEffect(() => {
    Promise.all([engine.debtors(), engine.salesTotals()])
      .then(([d, t]) => {
        setDebtors(d)
        setTotals(t)
      })
      .catch(setError)
  }, [])

  const totalOutstanding = (debtors ?? []).reduce((s, d) => s + Math.max(d.outstanding_paisa, 0), 0)
  // All invoices, totalled by the database. Margin only over fully dispatched invoices (their cost is known).
  const totalRevenue = totals?.revenue_paisa ?? 0
  const marginBase = totals?.dispatched_revenue_paisa ?? 0
  const totalProfit = marginBase - (totals?.dispatched_cogs_paisa ?? 0)

  async function toggleInvoice(saleRef: string) {
    setExpanded(expanded === saleRef ? null : saleRef)
    if (allocsBySale[saleRef]) return
    try {
      const rows = await engine.dispatchAllocations(saleRef)
      setAllocsBySale((m) => ({ ...m, [saleRef]: rows }))
    } catch {
      // no signal: the invoice opens without its batch detail
    }
  }

  function refreshAfterDelete() {
    setExpanded(null)
    setAllocsBySale({})
    Promise.all([engine.debtors(), engine.salesTotals()])
      .then(([d, t]) => {
        setDebtors(d)
        setTotals(t)
      })
      .catch(setError)
    sales.reload()
    onPosted()
  }

  function closePayment() {
    setPayFor(null)
    setPayAmount('')
    setPayNote('')
  }

  async function submitPayment(e: React.FormEvent) {
    e.preventDefault()
    if (!payFor || !(Number(payAmount) > 0)) return
    const res = await paySafe.save((key) =>
      engine
        .recordCustomerPayment({
          customerName: payFor,
          amountPkr: Number(payAmount),
          occurredOn: payDate,
          note: payNote.trim() || undefined,
          idempotencyKey: key,
        })
        .then(() => true),
    )
    if (res === null) return
    closePayment()
    try {
      const [d, t] = await Promise.all([engine.debtors(), engine.salesTotals()])
      setDebtors(d)
      setTotals(t)
      sales.reload()
    } catch {
      // saved already; the lists refresh on the next visit
    }
    onPosted()
  }

  if (error) return <ErrorBanner error={error} />
  if (!debtors || !totals) return <Spinner />

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">Debtors &amp; Sales</h2>
        <p className="mt-1 text-slate-500">Who owes what, and exactly what every sale earned.</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Total receivable" tone={totalOutstanding > 0 ? 'amber' : 'emerald'} sub="Money customers still owe">
          PKR {(totalOutstanding / 100).toLocaleString()}
        </StatCard>
        <StatCard label="Revenue (all invoices)" tone="blue" sub={`${totals.invoices} invoice(s)`}>
          PKR {(totalRevenue / 100).toLocaleString()}
        </StatCard>
        <StatCard
          label="Gross profit (sales − salt cost)"
          tone="emerald"
          sub={marginBase > 0 ? `${((totalProfit / marginBase) * 100).toFixed(1)}% of sales — before expenses` : '—'}
        >
          PKR {(totalProfit / 100).toLocaleString()}
        </StatCard>
      </div>

      {!payFor && <SavedBanner safe={paySafe} />}

      {payFor && (
        <Card>
          <SectionTitle>Receive payment from {payFor}</SectionTitle>
          <form onSubmit={submitPayment} className="space-y-4">
            <fieldset disabled={paySafe.locked} className="space-y-4">
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <DateField label="Date received" value={payDate} onChange={setPayDate} />
              <Field label="Amount received (PKR)" hint={`Balance owed: PKR ${(payOwed / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`}>
                <input type="number" min="1" step="0.01" inputMode="decimal" value={payAmount} onChange={(e) => setPayAmount(e.target.value)} className={inputCls} required />
              </Field>
            </div>
            <Field label="Note (optional)">
              <input type="text" value={payNote} onChange={(e) => setPayNote(e.target.value)} placeholder="e.g. cash, against INV-00001" className={inputCls} />
            </Field>
            </fieldset>
            <SaveControls safe={paySafe} valid={Number(payAmount) > 0} label="Receive payment" onStartOver={closePayment} />
            {!paySafe.locked && (
              <button type="button" onClick={closePayment} className="min-h-11 w-full rounded-xl border border-slate-300 px-6 py-3 text-base font-semibold text-slate-600 hover:bg-slate-50">
                Cancel
              </button>
            )}
          </form>
        </Card>
      )}

      <Card>
        <SectionTitle>Who owes what</SectionTitle>
        {debtors.length === 0 ? (
          <EmptyState>
            No customers yet. Record your first sale from <strong>Record what happened → Sell Salt / Dispatch</strong> —
            credit sales appear here automatically.
          </EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                  <th className="px-3 py-2">Customer</th>
                  <th className="px-3 py-2 text-right">Invoiced</th>
                  <th className="px-3 py-2 text-right">Paid</th>
                  <th className="px-3 py-2 text-right">Owes</th>
                  <th className="px-3 py-2 text-right">Last sale</th>
                  <th className="px-3 py-2"></th>
                </tr>
              </thead>
              <tbody>
                {debtors.map((d) => (
                  <tr key={d.party_id} className="border-b border-slate-100 last:border-0">
                    <td className="px-3 py-2.5">
                      <div className="font-semibold text-slate-800">{d.customer_name}</div>
                      {d.phone && <div className="text-xs text-slate-500">{d.phone}</div>}
                    </td>
                    <td className="px-3 py-2.5 text-right font-mono tabular-nums">PKR {(d.total_invoiced_paisa / 100).toLocaleString()}</td>
                    <td className="px-3 py-2.5 text-right font-mono tabular-nums text-emerald-700">PKR {(d.total_paid_paisa / 100).toLocaleString()}</td>
                    <td className={`px-3 py-2.5 text-right font-mono font-bold tabular-nums ${d.outstanding_paisa > 0 ? 'text-amber-700' : 'text-slate-500'}`}>
                      PKR {(d.outstanding_paisa / 100).toLocaleString()}
                    </td>
                    <td className="px-3 py-2.5 text-right text-xs text-slate-500">{d.last_sale_on ?? '—'}</td>
                    <td className="px-3 py-2.5 text-right">
                      {d.outstanding_paisa > 0 && (
                        <button
                          disabled={paySafe.locked}
                          onClick={() => {
                            setPayFor(d.customer_name)
                            setPayOwed(d.outstanding_paisa)
                            setPayAmount('')
                          }}
                          className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-emerald-50 px-3 text-sm font-bold text-emerald-700 hover:bg-emerald-100"
                        >
                          <HandCoins className="h-3.5 w-3.5" /> Receive
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card>
        <SectionTitle>Invoices</SectionTitle>
        {sales.error != null && <ErrorBanner error={sales.error} />}
        {!sales.rows ? (
          <Spinner />
        ) : sales.rows.length === 0 ? (
          <EmptyState>No invoices yet — record your first sale from the Record hub.</EmptyState>
        ) : (
          <div className="space-y-3">
            {sales.rows.map((s) => {
              const isOpen = expanded === s.sale_ref
              const saleAllocs = allocsBySale[s.sale_ref] ?? []
              return (
                <div key={s.sale_ref} className="rounded-xl border border-slate-200">
                  <div className="flex items-start">
                  <button
                    onClick={() => toggleInvoice(s.sale_ref)}
                    className="flex min-w-0 flex-1 flex-wrap items-center justify-between gap-3 px-4 py-3 text-left hover:bg-slate-50"
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm font-bold text-slate-800">{s.sale_ref}</span>
                        <Badge tone={s.status === 'dispatched' ? 'emerald' : 'blue'}>{s.status}</Badge>
                        {s.currency !== 'PKR' && <Badge tone="indigo">{s.currency}</Badge>}
                      </div>
                      <div className="mt-0.5 text-sm text-slate-500">
                        {s.customer_name} · {s.occurred_on} · {gramsToKg(s.invoiced_grams)} kg invoiced ·{' '}
                        {s.dispatched_grams >= s.invoiced_grams ? 'fully dispatched' : `${gramsToKg(s.dispatched_grams)} kg dispatched`}
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="font-mono font-bold tabular-nums text-slate-800">PKR {(s.total_revenue_paisa / 100).toLocaleString()}</div>
                      <div className="text-sm text-slate-500">
                        {s.cogs_paisa > 0 ? (
                          <>
                            COGS PKR {(s.cogs_paisa / 100).toLocaleString()} ·{' '}
                            <span className="font-semibold text-emerald-700">GP PKR {(s.gross_profit_paisa / 100).toLocaleString()} ({s.gross_margin_pct.toFixed(1)}%)</span>
                          </>
                        ) : s.dispatched_grams > 0 ? (
                          'awaiting cost detail'
                        ) : (
                          'not dispatched yet'
                        )}
                      </div>
                    </div>
                  </button>
                  <div className="p-2">
                    <EntryMenu entryRef={s.sale_ref} onChanged={refreshAfterDelete} />
                  </div>
                  </div>
                  {isOpen && (
                    <div className="border-t border-slate-100 bg-slate-50 px-4 py-3 text-sm">
                      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                        <div>
                          <div className="text-xs uppercase text-slate-500">Cash received</div>
                          <div className="font-mono tabular-nums">PKR {(s.cash_received_paisa / 100).toLocaleString()}</div>
                        </div>
                        <div>
                          <div className="text-xs uppercase text-slate-500">Advance applied</div>
                          <div className="font-mono tabular-nums">PKR {(s.advance_applied_paisa / 100).toLocaleString()}</div>
                        </div>
                        <div>
                          <div className="text-xs uppercase text-slate-500">Receivable</div>
                          <div className="font-mono tabular-nums">PKR {(s.ar_paisa / 100).toLocaleString()}</div>
                        </div>
                        <div>
                          <div className="text-xs uppercase text-slate-500">Revenue</div>
                          <div className="font-mono tabular-nums">PKR {(s.total_revenue_paisa / 100).toLocaleString()}</div>
                        </div>
                      </div>
                      {saleAllocs.length > 0 && (
                        <div className="mt-3">
                          <div className="mb-1 text-xs font-bold uppercase tracking-wide text-slate-500">Batches consumed (exact COGS)</div>
                          <ul className="space-y-1">
                            {saleAllocs.map((a, i) => (
                              <li key={i} className="flex flex-wrap items-center justify-between gap-2">
                                <span>
                                  {a.batch_code} · {gramsToKg(a.qty_grams)} kg @ PKR {(a.unit_cost_paisa_per_kg / 100).toFixed(2)}/kg ·{' '}
                                  {a.allocation_mode === 'fifo' ? (
                                    <Badge tone="blue">FIFO</Badge>
                                  ) : (
                                    <>
                                      <Badge tone="amber">manual</Badge>{' '}
                                      <span className="text-xs text-slate-500">“{a.override_reason}”</span>
                                    </>
                                  )}
                                </span>
                                <span className="font-mono tabular-nums">PKR {(a.cogs_paisa / 100).toLocaleString()}</span>
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
        <ShowMore paged={sales} />
      </Card>
    </div>
  )
}
