import { useState } from 'react'
import { engine } from '../lib/engine'
import { friendlyMessage } from '../lib/friendly'
import { useOffline } from '../lib/offline'
import type { DeletedEntry } from '../lib/types'
import { Badge, Card, EmptyState, ErrorBanner, Money, ShowMore, Spinner, usePaged } from './ui'

/** Every deleted entry with who / when / why, and Restore (puts it back exactly as it was, same numbers). */
export default function DeletedEntries() {
  const list = usePaged((limit, offset) => engine.deletedEntries(limit, offset))
  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">Deleted entries</h2>
        <p className="mt-1 text-base text-slate-600">A full copy of every deleted entry is kept here. Restore puts it back exactly as it was.</p>
      </div>
      {list.error != null && <ErrorBanner error={list.error} />}
      {!list.rows ? (
        <Spinner />
      ) : list.rows.length === 0 ? (
        <EmptyState>Nothing has been deleted.</EmptyState>
      ) : (
        <div className="space-y-3">
          {list.rows.map((d) => (
            <DeletedCard key={d.id} d={d} onRestored={list.reload} />
          ))}
        </div>
      )}
      <ShowMore paged={list} />
    </div>
  )
}

function DeletedCard({ d, onRestored }: { d: DeletedEntry; onRestored: () => void }) {
  const offline = useOffline()
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const s = d.summary
  const cash = s.cash_change_paisa ?? 0

  async function restore() {
    if (busy) return
    setBusy(true)
    setMsg(null)
    try {
      const r = await engine.restoreEntry(d.id)
      setMsg({ ok: true, text: `${r.already_restored ? 'Already restored' : 'Restored'}: ${r.event_refs.join(', ')}.` })
      setConfirming(false)
      onRestored()
    } catch (e) {
      const definite = (e as { definite?: boolean }).definite !== false
      setMsg({ ok: false, text: definite ? friendlyMessage(e, 'save') : 'No signal — not confirmed. Tap Restore again: it never restores twice.' })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="font-mono text-base font-bold text-slate-800">{d.event_refs.join(', ')}</span>
        {d.restored_at ? <Badge tone="emerald">restored</Badge> : <Badge tone="rose">deleted</Badge>}
      </div>
      <div className="mt-1 text-base text-slate-700">
        {(s.entries ?? []).map((e) => e.description).join(' · ')}
      </div>
      <dl className="mt-2 space-y-1 text-base">
        <div className="flex flex-wrap gap-x-2">
          <dt className="text-slate-600">Deleted:</dt>
          <dd className="text-slate-900">{new Date(d.deleted_at).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' })} by {d.deleted_by_name ?? '—'}</dd>
        </div>
        <div className="flex flex-wrap gap-x-2">
          <dt className="text-slate-600">Why:</dt>
          <dd className="text-slate-900">{d.reason}</dd>
        </div>
        {cash !== 0 && (
          <div className="flex flex-wrap gap-x-2">
            <dt className="text-slate-600">Cash changed by:</dt>
            <dd className="text-slate-900"><Money paisa={cash} /></dd>
          </div>
        )}
        {d.restored_at && (
          <div className="flex flex-wrap gap-x-2">
            <dt className="text-slate-600">Restored:</dt>
            <dd className="text-slate-900">{new Date(d.restored_at).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' })} by {d.restored_by_name ?? '—'}</dd>
          </div>
        )}
      </dl>

      {msg && (
        <div role="status" className={`mt-3 rounded-xl p-3 text-base font-semibold ${msg.ok ? 'bg-emerald-50 text-emerald-900' : 'bg-rose-50 text-rose-900'}`}>
          {msg.text}
        </div>
      )}

      {!d.restored_at &&
        (confirming ? (
          <div className="mt-3 space-y-2">
            <p className="text-base text-slate-800">Put {d.event_refs.join(', ')} back exactly as it was? The books are checked first.</p>
            <div className="grid grid-cols-2 gap-3">
              <button type="button" onClick={restore} disabled={busy || offline}
                className="min-h-11 rounded-xl bg-emerald-700 px-4 text-lg font-bold text-white hover:bg-emerald-800 disabled:bg-slate-300">
                {busy ? 'Restoring…' : 'Restore'}
              </button>
              <button type="button" onClick={() => setConfirming(false)} disabled={busy}
                className="min-h-11 rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <button type="button" onClick={() => setConfirming(true)} disabled={offline}
            className="mt-3 min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-base font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-60">
            Restore…
          </button>
        ))}
    </Card>
  )
}
