import { useState } from 'react'
import { engine } from '../lib/engine'
import {
  Card,
  ErrorBanner,
  Field,
  inputCls,
  JournalPreview,
  SectionTitle,
  SuccessBanner,
  accountName,
} from './ui'

type Category = { id: string; label: string; account: string; eventType: string }

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
  { id: 'drawings', label: 'Owner Drawings (personal take-out)', account: '3100', eventType: 'drawings' },
  { id: 'personal', label: 'Personal / Unclear — Suspense for review', account: '1900', eventType: 'expense' },
]

export default function MoneyOutForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [categoryId, setCategoryId] = useState(CATEGORIES[0].id)
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [error, setError] = useState<unknown>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const category = CATEGORIES.find((c) => c.id === categoryId) ?? CATEGORIES[0]
  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = amountPaisa > 0 && description.trim().length > 0

  const lines = [
    { account: category.account, debit: amountPaisa },
    { account: '1000', credit: amountPaisa },
  ]

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
        lines,
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
      <form onSubmit={submit} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="Date">
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className={inputCls} required />
          </Field>
          <Field label="What kind of spending?">
            <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className={inputCls}>
              {CATEGORIES.map((c) => (
                <option key={c.id} value={c.id}>{c.label}</option>
              ))}
            </select>
          </Field>
        </div>

        <Field label="Amount (PKR)">
          <input
            type="number"
            min="1"
            step="0.01"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className={inputCls}
            required
          />
        </Field>

        <Field label="What was it for?" hint="Write it the way you'd say it — the engine records it word for word.">
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="e.g. Qasim weekly wages, bill house…"
            className={inputCls}
            required
          />
        </Field>

        <JournalPreview
          lines={lines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account),
            debit: l.debit || undefined,
            credit: l.credit || undefined,
          }))}
        />

        {error && <ErrorBanner error={error} />}
        {success && <SuccessBanner>{success}</SuccessBanner>}

        <button
          type="submit"
          disabled={!valid || busy}
          className="w-full rounded-xl bg-slate-900 px-4 py-3.5 text-lg font-bold text-white shadow-sm transition hover:bg-slate-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {busy ? 'Recording…' : 'Record it'}
        </button>
      </form>
    </Card>
  )
}
