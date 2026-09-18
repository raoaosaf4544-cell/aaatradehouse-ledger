import { useState } from 'react'
import { engine } from '../lib/engine'
import {
  Card,
  Field,
  inputCls,
  ErrorBanner,
  JournalPreview,
  SectionTitle,
  SuccessBanner,
  accountName,
} from './ui'

/**
 * Capital Injection: Dr Cash 1000 / Cr Owner Capital 3000.
 * Updates liquid cash and capital immediately — verified by the engine.
 */
export default function CapitalInjectionForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [amount, setAmount] = useState('')
  const [depositor, setDepositor] = useState('')
  const [note, setNote] = useState('')
  const [error, setError] = useState<unknown>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = amountPaisa > 0 && depositor.trim().length > 0

  const lines = [
    { account: '1000', debit: amountPaisa },
    { account: '3000', credit: amountPaisa },
  ]

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setSuccess(null)
    if (!valid) return
    setBusy(true)
    try {
      const ref = await engine.postEvent({
        eventType: 'capital_injection',
        occurredOn: date,
        description: `Capital injection by ${depositor.trim()}${note.trim() ? ` — ${note.trim()}` : ''}`,
        lines,
        partyType: 'owner',
        partyName: depositor.trim(),
      })
      setSuccess(`Recorded as ${ref}. Cash and capital both increased immediately.`)
      setAmount('')
      setNote('')
      onPosted()
    } catch (err) {
      setError(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <SectionTitle>Add investment money</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="Date">
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className={inputCls} required />
          </Field>
          <Field label="Amount (PKR)">
            <input
              type="number"
              min="1"
              step="0.01"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="e.g. 500000"
              className={inputCls}
              required
            />
          </Field>
        </div>

        <Field label="Who put the money in?" hint="You or your father — kept for the record.">
          <input
            type="text"
            value={depositor}
            onChange={(e) => setDepositor(e.target.value)}
            placeholder="e.g. Ahmed Osaaf"
            className={inputCls}
            required
          />
        </Field>

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. second tranche for October stock" className={inputCls} />
        </Field>

        <JournalPreview
          lines={lines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account),
            debit: l.debit,
            credit: l.credit,
          }))}
        />

        {error && <ErrorBanner error={error} />}
        {success && <SuccessBanner>{success}</SuccessBanner>}

        <button
          type="submit"
          disabled={!valid || busy}
          className="w-full rounded-xl bg-emerald-600 px-4 py-3.5 text-lg font-bold text-white shadow-sm transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {busy ? 'Recording…' : 'Record it'}
        </button>
      </form>
    </Card>
  )
}
