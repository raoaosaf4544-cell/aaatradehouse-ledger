import { useState } from 'react'
import { engine } from '../lib/engine'
import { Card, DateField, Field, inputCls, JournalPreview, SectionTitle, accountName, todayPK } from './ui'
import { SaveControls, useSafeSave } from './SafeSave'

type Category = { id: string; label: string; account: string; eventType: string; asset?: boolean }

const CATEGORIES: Category[] = [
  { id: 'labour', label: 'Labour', account: '5000', eventType: 'expense' },
  { id: 'utilities', label: 'Utilities', account: '5100', eventType: 'expense' },
  { id: 'fuel', label: 'Fuel', account: '5300', eventType: 'expense' },
  { id: 'site', label: 'Site Meals & Welfare', account: '5500', eventType: 'expense' },
  { id: 'travel', label: 'Travel', account: '5600', eventType: 'expense' },
  { id: 'repairs', label: 'Repairs & Maintenance', account: '5700', eventType: 'expense' },
  { id: 'admin', label: 'Admin & Office', account: '5800', eventType: 'expense' },
  { id: 'other_biz', label: 'Other Business Expense', account: '5900', eventType: 'expense' },
  { id: 'bike', label: 'Vehicle (1400)', account: '1400', eventType: 'asset_purchase', asset: true },
  { id: 'goats', label: 'Livestock (1450)', account: '1450', eventType: 'asset_purchase', asset: true },
  { id: 'equipment', label: 'Equipment / other assets (1500)', account: '1500', eventType: 'asset_purchase', asset: true },
  { id: 'drawings', label: 'Owner Drawings (personal take-out)', account: '3100', eventType: 'drawings' },
  { id: 'personal', label: 'Personal / Unclear — Suspense for review', account: '1900', eventType: 'expense' },
]

export default function MoneyOutForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [categoryId, setCategoryId] = useState('') // no default: the type must be picked every time
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const safe = useSafeSave()

  const category = CATEGORIES.find((c) => c.id === categoryId)
  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = !!category && amountPaisa > 0 && description.trim().length > 0
  // hint only: crushing costs belong on the Crush screen, where they go into the salt cost
  const looksLikeCrushing = (categoryId === 'labour' || categoryId === 'utilities') && /crush|پسائی|مشین|machine/i.test(description)

  const lines = category
    ? [
        { account: category.account, debit: amountPaisa },
        { account: '1000', credit: amountPaisa },
      ]
    : []

  function clear() {
    setCategoryId('')
    setAmount('')
    setDescription('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid || !category) return
    const ref = await safe.save((key) =>
      engine.postEvent({
        eventType: category.eventType,
        occurredOn: date,
        description: description.trim(),
        lines,
        partyType: 'other',
        idempotencyKey: key,
      }),
    )
    if (ref === null) return
    clear()
    onPosted()
  }

  return (
    <Card>
      <SectionTitle>Record money out</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date paid" value={date} onChange={setDate} />
          <Field label="What kind of spending?">
            <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className={inputCls} required>
              <option value="" disabled>Pick one…</option>
              <optgroup label="Spending">
                {CATEGORIES.filter((c) => !c.asset).map((c) => (
                  <option key={c.id} value={c.id}>{c.label}</option>
                ))}
              </optgroup>
              <optgroup label="Something bought that keeps its value (asset)">
                {CATEGORIES.filter((c) => c.asset).map((c) => (
                  <option key={c.id} value={c.id}>{c.label}</option>
                ))}
              </optgroup>
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

        {looksLikeCrushing && (
          <p role="note" className="rounded-xl bg-amber-50 px-4 py-3 text-base text-amber-900">
            If this is for crushing, enter it on the <strong>Crush</strong> screen instead so it goes into the salt cost.
          </p>
        )}

        <JournalPreview
          lines={lines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account),
            debit: l.debit || undefined,
            credit: l.credit || undefined,
          }))}
        />

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record it" onStartOver={clear} className="bg-slate-900 hover:bg-slate-700" />
      </form>
    </Card>
  )
}
