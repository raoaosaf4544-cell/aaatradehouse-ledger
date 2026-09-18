import { Fragment, useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import type { AccountBalance } from '../lib/types'
import { Card, ErrorBanner, Money, SectionTitle, Spinner } from './ui'

const GROUP_ORDER: Array<AccountBalance['type']> = ['asset', 'liability', 'equity', 'income', 'expense']

const GROUP_LABEL: Record<string, string> = {
  asset: 'Assets',
  liability: 'Liabilities',
  equity: 'Equity',
  income: 'Income',
  expense: 'Expenses',
}

export default function Financials() {
  const [balances, setBalances] = useState<AccountBalance[] | null>(null)
  const [error, setError] = useState<unknown>(null)

  useEffect(() => {
    engine
      .accountBalances()
      .then(setBalances)
      .catch(setError)
  }, [])

  if (error) return <ErrorBanner error={error} />
  if (!balances) return <Spinner />

  const groups = GROUP_ORDER.map((type) => ({
    type,
    rows: balances.filter((b) => b.type === type && b.balance_paisa !== 0),
  })).filter((g) => g.rows.length > 0)

  return (
    <div className="space-y-6">
      <Card>
        <SectionTitle>Trial balance — every account, straight from the ledger</SectionTitle>
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
                    <tr key={b.code} className="border-b border-slate-100">
                      <td className="py-2 font-mono text-xs text-slate-500">{b.code}</td>
                      <td className="py-2">{b.name}</td>
                      <td className="py-2 text-right">
                        <Money paisa={b.type === 'liability' || b.type === 'equity' || b.type === 'income' ? -b.balance_paisa : b.balance_paisa} />
                      </td>
                    </tr>
                  ))}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-3 text-xs text-slate-500">
          Credit balances (liabilities, equity, income) are shown as positive numbers. Every value
          here is SUM(debits − credits) computed by the database.
        </p>
      </Card>
    </div>
  )
}
