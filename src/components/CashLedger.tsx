import { useEffect, useState } from 'react'
import { ArrowDownLeft, ArrowUpRight } from 'lucide-react'
import { engine } from '../lib/engine'
import type { EventRow } from '../lib/types'
import { Card, EmptyState, ErrorBanner, Money, SectionTitle, Spinner } from './ui'
import MoneyOutForm from './MoneyOutForm'

export default function CashLedger() {
  const [events, setEvents] = useState<EventRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [inError, setInError] = useState<unknown>(null)

  async function load() {
    try {
      setEvents(await engine.listEvents(100))
    } catch (e) {
      setError(e)
    }
  }

  useEffect(() => {
    load()
  }, [])

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <MoneyOutForm onPosted={load} />
        <MoneyInCard onPosted={load} onError={setInError} />
      </div>

      {error && <ErrorBanner error={error} />}

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

function MoneyInCard({
  onPosted,
  onError,
}: {
  onPosted: () => void
  onError: (e: unknown) => void
}) {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [toSuspense, setToSuspense] = useState(false)
  const [success, setSuccess] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = amountPaisa > 0 && description.trim().length > 0

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    setBusy(true)
    setSuccess(null)
    try {
      const ref = await engine.postEvent({
        eventType: 'other',
        occurredOn: date,
        description: description.trim(),
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
      })
      setSuccess(`Recorded as ${ref}.`)
      setAmount('')
      setDescription('')
      onPosted()
    } catch (err) {
      onError(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <SectionTitle>Record money in</SectionTitle>
      <form
        onSubmit={(e) => {
          onError(null)
          submit(e).catch(() => {})
        }}
        className="space-y-4"
      >
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

        <label className="flex items-start gap-2 text-sm">
          <input
            type="checkbox"
            checked={toSuspense}
            onChange={(e) => setToSuspense(e.target.checked)}
            className="mt-0.5"
          />
          <span>
            Not sure what this is — send it to <strong>Suspense</strong> for review instead of
            booking it as income.
          </span>
        </label>

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

        {success && (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
            {success}
          </div>
        )}

        <button
          type="submit"
          disabled={!valid || busy}
          className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {busy ? 'Posting…' : 'Record it'}
        </button>
      </form>
    </Card>
  )
}
