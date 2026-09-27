import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import { useOffline } from '../lib/offline'
import type { ReviewItem } from '../lib/types'
import { Card, EmptyState, ErrorBanner, inputCls, SectionTitle, Spinner } from './ui'

export default function ReviewQueue() {
  const offline = useOffline() // resolving writes to the books: needs signal
  const [items, setItems] = useState<ReviewItem[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [notes, setNotes] = useState<Record<number, string>>({})

  async function load() {
    try {
      setItems(await engine.openReviewItems())
    } catch (e) {
      setError(e)
    }
  }

  useEffect(() => {
    load()
  }, [])

  async function decide(item: ReviewItem, dismissed: boolean) {
    setError(null)
    try {
      await engine.resolveReviewItem(item.id, notes[item.id] ?? '', dismissed)
      await load()
    } catch (e) {
      setError(e)
    }
  }

  return (
    <div className="space-y-4">
      {error != null && <ErrorBanner error={error} kind={items ? 'save' : 'load'} />}
      <Card>
        <SectionTitle>
          Unclear lines imported from your Excel ledger — nothing was auto-classified
        </SectionTitle>
        {!items ? (
          <Spinner />
        ) : items.length === 0 ? (
          <EmptyState>Nothing waiting for review. All clear.</EmptyState>
        ) : (
          <div className="space-y-3">
            {items.map((item) => (
              <div
                key={item.id}
                className="rounded-xl border border-amber-200 bg-amber-50/50 p-4"
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="font-medium text-slate-800">{item.title}</div>
                  <div className="text-xs text-slate-500">
                    {String(item.detail?.date ?? '')} · {String(item.detail?.category ?? '')} ·{' '}
                    <span className="font-mono">
                      {String(item.detail?.amount_display ?? '?')}
                    </span>{' '}
                    · {String(item.detail?.side ?? '')}
                  </div>
                </div>
                <div className="mt-1 text-sm text-slate-600">
                  “{String(item.detail?.description ?? '')}”
                </div>
                <div className="mt-1 text-xs text-slate-500">
                  Provisionally posted to {String(item.detail?.provisional_account ?? 'Suspense')} —
                  the amount is in the books but not classified.
                </div>
                <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                  <input
                    type="text"
                    value={notes[item.id] ?? ''}
                    onChange={(e) => setNotes({ ...notes, [item.id]: e.target.value })}
                    placeholder="Decision note (required) — e.g. 'personal, treat as drawings'"
                    className={`${inputCls} flex-1`}
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={() => decide(item, false)}
                      disabled={offline || !(notes[item.id] ?? '').trim()}
                      className="min-h-11 rounded-lg bg-slate-900 px-4 text-base font-semibold text-white hover:bg-slate-700 disabled:bg-slate-300"
                    >
                      Mark resolved
                    </button>
                    <button
                      onClick={() => decide(item, true)}
                      disabled={offline || !(notes[item.id] ?? '').trim()}
                      className="min-h-11 rounded-lg border-2 border-slate-300 px-4 text-base font-semibold text-slate-700 hover:bg-slate-100 disabled:text-slate-300"
                    >
                      Dismiss
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  )
}
