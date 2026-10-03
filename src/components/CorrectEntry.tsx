import { useEffect, useRef, useState } from 'react'
import { engine } from '../lib/engine'
import { friendlyMessage } from '../lib/friendly'
import type { AccountBalance, CorrectionPlan, CorrectionStart } from '../lib/types'
import { SaveControls, useSafeSave } from './SafeSave'
import { DateField, Field, Money, Spinner, accountName, dateInWords, inputCls } from './ui'

/**
 * "Correct this entry" (money entries). The owner fixes what was wrong — account, amount, date — and gives a reason.
 * The database works out the correction (one entry moving the difference, or a reversal + the correct entry for a
 * different date), shows it before saving, and saves the pair together. The original entry stays as it was.
 */

// customer, supplier, advance and stock accounts are never picked here (the database refuses them too)
const usable = (a: AccountBalance) => !['1100', '2000', '2200'].includes(a.code) && !a.code.startsWith('12')
const kindWords = { fix: 'Correction', reverse: 'Takes the wrong entry back out', repost: 'The correct entry' } as const

export function CorrectEntryDialog({ entryRef, onClose: close }: { entryRef: string; onClose: (changed: boolean) => void }) {
  const [start, setStart] = useState<CorrectionStart | null>(null)
  const [accounts, setAccounts] = useState<AccountBalance[]>([])
  const [loadError, setLoadError] = useState<unknown>(null)
  const [date, setDate] = useState('')
  const [debitAcc, setDebitAcc] = useState('')
  const [creditAcc, setCreditAcc] = useState('')
  const [amountPkr, setAmountPkr] = useState('')
  const [reason, setReason] = useState('')
  const [plan, setPlan] = useState<CorrectionPlan | null>(null)
  const [planError, setPlanError] = useState<unknown>(null)
  const [saved, setSaved] = useState<string[] | null>(null)
  const safe = useSafeSave()
  const heading = useRef<HTMLHeadingElement>(null)
  const onClose = () => close(saved !== null)

  useEffect(() => {
    heading.current?.focus()
    Promise.all([engine.correctionStart(entryRef), engine.accountBalances()])
      .then(([s, a]) => {
        setStart(s)
        setAccounts(a.filter(usable))
        const dr = s.lines.find((l) => l.debit > 0)
        const cr = s.lines.find((l) => l.credit > 0)
        setDate(s.date)
        setDebitAcc(dr?.account ?? '')
        setCreditAcc(cr?.account ?? '')
        setAmountPkr(dr ? String(dr.debit / 100) : '')
      })
      .catch(setLoadError)
  }, [entryRef])

  const twoLines = (start?.lines.length ?? 0) === 2
  const amountP = Math.round((Number(amountPkr) || 0) * 100)
  const lines = [
    { account: debitAcc, debit: amountP },
    { account: creditAcc, credit: amountP },
  ]
  const ready = !!start && !start.blocker && twoLines && !!date && !!debitAcc && !!creditAcc && debitAcc !== creditAcc && amountP > 0

  // the database's own answer to "what would this post?", asked 0.4 s after typing stops
  const key = JSON.stringify([date, debitAcc, creditAcc, amountP])
  useEffect(() => {
    setPlan(null)
    setPlanError(null)
    if (!ready || saved) return
    let alive = true
    const t = setTimeout(() => {
      engine
        .correctionPreview(entryRef, date, lines)
        .then((p) => alive && setPlan(p))
        .catch((e) => alive && setPlanError(e))
    }, 400)
    return () => {
      alive = false
      clearTimeout(t)
    }
  }, [key, ready]) // eslint-disable-line react-hooks/exhaustive-deps

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!ready || !plan || !reason.trim()) return
    const r = await safe.save((k) => engine.correctEntry({ idempotencyKey: k, ref: entryRef, date, lines, reason }))
    if (r) setSaved(r.event_refs ?? [])
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 sm:items-center" onClick={() => !safe.locked && onClose()}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="correct-entry-title"
        className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-white p-5 shadow-xl sm:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 id="correct-entry-title" ref={heading} tabIndex={-1} className="text-xl font-bold text-slate-900 outline-none">
          {saved ? 'Corrected' : `Correct ${entryRef}`}
        </h2>

        {saved ? (
          <div className="mt-3 space-y-4">
            <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-base font-semibold text-emerald-900">
              Saved {saved.join(' and ')}. {entryRef} stays in the books as it was; the correction is next to it.
            </div>
            <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl bg-slate-900 px-4 text-lg font-semibold text-white">
              Close
            </button>
          </div>
        ) : loadError != null ? (
          <Closing text={friendlyMessage(loadError, 'load')} onClose={onClose} />
        ) : !start ? (
          <div className="mt-4"><Spinner label="Opening the entry…" /></div>
        ) : start.blocker ? (
          <Closing text={start.blocker} onClose={onClose} />
        ) : !twoLines ? (
          <Closing text="This entry has more than two lines. Delete it and enter it again." onClose={onClose} />
        ) : (
          <form onSubmit={submit} className="mt-3 space-y-4 text-base">
            <section className="rounded-xl border border-slate-200 p-3">
              <div className="font-mono text-sm text-slate-700">{start.ref} · {dateInWords(start.date)}</div>
              <div className="mt-0.5 break-words text-slate-800">{start.description}</div>
              <ul className="mt-2 text-sm text-slate-700">
                {start.lines.map((l) => (
                  <li key={l.account + l.debit + l.credit}>
                    {l.debit > 0 ? 'Debit' : 'Credit'} {l.name} ({l.account}): <Money paisa={l.debit || l.credit} />
                  </li>
                ))}
              </ul>
            </section>

            <p className="text-slate-700">Change only what was wrong:</p>
            <fieldset disabled={safe.locked} className="space-y-4">
              <DateField label="Correct date" value={date} onChange={setDate} />
              <Field label="Account it should go to (debit)">
                <select value={debitAcc} onChange={(e) => setDebitAcc(e.target.value)} className={inputCls} required>
                  {accounts.map((a) => <option key={a.code} value={a.code}>{a.code} — {a.name}</option>)}
                </select>
              </Field>
              <Field label="Paid from / received into (credit)">
                <select value={creditAcc} onChange={(e) => setCreditAcc(e.target.value)} className={inputCls} required>
                  {accounts.map((a) => <option key={a.code} value={a.code}>{a.code} — {a.name}</option>)}
                </select>
              </Field>
              <Field label="Correct amount (PKR)">
                <input type="number" min="0" step="0.01" inputMode="decimal" value={amountPkr} onChange={(e) => setAmountPkr(e.target.value)} className={inputCls} required />
              </Field>
              <Field label="Why is it being corrected? (required)">
                <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. paper register says 24 Sep" className={inputCls} required />
              </Field>
            </fieldset>

            {debitAcc && debitAcc === creditAcc && <p role="alert" className="font-semibold text-rose-700">The two accounts must be different.</p>}
            {planError != null && <p role="alert" className="rounded-xl bg-rose-50 p-3 font-semibold text-rose-800">{friendlyMessage(planError, 'load')}</p>}
            {plan && (
              <section className="space-y-3">
                <h3 className="font-semibold text-slate-800">This will be saved (worked out by the database):</h3>
                {plan.plan.map((p) => (
                  <div key={p.kind} className="rounded-xl border border-slate-200 p-3">
                    <div className="font-semibold text-slate-800">{kindWords[p.kind]} — {dateInWords(p.date)}</div>
                    <ul className="mt-1 text-sm text-slate-700">
                      {p.lines.map((l) => (
                        <li key={l.account}>
                          {l.debit > 0 ? 'Debit' : 'Credit'} {accountName(l.account)} ({l.account}): <Money paisa={l.debit || l.credit} />
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
                <h3 className="font-semibold text-slate-800">Each account after the correction:</h3>
                <ul className="divide-y divide-slate-100">
                  {(plan.accounts ?? []).map((a) => (
                    <li key={a.code} className="flex flex-wrap justify-between gap-x-3 py-1.5">
                      <span className="text-slate-700">{a.name} ({a.code})</span>
                      <span className="font-semibold text-slate-900"><Money paisa={a.before_paisa} /> → <Money paisa={a.after_paisa} /></span>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            <SaveControls safe={safe} valid={ready && !!plan && !!reason.trim()} label="Save the correction" onStartOver={onClose} />
            {!safe.locked && (
              <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
                Cancel
              </button>
            )}
          </form>
        )}
      </div>
    </div>
  )
}

function Closing({ text, onClose }: { text: string; onClose: () => void }) {
  return (
    <div className="mt-3 space-y-4">
      <p className="rounded-xl bg-slate-100 p-4 text-base text-slate-800">{text}</p>
      <button type="button" onClick={onClose} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
        Close
      </button>
    </div>
  )
}
