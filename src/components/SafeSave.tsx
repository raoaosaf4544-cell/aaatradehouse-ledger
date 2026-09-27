import { useRef, useState } from 'react'
import { engine, InvariantError, type ConfirmedEntry } from '../lib/engine'
import { ErrorBanner, Money } from './ui'
import { useOffline } from '../lib/offline'

const newKey = () => crypto.randomUUID()

export const START_OVER_WARNING =
  'If the first try reached the server it is already saved — check the list before entering again.'

/**
 * Safe saving on a bad signal. One idempotency key per entry: created when the form opens, reused on
 * every Retry of that entry (the database writes it at most once), replaced only after a confirmed
 * save, a clear "no" from the database, or Start over. While saving or after an unclear failure the
 * form is locked, so a Retry always sends identical data with the same key.
 */
export function useSafeSave() {
  const [key, setKey] = useState(newKey)
  // 'already' = Start over found the entry was saved after all: show it, keep the form locked
  const [phase, setPhase] = useState<'idle' | 'saving' | 'failed' | 'saved' | 'already'>('idle')
  const [confirmed, setConfirmed] = useState<ConfirmedEntry | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [checking, setChecking] = useState(false)
  const [startOverOffline, setStartOverOffline] = useState(false)
  const inFlight = useRef(false) // blocks a double tap before React re-renders
  const offline = useOffline() // entries need signal: the form is disabled while offline

  async function save<T>(write: (key: string) => Promise<T>): Promise<T | null> {
    if (inFlight.current) return null
    inFlight.current = true
    setPhase('saving')
    setError(null)
    setConfirmed(null)
    setStartOverOffline(false)
    try {
      const result = await write(key)
      // Confirm from the database: the ref and amount shown are what it holds, not what was typed.
      // A "duplicate" reply lands here too and shows the original entry.
      const entry = await engine.entryByKey(key)
      if (!entry) throw new InvariantError('Save not confirmed yet', false)
      setConfirmed(entry)
      setPhase('saved')
      setKey(newKey()) // the next entry is a new entry
      return result
    } catch (e) {
      if (e instanceof InvariantError && e.definite) {
        // The database clearly said no: nothing was written. Unlock for correction with a fresh key.
        setError(e)
        setPhase('idle')
        setKey(newKey())
      } else {
        setPhase('failed') // no clear answer: keep data locked, Retry resends it with the same key
      }
      return null
    } finally {
      inFlight.current = false
    }
  }

  /**
   * Start over after an unclear failure: first ask the database whether the old key was saved.
   * Found -> "Already saved" (form stays locked; "New entry" unlocks it). Not found -> clear, new key.
   * No signal -> show the warning and stay locked (Retry is still the safe choice).
   */
  async function startOver(clear: () => void) {
    if (checking) return
    setChecking(true)
    setStartOverOffline(false)
    try {
      const entry = await engine.entryByKey(key)
      setKey(newKey())
      setError(null)
      if (entry) {
        setConfirmed(entry)
        setPhase('already')
        return
      }
      setConfirmed(null)
      setPhase('idle')
      clear()
    } catch {
      setStartOverOffline(true)
    } finally {
      setChecking(false)
    }
  }

  /** After "Already saved": unlock an empty form for a genuinely new entry (the key is already new). */
  function newEntry(clear: () => void) {
    setPhase('idle')
    setConfirmed(null)
    clear()
  }

  return {
    key, phase, confirmed, error, checking, startOverOffline, save, startOver, newEntry, offline,
    locked: phase === 'saving' || phase === 'failed' || phase === 'already' || offline,
  }
}

export type SafeSave = ReturnType<typeof useSafeSave>

export function SavedBanner({ safe }: { safe: SafeSave }) {
  if ((safe.phase !== 'saved' && safe.phase !== 'already') || !safe.confirmed) return null
  return (
    <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-lg font-bold text-emerald-800">
      {safe.phase === 'already' ? 'Already saved' : '✓ Saved'} — <Money paisa={safe.confirmed.total_paisa} /> (
      {safe.confirmed.event_ref})
    </div>
  )
}

/** Status banners + Save / Retry / Start over. Put it inside the form, after the locked fieldset. */
export function SaveControls({
  safe,
  valid,
  label,
  onStartOver,
  className = 'bg-emerald-600 hover:bg-emerald-700',
}: {
  safe: SafeSave
  valid: boolean
  label: string
  onStartOver: () => void
  className?: string
}) {
  return (
    <div className="space-y-3">
      {safe.error != null && <ErrorBanner error={safe.error} />}
      <SavedBanner safe={safe} />
      {safe.phase === 'already' ? (
        <button
          type="button"
          onClick={() => safe.newEntry(onStartOver)}
          className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 py-3.5 text-lg font-semibold text-slate-700 hover:bg-slate-50"
        >
          New entry
        </button>
      ) : safe.phase === 'failed' ? (
        <>
          <div role="alert" className="rounded-xl border-2 border-rose-300 bg-rose-50 p-4 text-lg font-bold text-rose-800">
            Not saved — check signal and tap Retry
          </div>
          {safe.startOverOffline && (
            <div role="alert" className="rounded-xl border-2 border-amber-300 bg-amber-50 p-4 text-base font-semibold text-amber-900">
              {START_OVER_WARNING}
            </div>
          )}
          <div className="grid grid-cols-2 gap-3">
            <button type="submit" disabled={safe.offline} className="min-h-11 rounded-xl bg-rose-600 px-4 py-3.5 text-lg font-bold text-white shadow-sm hover:bg-rose-700 disabled:opacity-60">
              Retry
            </button>
            <button
              type="button"
              disabled={safe.checking}
              onClick={() => safe.startOver(onStartOver)}
              className="min-h-11 rounded-xl border-2 border-slate-300 px-4 py-3.5 text-lg font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-60"
            >
              {safe.checking ? 'Checking…' : 'Start over'}
            </button>
          </div>
        </>
      ) : (
        <button
          type="submit"
          disabled={!valid || safe.phase === 'saving' || safe.offline}
          className={`min-h-11 w-full rounded-xl px-4 py-3.5 text-lg font-bold text-white shadow-sm transition disabled:cursor-not-allowed disabled:bg-slate-300 ${className}`}
        >
          {safe.phase === 'saving' ? 'Saving…' : safe.offline ? 'Offline — entries need signal' : label}
        </button>
      )}
    </div>
  )
}
