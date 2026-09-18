import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import type { StockOnHand } from '../lib/types'
import { Card, EmptyState, ErrorBanner, Kg, Money, SectionTitle, Spinner, StatCard } from './ui'

export default function SaltInventory() {
  const [stock, setStock] = useState<StockOnHand[] | null>(null)
  const [error, setError] = useState<unknown>(null)

  useEffect(() => {
    engine
      .stockOnHand()
      .then(setStock)
      .catch(setError)
  }, [])

  if (error) return <ErrorBanner error={error} />
  if (!stock) return <Spinner />

  const totalKg = stock.reduce((s, r) => s + r.qty_grams, 0)
  const totalValue = stock.reduce((s, r) => s + r.value_paisa, 0)

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Total on hand" tone="blue">
          <Kg grams={totalKg} />
        </StatCard>
        <StatCard label="Inventory value">
          <Money paisa={totalValue} />
        </StatCard>
        <StatCard label="Batches in stock">
          {new Set(stock.map((s) => s.batch_code)).size}
        </StatCard>
      </div>

      <Card>
        <SectionTitle>Stock by batch, product and location — SUM of append-only movements</SectionTitle>
        {stock.length === 0 ? (
          <EmptyState>No stock recorded yet. Purchases and processing runs will appear here.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
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
                {stock.map((s) => (
                  <tr key={`${s.batch_code}-${s.location_code}`} className="border-b border-slate-100">
                    <td className="py-2 font-medium">{s.batch_code}</td>
                    <td className="py-2">{s.product_name}</td>
                    <td className="py-2">{s.location_name}</td>
                    <td className="py-2 text-right">
                      <Kg grams={s.qty_grams} />
                    </td>
                    <td className="py-2 text-right">
                      <Money paisa={s.value_paisa} />
                    </td>
                    <td className="py-2 text-right font-mono tabular-nums text-slate-600">
                      {s.qty_grams > 0
                        ? `PKR ${((s.value_paisa / s.qty_grams) * 1000 / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`
                        : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="mt-3 text-xs text-slate-500">
          Purchases add stock, processing consumes input and creates output batches with their own
          cost, sales remove stock at cost. The database rejects any movement that would make a
          batch go negative.
        </p>
      </Card>
    </div>
  )
}
