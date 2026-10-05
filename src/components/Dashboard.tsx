import { Fragment, useEffect, useState } from 'react'
import { BookUser, HandCoins, PackageOpen, PlusCircle, RefreshCw, ShieldAlert, ShieldCheck } from 'lucide-react'
import { engine } from '../lib/engine'
import type { AccountBalance, DebtorRow, LedgerEntryRow, LedgerHealth, StockOnHand } from '../lib/types'
import { Card, ErrorBanner, Kg, Money, SectionTitle, ShowMore, Spinner, StatCard, usePaged } from './ui'
import { EntryMenu } from './EntryActions'
import { batchNames } from '../lib/batches'

/** Dashboard: every number read from database views. No client-side totals over long lists. */

type Snapshot = {
  cash: AccountBalance | undefined
  vehicle: AccountBalance | undefined
  unclassifiedPaisa: number
  /** 2000 Suppliers, as what we owe (credit side positive) */
  weOwePaisa: number
  debtors: DebtorRow[]
  inventoryTotalPaisa: number
  stock: StockOnHand[]
  health: LedgerHealth
}

export default function Dashboard({ go }: { go?: (tab: string) => void }) {
  const [snap, setSnap] = useState<Snapshot | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [busy, setBusy] = useState(false)
  const [expanded, setExpanded] = useState<number | null>(null)
  const [lines, setLines] = useState<Record<number, LedgerEntryRow[]>>({})
  const [batchName, setBatchName] = useState<Map<string, string>>(new Map())
  const events = usePaged((limit, offset) => engine.listEvents(limit, offset))

  async function load() {
    setBusy(true)
    setError(null)
    try {
      const [balances, stock, debtors, health, batches] = await Promise.all([
        engine.accountBalances(),
        engine.stockOnHand(),
        engine.debtors(),
        engine.ledgerHealth(),
        engine.batches(),
      ])
      setBatchName(batchNames(batches))
      const find = (code: string) => balances.find((b) => b.code === code)
      const inventoryTotalPaisa = balances
        .filter((b) => ['1200', '1210', '1220', '1230'].includes(b.code))
        .reduce((s, b) => s + b.balance_paisa, 0)
      // both are 'still to sort out': 1900 Suspense + 5950 Personal/Unclassified (review)
      const unclassifiedPaisa = (find('1900')?.balance_paisa ?? 0) + (find('5950')?.balance_paisa ?? 0)
      // balances are debit minus credit; what we owe suppliers is on the credit side
      const weOwePaisa = -(find('2000')?.balance_paisa ?? 0)
      setSnap({ cash: find('1000'), vehicle: find('1400'), unclassifiedPaisa, weOwePaisa, inventoryTotalPaisa, stock, debtors, health })
    } catch (e) {
      setError(e)
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  function refreshAfterDelete() {
    setExpanded(null)
    setLines({})
    load()
    events.reload()
  }

  async function toggle(id: number) {
    setExpanded(expanded === id ? null : id)
    if (lines[id]) return
    try {
      const m = await engine.eventLines([id])
      setLines((l) => ({ ...l, [id]: m.get(id) ?? [] }))
    } catch {
      // no signal: the row simply stays without its lines
    }
  }

  if (error)
    return (
      <div>
        <ErrorBanner error={error} />
        <button
          onClick={load}
          className="min-h-11 rounded-lg bg-slate-900 px-4 py-2 text-base font-medium text-white hover:bg-slate-700"
        >
          Retry
        </button>
      </div>
    )
  if (!snap) return <Spinner />

  const h = snap.health
  const balanced = h.total_debit_paisa === h.total_credit_paisa
  const stockTies = h.stock_mismatched_accounts === 0 && h.stock_ledger_paisa === h.stock_movements_paisa
  const cashNeverNegative = h.negative_cash_days === 0
  const allOk = balanced && stockTies && cashNeverNegative

  return (
    <div className="space-y-6">
      {go && (
        <div className="space-y-3">
          {/* the three things done every day: one big tap each */}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            {[
              { id: 'record-sale', label: 'Sell Salt', icon: PackageOpen, cls: 'bg-emerald-700 hover:bg-emerald-800' },
              { id: 'record-moneyout', label: 'Money Out', icon: BookUser, cls: 'bg-slate-800 hover:bg-slate-900' },
              { id: 'debtors', label: 'Receive payment', icon: HandCoins, cls: 'bg-blue-700 hover:bg-blue-800' },
            ].map((a) => (
              <button
                key={a.id}
                onClick={() => go(a.id)}
                className={`flex min-h-16 items-center justify-center gap-3 rounded-2xl px-5 py-4 text-xl font-bold text-white shadow-sm transition ${a.cls}`}
              >
                <a.icon className="h-7 w-7 shrink-0" />
                {a.label}
              </button>
            ))}
          </div>
          <button
            onClick={() => go('record')}
            className="flex min-h-11 w-full items-center justify-center gap-2 rounded-xl border-2 border-slate-300 bg-white px-4 py-2.5 text-base font-semibold text-slate-700 hover:bg-slate-50"
          >
            <PlusCircle className="h-5 w-5 shrink-0" />
            Other entries — investment, buy salt, crush salt
          </button>
        </div>
      )}

      {busy && (
        <div className="flex items-center gap-2 text-sm text-slate-500">
          <RefreshCw className="h-3 w-3 animate-spin" /> refreshing…
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Cash on Hand"
          sub={cashNeverNegative ? '✓ never below zero on any day' : `went below zero on ${h.negative_cash_days} day(s) — check back-dated entries`}
          tone={cashNeverNegative ? 'emerald' : 'rose'}
        >
          <Money paisa={snap.cash?.balance_paisa ?? 0} />
        </StatCard>
        <StatCard
          label="Inventory Value"
          sub={stockTies ? '✓ matches the batch stock records' : 'does NOT match the batch stock records'}
          tone={stockTies ? 'emerald' : 'rose'}
        >
          <Money paisa={snap.inventoryTotalPaisa} />
        </StatCard>
        <StatCard label="Vehicle (side asset)" sub="kept out of salt cost" tone="blue">
          <Money paisa={snap.vehicle?.balance_paisa ?? 0} />
        </StatCard>
        <StatCard
          label="Unclassified (to check with baba)"
          sub="Tap to open the lines and move them →"
          tone={snap.unclassifiedPaisa > 0 ? 'amber' : 'slate'}
          onClick={go && (() => go('unclassified'))}
        >
          <Money paisa={snap.unclassifiedPaisa} />
        </StatCard>
        <StatCard
          label="We owe / ہم نے دینا ہے"
          sub="Workers, diesel, bills — tap to see who and pay →"
          tone={snap.weOwePaisa > 0 ? 'amber' : 'slate'}
          onClick={go && (() => go('record-paysupplier'))}
        >
          <Money paisa={snap.weOwePaisa} />
        </StatCard>
      </div>

      <Card>
        <SectionTitle>Udhaar / Debtors — who owes what</SectionTitle>
        {snap.debtors.length === 0 ? (
          <div className="text-sm text-slate-500">No udhaar outstanding.</div>
        ) : (
          <>
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                  <th className="pb-2">Shop</th>
                  <th className="pb-2 text-right">Baqaya (PKR)</th>
                  <th className="pb-2 text-right">Last sale</th>
                </tr>
              </thead>
              <tbody>
                {snap.debtors.map((d) => (
                  <tr key={d.party_id} className="border-b border-slate-100">
                    <td className="py-2 font-medium">{d.customer_name}</td>
                    <td className="py-2 text-right">
                      <Money paisa={d.outstanding_paisa} />
                    </td>
                    <td className="py-2 text-right text-slate-600">{d.last_sale_on}</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
            {go && (
              <button
                onClick={() => go('debtors')}
                className="mt-3 min-h-11 rounded-lg bg-slate-900 px-4 py-2 text-base font-medium text-white hover:bg-slate-700"
              >
                Open Debtors &amp; Sales — collect payments
              </button>
            )}
          </>
        )}
      </Card>

      <Card>
        <SectionTitle>Stock on hand (from the batch stock records)</SectionTitle>
        {snap.stock.length === 0 ? (
          <div className="text-sm text-slate-500">No stock recorded yet.</div>
        ) : (
          <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                <th className="pb-2">Batch</th>
                <th className="pb-2">Product</th>
                <th className="pb-2">Location</th>
                <th className="pb-2 text-right">Quantity</th>
                <th className="pb-2 text-right">Value</th>
                <th className="pb-2 text-right">Cost / kg</th>
              </tr>
            </thead>
            <tbody>
              {snap.stock.filter((s) => s.qty_grams > 0).map((s) => (
                <tr key={`${s.batch_code}-${s.location_code}`} className="border-b border-slate-100">
                  <td className="py-2 font-medium">
                    {batchName.get(s.batch_code) ?? s.batch_code}
                    <div className="font-mono text-xs font-normal text-slate-500">{s.batch_code}</div>
                  </td>
                  <td className="py-2">{s.product_name}</td>
                  <td className="py-2">{s.location_name}</td>
                  <td className="py-2 text-right">
                    <Kg grams={s.qty_grams} />
                  </td>
                  <td className="py-2 text-right">
                    <Money paisa={s.value_paisa} />
                  </td>
                  <td className="py-2 text-right font-mono tabular-nums text-slate-600">
                    Rs {(s.value_paisa / 100 / (s.qty_grams / 1000)).toLocaleString('en-PK', { maximumFractionDigits: 2 })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table></div>
        )}
      </Card>

      <Card>
        <SectionTitle>Recent entries — tap one to see its exact ledger lines</SectionTitle>
        {events.error != null && <ErrorBanner error={events.error} />}
        {!events.rows ? (
          <Spinner />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                  <th className="pb-2">Date</th>
                  <th className="pb-2">Ref</th>
                  <th className="pb-2">Type</th>
                  <th className="pb-2">Description</th>
                  <th className="pb-2 text-right">Amount</th>
                  <th className="pb-2"><span className="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                {events.rows.map((e) => (
                  <Fragment key={e.id}>
                    <tr
                      onClick={() => toggle(e.id)}
                      className="cursor-pointer border-b border-slate-100 hover:bg-slate-50"
                    >
                      <td className="py-3 whitespace-nowrap text-slate-600">{e.occurred_on}</td>
                      <td className="py-3 font-mono text-xs">{e.event_ref}</td>
                      <td className="py-3">
                        <TypeBadge type={e.event_type} />
                      </td>
                      <td className="max-w-[28rem] truncate py-3" title={e.description}>
                        {e.description}
                      </td>
                      <td className="py-3 text-right font-mono tabular-nums">
                        {paisa(e.total_paisa)}
                      </td>
                      <td className="py-1 pl-2 text-right">
                        <EntryMenu entryRef={e.event_ref} onChanged={refreshAfterDelete} />
                      </td>
                    </tr>
                    {expanded === e.id && (
                      <tr className="border-b border-slate-100 bg-slate-50/60">
                        <td colSpan={6} className="px-4 py-3">
                          {!lines[e.id] ? (
                            <Spinner label="Loading lines…" />
                          ) : (
                            <div className="space-y-1">
                              {lines[e.id].map((l) => (
                                <div key={l.id} className="flex justify-between text-sm">
                                  <span className="font-mono">
                                    {l.account_code} {l.account_name}
                                  </span>
                                  <span className="font-mono tabular-nums">
                                    {l.debit_paisa > 0 ? `Dr ${paisa(l.debit_paisa)}` : `Cr ${paisa(l.credit_paisa)}`}
                                  </span>
                                </div>
                              ))}
                            </div>
                          )}
                        </td>
                      </tr>
                    )}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <ShowMore paged={events} />
      </Card>

      <Card>
        <div className="flex items-start gap-3">
          {allOk ? (
            <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />
          ) : (
            <ShieldAlert className="mt-0.5 h-5 w-5 shrink-0 text-rose-600" />
          )}
          <div className="space-y-1 text-sm text-slate-600">
            <div className="font-semibold text-slate-800">Checks the database runs on the whole ledger</div>
            <div>{balanced ? '✓' : '✗'} Every debit has an equal credit (debits = credits).</div>
            <div>{stockTies ? '✓' : '✗'} Stock value in the ledger equals the value of the batch stock records.</div>
            <div>
              {cashNeverNegative ? '✓' : '✗'} Cash never went below zero on any day
              {h.lowest_cash_paisa != null && <> (lowest: <Money paisa={h.lowest_cash_paisa} />)</>}.
            </div>
          </div>
        </div>
      </Card>
    </div>
  )
}

function TypeBadge({ type }: { type: string }) {
  const colors: Record<string, string> = {
    capital_injection: 'bg-emerald-100 text-emerald-700',
    expense: 'bg-slate-100 text-slate-600',
    asset_purchase: 'bg-blue-100 text-blue-700',
    drawings: 'bg-rose-100 text-rose-700',
    purchase: 'bg-indigo-100 text-indigo-700',
    process_run: 'bg-amber-100 text-amber-700',
    other: 'bg-amber-100 text-amber-700',
    opening_inventory: 'bg-indigo-100 text-indigo-700',
  }
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${colors[type] ?? 'bg-slate-100 text-slate-600'}`}>
      {type.replace(/_/g, ' ')}
    </span>
  )
}

function paisa(p: number): string {
  return `PKR ${(p / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`
}
