import { Fragment, useEffect, useState } from 'react'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { engine } from '../lib/engine'
import type { AccountBalance, AccountTotals } from '../lib/types'
import PlantRateCheck from './PlantRateCheck'
import { Card, ErrorBanner, Money, SectionTitle, ShowMore, Spinner, StatCard, usePaged } from './ui'

const GROUP_ORDER: Array<AccountBalance['type']> = ['asset', 'liability', 'equity', 'income', 'expense']

const GROUP_LABEL: Record<string, string> = {
  asset: 'Assets',
  liability: 'Liabilities',
  equity: 'Equity',
  income: 'Income',
  expense: 'Expenses',
}

/**
 * Financials — full transparency surface.
 * Every trial-balance row expands to show the exact ledger lines behind it
 * (straight from the append-only ledger, nothing derived client-side).
 */
export default function Financials() {
  const [balances, setBalances] = useState<AccountBalance[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [openCode, setOpenCode] = useState<string | null>(null)

  useEffect(() => {
    engine
      .accountBalances()
      .then(setBalances)
      .catch(setError)
  }, [])

  function toggle(code: string) {
    setOpenCode(openCode === code ? null : code)
  }

  if (error) return <ErrorBanner error={error} />
  if (!balances) return <Spinner />

  const find = (code: string) => balances.find((b) => b.code === code)
  const capital = find('3000')
  const drawings = find('3100')
  const suspense = find('1900')
  const investedPaisa = (capital ? -capital.balance_paisa : 0) - (drawings?.balance_paisa ?? 0)

  const groups = GROUP_ORDER.map((type) => ({
    type,
    rows: balances.filter((b) => b.type === type && b.balance_paisa !== 0),
  })).filter((g) => g.rows.length > 0)


  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <StatCard
          label="Your investment till now"
          sub={
            capital
              ? `Owner capital put in: PKR ${(-capital.balance_paisa / 100).toLocaleString()}${
                  drawings && drawings.balance_paisa !== 0
                    ? `  −  taken back out (drawings): PKR ${(drawings.balance_paisa / 100).toLocaleString()}`
                    : ''
                } — see each injection under Equity → Owner Capital below.`
              : undefined
          }
          tone="emerald"
        >
          <Money paisa={investedPaisa} />
        </StatCard>
        <StatCard
          label="Unclassified (Suspense)"
          sub={
            suspense && suspense.balance_paisa !== 0
              ? 'Nothing is hidden — click the Suspense row below to see every single line inside this number.'
              : 'Fully classified.'
          }
          tone={suspense && suspense.balance_paisa !== 0 ? 'amber' : 'slate'}
        >
          <Money paisa={suspense?.balance_paisa ?? 0} />
        </StatCard>
      </div>

      <PlantRateCheck />

      <Card>
        <SectionTitle>Trial balance — click any account to see its exact ledger lines</SectionTitle>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                <th className="pb-2">Code</th>
                <th className="pb-2">Account</th>
                <th className="pb-2 text-right">Balance (Dr + / Cr −)</th>
              </tr>
            </thead>
            <tbody>
              {groups.map((g) => (
                <Fragment key={g.type}>
                  <tr className="bg-slate-50">
                    <td colSpan={3} className="px-2 py-1.5 text-xs font-semibold uppercase tracking-wide text-slate-500">
                      {GROUP_LABEL[g.type]}
                    </td>
                  </tr>
                  {g.rows.map((b) => (
                    <Fragment key={b.code}>
                      <tr
                        onClick={() => toggle(b.code)}
                        className={`cursor-pointer border-b border-slate-100 hover:bg-slate-50 ${openCode === b.code ? 'bg-blue-50/60' : ''}`}
                      >
                        <td className="py-3 font-mono text-xs text-slate-600">
                          <span className="inline-flex items-center gap-1">
                            {openCode === b.code ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                            {b.code}
                          </span>
                        </td>
                        <td className="py-3">{b.name}</td>
                        <td className="py-3 text-right">
                          <Money paisa={b.type === 'liability' || b.type === 'equity' || b.type === 'income' ? -b.balance_paisa : b.balance_paisa} />
                        </td>
                      </tr>
                      {openCode === b.code && (
                        <tr className="border-b border-slate-100 bg-slate-50/60">
                          <td colSpan={3} className="px-4 py-3">
                            <AccountDrill code={b.code} />
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  ))}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-3 text-xs text-slate-500">
          Credit balances (liabilities, equity, income) are shown as positive numbers. Every value
          here is SUM(debits − credits) computed by the database — clicking a row shows the raw,
          append-only lines behind it.
        </p>
      </Card>
    </div>
  )
}

/** Every ledger line of one account, a page at a time; totals come from the database. */
function AccountDrill({ code }: { code: string }) {
  const lines = usePaged((limit, offset) => engine.accountLines(code, limit, offset), code)
  const [totals, setTotals] = useState<AccountTotals | null>(null)
  useEffect(() => {
    engine.accountTotals(code).then(setTotals).catch(() => setTotals(null))
  }, [code])

  if (lines.error != null) return <ErrorBanner error={lines.error} />
  if (!lines.rows) return <Spinner label="Loading lines…" />
  if (lines.rows.length === 0) return <div className="text-sm text-slate-500">No lines found for this account.</div>
  return (
    <div className="space-y-2">
      {totals && (
        <div className="flex flex-wrap items-center gap-x-6 gap-y-1 text-sm text-slate-600">
          <span>
            <strong>{totals.line_count}</strong> line(s)
          </span>
          <span>
            Total debits: <Money paisa={totals.debit_paisa} />
          </span>
          <span>
            Total credits: <Money paisa={totals.credit_paisa} />
          </span>
        </div>
      )}
      <div className="max-h-96 overflow-y-auto rounded-lg border border-slate-200 bg-white">
        <div className="overflow-x-auto"><table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
              <th className="px-3 py-2">Date</th>
              <th className="px-3 py-2">Ref</th>
              <th className="px-3 py-2">Description</th>
              <th className="px-3 py-2 text-right">Debit</th>
              <th className="px-3 py-2 text-right">Credit</th>
            </tr>
          </thead>
          <tbody>
            {lines.rows.map((l) => (
              <tr key={`${l.event_id}-${l.entry_seq}`} className="border-b border-slate-100 last:border-0">
                <td className="whitespace-nowrap px-3 py-1.5 text-slate-600">{l.occurred_on}</td>
                <td className="px-3 py-1.5 font-mono">{l.event_ref}</td>
                <td className="px-3 py-1.5">{l.description}</td>
                <td className="px-3 py-1.5 text-right font-mono tabular-nums">
                  {l.debit_paisa > 0 ? <Money paisa={l.debit_paisa} /> : '—'}
                </td>
                <td className="px-3 py-1.5 text-right font-mono tabular-nums">
                  {l.credit_paisa > 0 ? <Money paisa={l.credit_paisa} /> : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div>
      </div>
      <ShowMore paged={lines} />
    </div>
  )
}
