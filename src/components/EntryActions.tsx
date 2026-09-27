import { useEffect, useRef, useState } from 'react'
import { MoreHorizontal, Trash2 } from 'lucide-react'
import { engine } from '../lib/engine'
import { friendlyMessage } from '../lib/friendly'
import { useOffline } from '../lib/offline'
import type { DeletePreview } from '../lib/types'
import { Money, Spinner, dateInWords, inputCls } from './ui'

/**
 * "…" menu on an entry. Delete is two steps away on purpose: "…" → "Delete entry…" → a preview of exactly what
 * will change, a required reason and a Confirm button. The database does the delete in one transaction, keeps a
 * full copy (restorable from "Deleted entries") and cancels everything if any check of the books fails.
 */
export function EntryMenu({ entryRef, onChanged }: { entryRef: string; onChanged: () => void }) {
  const offline = useOffline()
  const [open, setOpen] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const wrap = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const close = (e: Event) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('pointerdown', close)
    return () => document.removeEventListener('pointerdown', close)
  }, [open])

  return (
    <div ref={wrap} className="relative inline-block" onClick={(e) => e.stopPropagation()}>
      <button
        type="button"
        aria-label={`More actions for ${entryRef}`}
        aria-expanded={open}
        disabled={offline}
        onClick={() => setOpen((o) => !o)}
        className="flex min-h-11 min-w-11 items-center justify-center rounded-lg border border-slate-300 bg-white text-slate-700 hover:bg-slate-100 disabled:opacity-50"
      >
        <MoreHorizontal className="h-5 w-5" />
      </button>
      {open && (
        <div className="absolute right-0 z-30 mt-1 w-56 rounded-xl border border-slate-200 bg-white p-1 shadow-lg">
          <button
            type="button"
            onClick={() => {
              setOpen(false)
              setDeleting(true)
            }}
            className="flex min-h-11 w-full items-center gap-2 rounded-lg px-3 text-left text-base font-semibold text-rose-800 hover:bg-rose-50"
          >
            <Trash2 className="h-5 w-5" /> Delete entry…
          </button>
        </div>
      )}
      {deleting && (
        <DeleteEntryDialog
          entryRef={entryRef}
          onClose={(deleted) => {
            setDeleting(false)
            // refresh the list only after the owner has read the result: the refresh removes this row (and this
            // dialog with it)
            if (deleted) onChanged()
          }}
        />
      )}
    </div>
  )
}

const kg = (n: number) => `${n.toLocaleString('en-PK', { maximumFractionDigits: 3 })} kg`
const signedKg = (n: number) => `${n > 0 ? '+' : n < 0 ? '−' : ''}${kg(Math.abs(n))}`

function Change({ label, before, after }: { label: string; before: React.ReactNode; after: React.ReactNode }) {
  return (
    <li className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5 py-1.5">
      <span className="text-slate-700">{label}</span>
      <span className="font-semibold text-slate-900">
        {before} → {after}
      </span>
    </li>
  )
}

