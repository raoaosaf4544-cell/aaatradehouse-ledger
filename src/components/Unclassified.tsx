import { useEffect, useState } from 'react'
import { ArrowRightLeft } from 'lucide-react'
import { engine } from '../lib/engine'
import { REASON_RULE, friendlyMessage, reasonProblem } from '../lib/friendly'
import type { CorrectionStart, UnclassifiedRow } from '../lib/types'
import { DEFAULT_REASON, MOVE_TARGETS, moveLines } from '../lib/unclassified'
import { SaveControls, useSafeSave } from './SafeSave'
import { Bi, Card, ErrorBanner, Money, Spinner, dateInWords, inputCls } from './ui'

/**
 * Unclassified — check with baba. Every register line still in 5950, one card each. Baba moves a line in three taps:
 * "Move to…" → the account → Save. The save is the database's own "correct this entry" (the latest version of the
 * entry is corrected; the amount, date and cash stay as they are, only the account changes; history is kept).
 */

export default function Unclassified({ canRecord }: { canRecord: boolean }) {
  const [rows, setRows] = useState<UnclassifiedRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [moving, setMoving] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  const load = () =>
    engine
      .unclassified()
      .then((r) => {
        setRows(r)
        setError(null)
      })
      .catch(setError)

  useEffect(() => {
    load()
  }, [])

  const total = (rows ?? []).reduce((s, r) => s + r.amount_paisa, 0)

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">
          <Bi en="Unclassified — check with baba" ur="غیر واضح — بابا سے پوچھیں" />
        </h2>
        <p className="mt-1 text-base text-slate-600">
          Lines from the register that are not clear yet. When baba says what one was, tap <strong>Move to…</strong>.
        </p>
      </div>

      {error != null && <ErrorBanner error={error} />}

      {done && rows && (
        <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-lg font-bold text-emerald-900">
          <Bi en="Done ✓" ur="ہو گیا" /> — Unclassified now <Money paisa={total} />
        </div>
      )}

      {!rows ? (
        error == null && <Spinner />
      ) : (
        <>
          <Card>
            <div className="text-sm font-semibold uppercase tracking-wide text-slate-500">
              <Bi en="Total unclassified" ur="کل غیر واضح" />
            </div>
            <div className="mt-1 text-3xl font-bold text-amber-700">
              <Money paisa={total} />
            </div>
            <div className="mt-1 text-sm text-slate-500">
              {rows.length} {rows.length === 1 ? 'line' : 'lines'}
            </div>
          </Card>

          {rows.length === 0 && <Card><p className="text-lg text-slate-700">Nothing left to check. ✓</p></Card>}

          {rows.map((r) => (
            <MoveCard
              key={r.latest_ref}
              row={r}
              canRecord={canRecord}
              open={moving === r.latest_ref}
              onOpen={() => {
                setDone(false)
                setMoving(r.latest_ref)
              }}
              onClose={() => setMoving(null)}
              onMoved={() => {
                setMoving(null)
                // the total shown in "Done" is the database's, read again after the save
                load().then(() => setDone(true))
              }}
            />
          ))}
        </>
      )}
    </div>
  )
}

function MoveCard({ row, canRecord, open, onOpen, onClose, onMoved }: {
  row: UnclassifiedRow
  canRecord: boolean
  open: boolean
  onOpen: () => void
  onClose: () => void
  onMoved: () => void
}) {
  const [start, setStart] = useState<CorrectionStart | null>(null)
  const [startError, setStartError] = useState<unknown>(null)
  const [target, setTarget] = useState('')
  const [reason, setReason] = useState(DEFAULT_REASON)
  const safe = useSafeSave()

  useEffect(() => {
    if (!open) return
    setStart(null)
    setStartError(null)
    setTarget('')
    setReason(DEFAULT_REASON)
    engine.correctionStart(row.latest_ref).then(setStart).catch(setStartError)
  }, [open, row.latest_ref])

  const lines = start && target ? moveLines(start.lines, target) : null
  const valid = !!start && !start.blocker && !!lines && !reasonProblem(reason)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid || !start || !lines) return
    const r = await safe.save((k) => engine.correctEntry({ idempotencyKey: k, ref: row.latest_ref, date: start.date, lines, reason }))
    if (r !== null) onMoved()
  }

  return (
    <Card>
      <div className="break-words text-xl font-bold text-slate-900">{row.original_description || '(no wording in the register)'}</div>
      <div className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-2xl font-bold text-slate-900">
          <Money paisa={row.amount_paisa} />
        </span>
        <span className="text-base text-slate-600">{dateInWords(row.entry_date)}</span>
      </div>
      <div className="mt-1 font-mono text-xs text-slate-400">
        {row.latest_ref}
        {row.original_ref !== row.latest_ref && ` · register ${row.original_ref}`}
      </div>

      {canRecord && !open && (
        <button
          type="button"
          onClick={onOpen}
          className="mt-4 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 text-lg font-bold text-white hover:bg-blue-700"
        >
          <ArrowRightLeft className="h-5 w-5" /> <Bi en="Move to…" ur="منتقل کریں" />
        </button>
      )}

      {open && (
        <form onSubmit={submit} className="mt-4 space-y-4">
          {startError != null ? (
            <p role="alert" className="rounded-xl bg-rose-50 p-3 text-base font-semibold text-rose-800">{friendlyMessage(startError, 'load')}</p>
          ) : !start ? (
            <Spinner label="Opening…" />
          ) : start.blocker ? (
            <p role="alert" className="rounded-xl bg-rose-50 p-3 text-base font-semibold text-rose-800">{friendlyMessage({ message: start.blocker, fromServer: true, definite: true }, 'load')}</p>
          ) : (
            <fieldset disabled={safe.locked} className="space-y-4">
              <legend className="mb-2 text-base font-semibold text-slate-700">
                <Bi en="What was it?" ur="یہ کیا تھا؟" />
              </legend>
              <div className="grid grid-cols-2 gap-2">
                {MOVE_TARGETS.map((t) => (
                  <button
                    key={t.code}
                    type="button"
                    aria-pressed={target === t.code}
                    onClick={() => setTarget(t.code)}
                    className={`flex min-h-14 flex-col items-center justify-center rounded-xl border-2 px-2 py-2 text-center leading-tight transition ${
                      target === t.code ? 'border-blue-600 bg-blue-50 text-blue-900 ring-4 ring-blue-100' : 'border-slate-200 bg-white text-slate-800'
                    }`}
                  >
                    <span className="text-base font-bold">{t.en}</span>
                    <span lang="ur" dir="rtl" className="text-base">{t.ur}</span>
                  </button>
                ))}
              </div>
              <label className="block">
                <span className="mb-1.5 block text-base font-semibold text-slate-700">
                  <Bi en="Reason" ur="وجہ" />
                </span>
                <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} className={inputCls} />
                {reasonProblem(reason) && <span role="alert" className="mt-1 block text-sm font-semibold text-rose-700">{REASON_RULE}</span>}
              </label>
            </fieldset>
          )}
          {start && !start.blocker && (
            <SaveControls safe={safe} valid={valid} label="Save / محفوظ کریں" onStartOver={() => setTarget('')} />
          )}
          {!safe.locked && (
            <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
              <Bi en="Cancel" ur="منسوخ" />
            </button>
          )}
        </form>
      )}
    </Card>
  )
}
