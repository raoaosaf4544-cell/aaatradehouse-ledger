import { useEffect, useState } from 'react'
import { ArrowDownLeft, ArrowUpRight } from 'lucide-react'
import { engine } from '../lib/engine'
import type { AccountLineRow, EventRow } from '../lib/types'
import { Badge, Card, EmptyState, ErrorBanner, Money, SectionTitle, Spinner } from './ui'
import MoneyOutForm from './MoneyOutForm'
import { SaveControls, useSafeSave } from './SafeSave'

export default function CashLedger() {
  const [events, setEvents] = useState<EventRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [suspenseLines, setSuspenseLines] = useState<AccountLineRow[] | null>(null)
  const [suspenseOpen, setSuspenseOpen] = useState(false)

  async function load() {
    try {
      setEvents(await engine.listEvents(100))
      engine
        .accountLines('1900')
        .then(setSuspenseLines)
        .catch(() => setSuspenseLines([]))
    } catch (e) {
      setError(e)
    }
  }

  useEffect(() => {
    load()
  }, [])

  const suspenseDr = (suspenseLines ?? []).reduce((s, l) => s + l.debit_paisa, 0)
  const suspenseCr = (suspenseLines ?? []).reduce((s, l) => s + l.credit_paisa, 0)

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <MoneyOutForm onPosted={load} />
        <MoneyInCard onPosted={load} />
      </div>

      {error && <ErrorBanner error={error} />}

      <Card>
        <button
          onClick={() => setSuspenseOpen((o) => !o)}
          className="flex w-full items-center justify-between text-left"
        >
          <SectionTitle>Unclassified (Suspense) — every line the books could not label yet</SectionTitle>
          <Badge tone={suspenseDr - suspenseCr !== 0 ? 'amber' : 'slate'}>
            {suspenseLines === null ? 'loading…' : `${suspenseLines.length} lines`}
          </Badge>
        </button>
        <p className="mb-3 text-xs text-slate-500">
          These are real cash movements that were recorded but not yet given a proper name
          (money out total <Money paisa={suspenseDr} />, money in total <Money paisa={suspenseCr} />).
          They stay here until you tell us what each one was — nothing is hidden inside the total.
        </p>
        {suspenseOpen &&
          (!suspenseLines ? (
            <Spinner />
          ) : suspenseLines.length === 0 ? (
            <EmptyState>Nothing unclassified — every rupee is labelled.</EmptyState>
          ) : (
            <div className="max-h-96 overflow-y-auto rounded-lg border border-slate-200">
              <div className="overflow-x-auto"><table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-slate-200 bg-slate-50 text-left uppercase tracking-wide text-slate-500">
                    <th className="px-3 py-2">Date</th>
                    <th className="px-3 py-2">Ref</th>
                    <th className="px-3 py-2">What was written in the book</th>
                    <th className="px-3 py-2 text-right">Out</th>
                    <th className="px-3 py-2 text-right">In</th>
                  </tr>
                </thead>
                <tbody>
                  {suspenseLines.map((l) => (
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
                  <tr className="bg-slate-50 font-semibold">
                    <td colSpan={3} className="px-3 py-2">Total</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums"><Money paisa={suspenseDr} /></td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums"><Money paisa={suspenseCr} /></td>
                  </tr>
                </tbody>
              </table></div>
            </div>
          ))}
      </Card>

      <Card>
        <SectionTitle>Recent events</SectionTitle>
        {!events ? (
          <Spinner />
        ) : events.length === 0 ? (
          <EmptyState>No events recorded yet.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-500">
                  <th className="pb-2">Date</th>
                  <th className="pb-2">Ref</th>
                  <th className="pb-2">Description</th>
                  <th className="pb-2 text-right">Amount</th>
                </tr>
              </thead>
              <tbody>
                {events.slice(0, 50).map((e) => (
                  <tr key={e.id} className="border-b border-slate-100">
                    <td className="whitespace-nowrap py-2 text-slate-600">{e.occurred_on}</td>
                    <td className="py-2 font-mono text-xs">{e.event_ref}</td>
                    <td className="max-w-[24rem] truncate py-2" title={e.description}>
                      <span className="mr-2 inline-flex items-center">
                        {e.event_type === 'capital_injection' || e.event_type === 'other' ? (
                          <ArrowDownLeft className="h-3.5 w-3.5 text-emerald-600" />
                        ) : (
                          <ArrowUpRight className="h-3.5 w-3.5 text-rose-500" />
                        )}
                      </span>
                      {e.description}
                    </td>
                    <td className="py-2 text-right">
                      <Money paisa={e.total_paisa} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  )
}

function MoneyInCard({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [toSuspense, setToSuspense] = useState(false)
  const [suspenseNote, setSuspenseNote] = useState('')
  const safe = useSafeSave()

  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  // Suspense must never again fill up with unexplained lines: a note is required when ticked.
  const valid = amountPaisa > 0 && description.trim().length > 0 && (!toSuspense || suspenseNote.trim().length > 0)

  function clear() {
    setAmount('')
    setDescription('')
    setSuspenseNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const ref = await safe.save((key) =>
      engine.postEvent({
        eventType: 'other',
        occurredOn: date,
        description: toSuspense ? `${description.trim()} — for: ${suspenseNote.trim()}` : description.trim(),
        lines: toSuspense
          ? [
              { account: '1000', debit: amountPaisa },
              { account: '1900', credit: amountPaisa },
            ]
          : [
              { account: '1000', debit: amountPaisa },
              { account: '4900', credit: amountPaisa },
            ],
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
      <SectionTitle>Record money in</SectionTitle>
      <form onSubmit={submit} className="space-y-4">
        <fieldset disabled={safe.locked} className="space-y-4">
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
        </div>

        <label className="block text-sm">
          <span className="mb-1 block font-medium text-slate-700">Where did it come from?</span>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="e.g. roznamcha aamdani…"
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
            required
          />
        </label>

        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
          <input
            type="checkbox"
            checked={toSuspense}
            onChange={(e) => setToSuspense(e.target.checked)}
            className="h-6 w-6 shrink-0"
          />
          <span>
            Not sure what this is — send it to <strong>Suspense</strong> for review instead of
            booking it as income.
          </span>
        </label>
        {toSuspense && (
          <label className="block text-sm">
            <span className="mb-1 block font-medium text-slate-700">Write what this was for</span>
            <input
              type="text"
              value={suspenseNote}
              onChange={(e) => setSuspenseNote(e.target.value)}
              placeholder="e.g. money from Ali for last week's salt"
              className="w-full rounded-lg border border-amber-400 px-3 py-2 text-base focus:border-blue-500 focus:outline-none"
              required
            />
          </label>
        )}

        <div className="rounded-lg bg-slate-50 p-4 text-sm">
          <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
            What the engine will record
          </div>
          <div className="space-y-1 font-mono text-xs">
            <div className="flex justify-between">
              <span>Dr 1000 — Cash on Hand</span>
              <span><Money paisa={amountPaisa} /></span>
            </div>
            <div className="flex justify-between">
              <span>Cr {toSuspense ? '1900 — Suspense (review)' : '4900 — Other Income'}</span>
              <span><Money paisa={amountPaisa} /></span>
            </div>
          </div>
        </div>

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record it" onStartOver={clear} />
      </form>
    </Card>
  )
}