function DeleteEntryDialog({ entryRef, onClose: close }: { entryRef: string; onClose: (deleted: boolean) => void }) {
  const [preview, setPreview] = useState<DeletePreview | null>(null)
  const [loadError, setLoadError] = useState<unknown>(null)
  const [reason, setReason] = useState('')
  const [phase, setPhase] = useState<'ready' | 'deleting' | 'unclear' | 'done'>('ready')
  const [error, setError] = useState<string | null>(null)
  const [deletedRefs, setDeletedRefs] = useState<string[]>([])
  const heading = useRef<HTMLHeadingElement>(null)
  const doneRef = useRef(false)
  const onClose = () => close(doneRef.current)
  const phaseRef = useRef(phase)
  phaseRef.current = phase

  useEffect(() => {
    heading.current?.focus()
    engine.deletePreview(entryRef).then(setPreview).catch(setLoadError)
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && phaseRef.current !== 'deleting' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entryRef])

  async function confirmDelete() {
    if (phase === 'deleting' || !reason.trim()) return
    setPhase('deleting')
    setError(null)
    try {
      const r = await engine.deleteEntry(entryRef, reason)
      setDeletedRefs(r.event_refs ?? [])
      doneRef.current = true
      setPhase('done')
    } catch (e) {
      const definite = (e as { definite?: boolean }).definite !== false
      setError(friendlyMessage(e, 'save'))
      // no answer: it may have gone through - trying again is safe (a repeat answers "already deleted")
      setPhase(definite ? 'ready' : 'unclear')
    }
  }

  const blockers = preview?.blockers ?? []
  const cashBefore = preview?.cash_before_paisa ?? 0
  const cashChange = preview?.cash_change_paisa ?? 0
  const supBefore = preview?.suppliers_owed_before_paisa ?? 0
  const supChange = preview?.suppliers_owed_change_paisa ?? 0

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 sm:items-center"
      onClick={() => phase !== 'deleting' && onClose()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-entry-title"
        className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-white p-5 shadow-xl sm:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 id="delete-entry-title" ref={heading} tabIndex={-1} className="text-xl font-bold text-slate-900 outline-none">
          {phase === 'done' ? 'Deleted' : `Delete ${entryRef}?`}
        </h2>

        {phase === 'done' ? (
          <div className="mt-3 space-y-4">
            <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-base font-semibold text-emerald-900">
              Deleted {deletedRefs.join(', ')}. A full copy is kept — restore it from “Deleted entries” if this was a mistake.
            </div>
            <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl bg-slate-900 px-4 text-lg font-semibold text-white">
              Close
            </button>
          </div>
        ) : loadError != null ? (
          <div className="mt-3 space-y-4">
            <p className="rounded-xl bg-rose-50 p-4 text-base text-rose-800">{friendlyMessage(loadError, 'load')}</p>
            <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
              Close
            </button>
          </div>
        ) : !preview ? (
          <div className="mt-4">
            <Spinner label="Checking what would change…" />
          </div>
        ) : !preview.found ? (
          <div className="mt-3 space-y-4">
            <p className="text-base text-slate-700">This entry no longer exists — it may already have been deleted.</p>
            <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
              Close
            </button>
          </div>
        ) : (
          <div className="mt-3 space-y-4 text-base">
            <section>
              <h3 className="font-semibold text-slate-800">
                {(preview.entries?.length ?? 0) > 1 ? 'These entries go together:' : 'This entry:'}
              </h3>
              <ul className="mt-1 divide-y divide-slate-200 rounded-xl border border-slate-200">
                {(preview.entries ?? []).map((e) => (
                  <li key={e.ref} className="p-3">
                    <div className="flex flex-wrap justify-between gap-2">
                      <span className="font-mono text-sm text-slate-700">{e.ref} · {dateInWords(e.date)}</span>
                      <span className="font-semibold text-slate-900"><Money paisa={e.amount_paisa} /></span>
                    </div>
                    <div className="mt-0.5 break-words text-slate-800">{e.description}</div>
                  </li>
                ))}
              </ul>
            </section>

            {blockers.length > 0 ? (
              <>
                <div role="alert" className="rounded-xl border-2 border-rose-300 bg-rose-50 p-4 text-rose-900">
                  <div className="font-bold">This entry can’t be deleted yet:</div>
                  <ul className="mt-2 list-disc space-y-1 pl-5">
                    {blockers.map((b) => (
                      <li key={b}>{b}</li>
                    ))}
                  </ul>
                </div>
                <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
                  Close
                </button>
              </>
            ) : (
              <>
                <section>
                  <h3 className="font-semibold text-slate-800">What will change:</h3>
                  <ul className="mt-1 divide-y divide-slate-100">
                    <Change
                      label="Cash on hand"
                      before={<Money paisa={cashBefore} />}
                      after={<><Money paisa={cashBefore + cashChange} />{cashChange === 0 && ' (no change)'}</>}
                    />
                    {(preview.stock ?? []).map((s) => (
                      <Change
                        key={s.batch}
                        label={`Stock ${s.batch}`}
                        before={kg(s.kg_before)}
                        after={<>{kg(s.kg_before + s.kg_change)} ({signedKg(s.kg_change)})</>}
                      />
                    ))}
                    {(preview.customers ?? []).map((c) => (
                      <Change key={c.name} label={`${c.name} owes`} before={<Money paisa={c.owes_before_paisa} />} after={<Money paisa={c.owes_after_paisa} />} />
                    ))}
                    {supChange !== 0 && (
                      <Change label="Owed to suppliers" before={<Money paisa={supBefore} />} after={<Money paisa={supBefore + supChange} />} />
                    )}
                    {(preview.advances_change_paisa ?? 0) !== 0 && (
                      <li className="py-1.5 text-slate-700">
                        Customer advances change by <Money paisa={preview.advances_change_paisa ?? 0} />
                      </li>
                    )}
                  </ul>
                  {((preview.batches_removed?.length ?? 0) > 0 || (preview.customers_removed?.length ?? 0) > 0) && (
                    <p className="mt-2 text-slate-700">
                      Also removed:{' '}
                      {[
                        ...(preview.batches_removed ?? []).map((b) => `batch ${b} (it came in with this entry)`),
                        ...(preview.customers_removed ?? []).map((c) => `customer “${c}” (created with this sale, used nowhere else)`),
                      ].join('; ')}
                      .
                    </p>
                  )}
                </section>

                <p className="rounded-xl bg-slate-100 p-3 text-slate-700">
                  A full copy is kept. If this is a mistake you can restore it from “Deleted entries”.
                </p>

                <label className="block">
                  <span className="mb-1.5 block font-semibold text-slate-700">Why delete it? (required)</span>
                  <input
                    type="text"
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    disabled={phase === 'deleting'}
                    placeholder="e.g. entered twice by mistake"
                    className={inputCls}
                  />
                </label>

                {error && (
                  <div role="alert" className="rounded-xl border-2 border-rose-300 bg-rose-50 p-4 text-rose-900">
                    <div className="font-bold">{phase === 'unclear' ? 'Not confirmed' : 'Not deleted'}</div>
                    <div className="mt-1">
                      {phase === 'unclear' ? 'No signal — not confirmed. Tap Delete again: it never deletes twice.' : error}
                    </div>
                  </div>
                )}

                <div className="grid grid-cols-2 gap-3">
                  <button
                    type="button"
                    onClick={confirmDelete}
                    disabled={!reason.trim() || phase === 'deleting'}
                    className="min-h-11 rounded-xl bg-rose-700 px-4 text-lg font-bold text-white hover:bg-rose-800 disabled:bg-slate-300"
                  >
                    {phase === 'deleting' ? 'Deleting…' : 'Delete entry'}
                  </button>
                  <button
                    type="button"
                    onClick={onClose}
                    disabled={phase === 'deleting'}
                    className="min-h-11 rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700 disabled:opacity-60"
                  >
                    Cancel
                  </button>
                </div>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
