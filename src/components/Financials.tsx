import { Fragment, useEffect, useState } from 'react'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { engine } from '../lib/engine'
import type { AccountBalance, AccountLineRow } from '../lib/types'
import { Card, ErrorBanner, Money, SectionTitle, Spinner, StatCard } from './ui'

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
  const [linesByCode, setLinesByCode] = useState<Record<string, AccountLineRow[]>>({})
  const [loadingCode, setLoadingCode] = useState<string | null>(null)

  useEffect(() => {
    engine
      .accountBalances()
      .then(setBalances)
      .catch(setError)
  }, [])

  async function toggle(code: string) {
    if (openCode === code) {
      setOpenCode(null)
      return
    }
    setOpenCode(code)
    if (!linesByCode[code]) {
      setLoadingCode(code)
      try {
        const rows = await engine.accountLines(code)
        setLinesByCode((m) => ({ ...m, [code]: rows }))
      } catch {
        setLinesByCode((m) => ({ ...m, [code]: [] }))
      } finally {
        setLoadingCode(null)
      }
    }
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

  const openLines = openCode ? linesByCode[openCode] : undefined
  const openDr = (openLines ?? []).reduce((s, l) => s + l.debit_paisa, 0)
  const openCr = (openLines ?? []).reduce((s, l) => s + l.credit_paisa, 0)

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
                        <td className="py-2 font-mono text-xs text-slate-500">
                          <span className="inline-flex items-center gap-1">
                            {openCode === b.code ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                            {b.code}
                          </span>
                        </td>
                        <td className="py-2">{b.name}</td>
                        <td className="py-2 text-right">
                          <Money paisa={b.type === 'liability' || b.type === 'equity' || b.type === 'income' ? -b.balance_paisa : b.balance_paisa} />
                        </td>
                      </tr>
                      {openCode === b.code && (
                        <tr className="border-b border-slate-100 bg-slate-50/60">
                          <td colSpan={3} className="px-4 py-3">
                            {loadingCode === b.code ? (
                              <Spinner label="Loading every line…" />
                            ) : (openLines ?? []).length === 0 ? (
                              <div className="text-sm text-slate-500">No lines found for this account.</div>
                            ) : (
                              <div className="space-y-2">
                                <div className="flex flex-wrap items-center gap-x-6 gap-y-1 text-xs text-slate-600">
                                  <span>
                                    <strong>{(openLines ?? []).length}</strong> line(s)
                                  </span>
                                  <span>
                                    Total money out (Dr): <Money paisa={openDr} />
                                  </span>
                                  <span>
                                    Total money in (Cr): <Money paisa={openCr} />
                                  </span>
                                </div>
                                <div className="max-h-96 overflow-y-auto rounded-lg border border-slate-200 bg-white">
                                  <table className="w-full text-xs">
                                    <thead>
                                      <tr className="border-b border-slate-200 bg-slate-50 text-left uppercase tracking-wide text-slate-500">
                                        <th className="px-3 py-2">Date</th>
                                        <th className="px-3 py-2">Ref</th>
                                        <th className="px-3 py-2">Description</th>
                                        <th className="px-3 py-2 text-right">Money out (Dr)</th>
                                        <th className="px-3 py-2 text-right">Money in (Cr)</th>
                                      </tr>
                                    </thead>
                                    <tbody>
                                      {(openLines ?? []).map((l) => (
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
                                  </table>
                                </div>
                              </div>
                            )}
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
