import { useState } from 'react'
import { engine } from '../lib/engine'
import { Card, DateField, Field, inputCls, todayPK, JournalPreview, SectionTitle, accountName } from './ui'
import { SaveControls, useSafeSave } from './SafeSave'

/**
 * Capital Injection: Dr Cash 1000 / Cr Owner Capital 3000.
 * Updates liquid cash and capital immediately — verified by the engine.
 */
export default function CapitalInjectionForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [amount, setAmount] = useState('')
  const [depositor, setDepositor] = useState('')
  const [note, setNote] = useState('')
  const safe = useSafeSave()

  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = amountPaisa > 0 && depositor.trim().length > 0

  const lines = [
    { account: '1000', debit: amountPaisa },
    { account: '3000', credit: amountPaisa },
  ]

  function clear() {
    setAmount('')
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const ref = await safe.save((key) =>
      engine.postEvent({
        eventType: 'capital_injection',
        occurredOn: date,
        description: `Capital injection by ${depositor.trim()}${note.trim() ? ` — ${note.trim()}` : ''}`,
        lines,
        partyType: 'owner',
        partyName: depositor.trim(),
        idempotencyKey: key,
      }),
    )
    if (ref === null) return
    clear()
    onPosted()
  }

  return (
    <Card>
      <SectionTitle>Add investment money</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date received" value={date} onChange={setDate} />
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

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record it" onStartOver={clear} />
      </form>
    </Card>
  )
}
