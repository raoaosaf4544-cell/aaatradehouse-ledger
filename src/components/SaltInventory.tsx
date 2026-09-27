import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import type { BatchRow } from '../lib/types'
import { Badge, Card, EmptyState, ErrorBanner, Kg, Money, SectionTitle, Spinner, StatCard } from './ui'

export default function SaltInventory() {
  const [batches, setBatches] = useState<BatchRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)

  useEffect(() => {
    engine
      .batches()
      .then(setBatches)
      .catch(setError)
  }, [])

  if (error) return <ErrorBanner error={error} />
  if (!batches) return <Spinner />

  const totalKg = batches.reduce((s, b) => s + b.onhand_grams, 0)
  const totalValue = batches.reduce((s, b) => s + b.value_paisa, 0)
  const totalWastageKg = batches.reduce((s, b) => s + b.wastage_grams, 0)
  const liveBatches = batches.filter((b) => b.onhand_grams > 0)

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Total on hand" tone="blue">
          <Kg grams={totalKg} />
        </StatCard>
        <StatCard label="Inventory value">
          <Money paisa={totalValue} />
        </StatCard>
        <StatCard label="Batches with stock">
          {liveBatches.length}
        </StatCard>
        <StatCard
          label="Wastage to date"
          tone={totalWastageKg > 0 ? 'amber' : 'slate'}
          sub={`across all batches — PKR ${(
            batches.reduce((s, b) => s + b.wastage_value_paisa, 0) / 100
          ).toLocaleString()} booked to process loss`}
        >
          <Kg grams={totalWastageKg} />
        </StatCard>
      </div>

      <Card>
        <SectionTitle>Batches — computed from the append-only movement ledger</SectionTitle>
        {batches.length === 0 ? (
          <EmptyState>No batches yet. Record a purchase to create the first batch.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                  <th className="pb-2">Batch</th>
                  <th className="pb-2">Product</th>
                  <th className="pb-2">Location</th>
                  <th className="pb-2 text-right">On hand</th>
                  <th className="pb-2 text-right">Value</th>
                  <th className="pb-2 text-right">Cost / kg</th>
                  <th className="pb-2 text-right">Wastage</th>
                  <th className="pb-2">Status</th>
                </tr>
              </thead>
              <tbody>
                {batches.map((b) => (
                  <tr
                    key={b.batch_code}
                    className={`border-b border-slate-100 ${b.onhand_grams === 0 ? 'text-slate-500' : ''}`}
                  >
                    <td className="py-2 font-medium">{b.batch_code}</td>
                    <td className="py-2">{b.product_name}</td>
                    <td className="py-2">{b.location_name}</td>
                    <td className="py-2 text-right">
                      <Kg grams={b.onhand_grams} />
                    </td>
                    <td className="py-2 text-right">
                      <Money paisa={b.value_paisa} />
                    </td>
                    <td className="py-2 text-right font-mono tabular-nums text-slate-600">
                      {b.onhand_grams > 0
                        ? `PKR ${((b.value_paisa / b.onhand_grams) * 1000 / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`
                        : '—'}
                    </td>
                    <td className="py-2 text-right text-amber-700">
                      {b.wastage_grams > 0 ? <Kg grams={b.wastage_grams} /> : '—'}
                    </td>
                    <td className="py-2">
                      {b.onhand_grams === 0 ? (
                        <Badge tone="slate">Consumed</Badge>
                      ) : (
                        <Badge tone="emerald">In stock</Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="mt-3 text-xs text-slate-500">
          Wastage rows record the measured loss and its value; on-hand quantity is computed strictly from
          in − out movements, so a fully consumed batch closes to exactly zero kg. The database rejects any
          run that would make a batch go negative or fail mass conservation.
        </p>
      </Card>
    </div>
  )
}
