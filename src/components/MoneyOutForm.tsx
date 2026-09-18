import { useMemo, useState } from 'react'
import { engine } from '../lib/engine'
import { Card, ErrorBanner, Money, SectionTitle } from './ui'

/** Simple posting form (Phase 2 scope: cash outflows). The engine enforces every rule. */

type Category = {
  id: string
  label: string
  account: string
  eventType: string
}

const CATEGORIES: Category[] = [
  { id: 'labour', label: 'Labour', account: '5000', eventType: 'expense' },
  { id: 'utilities', label: 'Utilities', account: '5100', eventType: 'expense' },
  { id: 'fuel', label: 'Fuel', account: '5300', eventType: 'expense' },
  { id: 'site', label: 'Site Meals & Welfare', account: '5500', eventType: 'expense' },
  { id: 'travel', label: 'Travel', account: '5600', eventType: 'expense' },
  { id: 'repairs', label: 'Repairs & Maintenance', account: '5700', eventType: 'expense' },
  { id: 'admin', label: 'Admin & Office', account: '5800', eventType: 'expense' },
  { id: 'other_biz', label: 'Other Business Expense', account: '5900', eventType: 'expense' },
  { id: 'bike', label: 'Vehicle Purchase / Improvement (asset)', account: '1400', eventType: 'asset_purchase' },
  { id: 'goats', label: 'Livestock (side asset)', account: '1450', eventType: 'asset_purchase' },
  { id: 'personal', label: 'Personal / Unclear — send to Suspense for review', account: '1900', eventType: 'expense' },
]

export default function MoneyOutForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [categoryId, setCategoryId] = useState(CATEGORIES[0].id)
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [error, setError] = useState<unknown>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const category = useMemo(
    () => CATEGORIES.find((c) => c.id === categoryId) ?? CATEGORIES[0],
    [categoryId],
  )
  const amountPaisa = useMemo(() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  }, [amount])

  const previewLines = [
    { account: category.account, debit: amountPaisa },
    { account: '1000', credit: amountPaisa },
  ]

  const valid = amountPaisa > 0 && description.trim().length > 0

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setSuccess(null)
    if (!valid) return
    setBusy(true)
    try {
      const ref = await engine.postEvent({
        eventType: category.eventType,
        occurredOn: date,
        description: description.trim(),
        lines: previewLines,
        partyType: 'other',
      })
      setSuccess(`Recorded as ${ref}. The engine verified the books stay balanced.`)
      setAmount('')
      setDescription('')
      onPosted()
    } catch (err) {
      setError(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <SectionTitle>Record money out</SectionTitle>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="mb-1 block font-medium text-slate-700">Date</span>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block font-medium text-slate-700">Category</span>
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
            >
              {CATEGORIES.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </select>
          </label>
        </div>

        <label className="block text-sm">
          <span className="mb-1 block font-medium text-slate-700">Amount (PKR)</span>
          <input
            type="number"
            min="1"
            step="0.01"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
            required
          />
        </label>

        <label className="block text-sm">
          <span className="mb-1 block font-medium text-slate-700">What was it for?</span>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="e.g. Qasim weekly wages, bill house…"
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
            required
          />
        </label>

        <div className="rounded-lg bg-slate-50 p-4 text-sm">
          <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
            What the engine will record
          </div>
          <div className="space-y-1 font-mono text-xs">
            <div className="flex justify-between">
              <span>Dr {category.account} — {category.label}</span>
              <span><Money paisa={amountPaisa} /></span>
            </div>
            <div className="flex justify-between">
              <span>Cr 1000 — Cash on Hand</span>
              <span><Money paisa={amountPaisa} /></span>
            </div>
          </div>
          <div className="mt-2 text-xs text-slate-500">
            The database rejects this posting if it would unbalance the books or make cash negative.
          </div>
        </div>

        {error && <ErrorBanner error={error} />}
        {success && (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
            {success}
          </div>
        )}

        <button
          type="submit"
          disabled={!valid || busy}
          className="w-full rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {busy ? 'Posting…' : 'Record it'}
        </button>
      </form>
    </Card>
  )
}
