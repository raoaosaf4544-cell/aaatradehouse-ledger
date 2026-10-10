import { useEffect, useState } from 'react'
import { HandCoins, Hammer, Pencil, UserPlus } from 'lucide-react'
import { engine } from '../lib/engine'
import type { WorkerHistoryRow, WorkerResult, WorkerRow } from '../lib/types'
import { SaveControls, useSafeSave } from './SafeSave'
import { Bi, Card, DateField, ErrorBanner, Field, Money, Spinner, inputCls, todayPK } from './ui'

/**
 * Workers / مزدور — part-time labour. Every figure is the database's (public.v_workers, v_worker_history).
 * Work done puts wages owed (2100); pay clears them, anything more is an advance (peshgi, 1320) used first next time.
 */

const PAY_TYPES: { v: WorkerRow['pay_type']; en: string; ur: string; unit: string }[] = [
  { v: 'day', en: 'Per day', ur: 'روزانہ', unit: 'days / دن' },
  { v: 'bag', en: 'Per bag', ur: 'فی بوری', unit: 'bags / بوریاں' },
  { v: 'ton', en: 'Per ton', ur: 'فی ٹن', unit: 'tons / ٹن' },
  { v: 'fixed', en: 'Fixed', ur: 'مقررہ', unit: 'times / بار' },
]
const payType = (v: string) => PAY_TYPES.find((p) => p.v === v) ?? PAY_TYPES[0]
const rs = (paisa: number) => `Rs ${(paisa / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`

export default function Workers({ onPosted, canRecord }: { onPosted: () => void; canRecord: boolean }) {
  const [rows, setRows] = useState<WorkerRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [open, setOpen] = useState<{ id: number; what: 'work' | 'pay' | 'edit' | 'history' } | null>(null)
  const [adding, setAdding] = useState(false)
  const [done, setDone] = useState<string | null>(null)

  const load = () => engine.workers().then(setRows).catch(setError)
  useEffect(() => {
    load()
  }, [])

  function finished(message: string) {
    setOpen(null)
    setAdding(false)
    setDone(message)
    load()
    onPosted()
  }

  const owed = (rows ?? []).reduce((s, r) => s + Math.max(r.owed_paisa, 0), 0)
  const advances = (rows ?? []).reduce((s, r) => s + Math.max(r.advance_paisa, 0), 0)

  return (
    <div className="space-y-4">
      <h2 className="text-2xl font-bold text-slate-800"><Bi en="Workers" ur="مزدور" /></h2>
      {error != null && <ErrorBanner error={error} />}
      {done && <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-lg font-bold text-emerald-900">{done}</div>}
      {!rows ? (
        error == null && <Spinner />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3">
            <Card>
              <div className="text-sm font-semibold text-slate-500"><Bi en="Wages owed" ur="واجب الادا اجرت" /></div>
              <div className="mt-1 text-2xl font-bold text-amber-700"><Money paisa={owed} /></div>
            </Card>
            <Card>
              <div className="text-sm font-semibold text-slate-500"><Bi en="Advances given" ur="پیشگی" /></div>
              <div className="mt-1 text-2xl font-bold text-blue-700"><Money paisa={advances} /></div>
            </Card>
          </div>

          {canRecord && (adding ? (
            <Card><WorkerForm onCancel={() => setAdding(false)} onSaved={(n) => finished(`Saved ✓ — ${n} added.`)} /></Card>
          ) : (
            <button type="button" onClick={() => { setDone(null); setAdding(true) }}
              className="flex min-h-12 w-full items-center justify-center gap-2 rounded-xl border-2 border-slate-300 bg-white px-4 text-lg font-semibold text-slate-700 hover:bg-slate-50">
              <UserPlus className="h-5 w-5" /> <Bi en="Add worker" ur="نیا مزدور" />
            </button>
          ))}

          {rows.length === 0 && <Card><p className="text-lg text-slate-700">No workers yet.</p></Card>}
          {rows.map((w) => {
            const isOpen = (what: string) => open?.id === w.party_id && open.what === what
            return (
              <Card key={w.party_id} className={w.is_active ? '' : 'opacity-60'}>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <div>
                    <div className="text-xl font-bold text-slate-900">{w.name}{!w.is_active && ' (not active)'}</div>
                    <div className="text-sm text-slate-500">
                      {payType(w.pay_type).en} {rs(w.rate_paisa)} · {w.area === 'plant' ? 'Plant / پلانٹ' : 'Shop / other'}{w.phone && ` · ${w.phone}`}
                    </div>
                  </div>
                  <div className="text-right">
                    {w.advance_paisa > 0 ? (
                      <><div className="text-sm text-blue-700"><Bi en="Advance he has" ur="پیشگی" /></div><div className="text-2xl font-bold text-blue-700"><Money paisa={w.advance_paisa} /></div></>
                    ) : (
                      <><div className="text-sm text-slate-500"><Bi en="We owe him" ur="ہم نے دینا ہے" /></div><div className="text-2xl font-bold text-slate-900"><Money paisa={w.owed_paisa} /></div></>
                    )}
                  </div>
                </div>
                {isOpen('work') ? (
                  <WorkForm worker={w} onCancel={() => setOpen(null)} onSaved={(r) => finished(resultWords(r))} />
                ) : isOpen('pay') ? (
                  <PayForm worker={w} onCancel={() => setOpen(null)} onSaved={(r) => finished(resultWords(r))} />
                ) : isOpen('edit') ? (
                  <WorkerForm worker={w} onCancel={() => setOpen(null)} onSaved={(n) => finished(`Saved ✓ — ${n} changed.`)} />
                ) : (
                  <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {canRecord && w.is_active && (
                      <>
                        <Btn onClick={() => { setDone(null); setOpen({ id: w.party_id, what: 'work' }) }} cls="bg-amber-600 text-white hover:bg-amber-700"><Hammer className="h-5 w-5" /> <Bi en="Work" ur="کام" /></Btn>
                        <Btn onClick={() => { setDone(null); setOpen({ id: w.party_id, what: 'pay' }) }} cls="bg-emerald-600 text-white hover:bg-emerald-700"><HandCoins className="h-5 w-5" /> <Bi en="Pay" ur="ادائیگی" /></Btn>
                      </>
                    )}
                    <Btn onClick={() => setOpen(isOpen('history') ? null : { id: w.party_id, what: 'history' })} cls="border-2 border-slate-300 text-slate-700 hover:bg-slate-50"><Bi en="History" ur="تفصیل" /></Btn>
                    {canRecord && <Btn onClick={() => setOpen({ id: w.party_id, what: 'edit' })} cls="border-2 border-slate-300 text-slate-700 hover:bg-slate-50"><Pencil className="h-4 w-4" /> <Bi en="Edit" ur="تبدیل" /></Btn>}
                  </div>
                )}
                {isOpen('history') && <History partyId={w.party_id} />}
              </Card>
            )
          })}
        </>
      )}
    </div>
  )
}

function Btn({ onClick, cls, children }: { onClick: () => void; cls: string; children: React.ReactNode }) {
  return (
    <button type="button" onClick={onClick} className={`flex min-h-12 items-center justify-center gap-2 rounded-xl px-3 text-base font-bold ${cls}`}>
      {children}
    </button>
  )
}

function resultWords(r: WorkerResult) {
  if (r.duplicate) return `Already saved ✓ (${r.event_ref}).`
  return [
    r.wage_paisa != null ? `Saved ✓ — ${r.worker}: wage ${rs(r.wage_paisa)}.` : `Paid ✓ — ${rs(r.paid_paisa ?? 0)} to ${r.worker}.`,
    r.advance_used_paisa ? `${rs(r.advance_used_paisa)} came from his advance.` : '',
    r.advance_paisa ? `${rs(r.advance_paisa)} is an advance (peshgi).` : '',
    r.advance_after_paisa > 0 ? `Advance he has now: ${rs(r.advance_after_paisa)}.` : `We owe him now: ${rs(r.owed_after_paisa)}.`,
  ].filter(Boolean).join(' ')
}

function Cancel({ onClick }: { onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
      Cancel / منسوخ
    </button>
  )
}

function WorkForm({ worker, onCancel, onSaved }: { worker: WorkerRow; onCancel: () => void; onSaved: (r: WorkerResult) => void }) {
  const [date, setDate] = useState(todayPK)
  const [qty, setQty] = useState('')
  const [wage, setWage] = useState('') // blank = qty x rate
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const q = Number(qty)
  const autoWage = Number.isFinite(q) && q > 0 ? Math.round(q * worker.rate_paisa) / 100 : 0
  const wagePkr = wage.trim() === '' ? autoWage : Number(wage)
  const valid = Number.isFinite(q) && q > 0 && Number.isFinite(wagePkr) && wagePkr > 0
  const fromAdvance = Math.min(Math.max(worker.advance_paisa, 0), Math.round(wagePkr * 100) || 0)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((k) => engine.recordWork({ idempotencyKey: k, partyId: worker.party_id, qty: q, wagePkr, occurredOn: date, note }))
    if (r !== null) onSaved(r)
  }

  return (
    <form onSubmit={submit} className="mt-3 space-y-3">
      <fieldset disabled={safe.locked} className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <DateField label="Date / تاریخ" value={date} onChange={setDate} />
          <Field label={`How many ${payType(worker.pay_type).unit}`}>
            <input type="number" min="0" step="0.01" inputMode="decimal" value={qty} onChange={(e) => setQty(e.target.value)} className={inputCls} required />
          </Field>
        </div>
        <Field label="Wage / اجرت (Rs)" hint={`${qty || 0} × ${rs(worker.rate_paisa)} = Rs ${autoWage.toLocaleString()} — change it if different`}>
          <input type="number" min="0" step="0.01" inputMode="decimal" value={wage} onChange={(e) => setWage(e.target.value)} placeholder={String(autoWage || '')} className={inputCls} />
        </Field>
        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} className={inputCls} />
        </Field>
      </fieldset>
      {valid && (
        <p className="rounded-lg bg-slate-100 px-3 py-2 text-base">
          Wage <strong>Rs {wagePkr.toLocaleString()}</strong> to {worker.area === 'plant' ? 'Plant labour' : 'Labour'}
          {fromAdvance > 0 && <> · <strong>{rs(fromAdvance)}</strong> from his advance</>} · owed to him <strong>{rs(Math.round(wagePkr * 100) - fromAdvance)}</strong>
        </p>
      )}
      <SaveControls safe={safe} valid={valid} label="Save work / کام درج کریں" onStartOver={() => { setQty(''); setWage('') }} />
      {!safe.locked && <Cancel onClick={onCancel} />}
    </form>
  )
}

function PayForm({ worker, onCancel, onSaved }: { worker: WorkerRow; onCancel: () => void; onSaved: (r: WorkerResult) => void }) {
  const [date, setDate] = useState(todayPK)
  const [amount, setAmount] = useState('')
  const [from, setFrom] = useState<'cash' | 'bank'>('cash')
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const paisa = Number(amount) > 0 ? Math.round(Number(amount) * 100) : 0
  const owed = Math.max(worker.owed_paisa, 0)
  const valid = paisa > 0

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((k) => engine.payWorker({ idempotencyKey: k, partyId: worker.party_id, amountPkr: paisa / 100, from, occurredOn: date, note }))
    if (r !== null) onSaved(r)
  }

  return (
    <form onSubmit={submit} className="mt-3 space-y-3">
      <fieldset disabled={safe.locked} className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Amount / رقم (Rs)" hint={`We owe him ${rs(owed)}`}>
            <input type="number" min="1" step="0.01" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} className={inputCls} required />
          </Field>
          <DateField label="Date paid / تاریخ" value={date} onChange={setDate} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          {(['cash', 'bank'] as const).map((f) => (
            <label key={f} className={`flex min-h-11 items-center gap-2 rounded-lg border px-3 text-base ${from === f ? 'border-slate-900 bg-white font-semibold' : 'border-slate-300'}`}>
              <input type="radio" name="pay-from" checked={from === f} onChange={() => setFrom(f)} className="h-5 w-5" />
              {f === 'cash' ? <Bi en="Cash" ur="نقد" /> : <Bi en="Bank" ur="بینک" />}
            </label>
          ))}
        </div>
        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} className={inputCls} />
        </Field>
      </fieldset>
      {paisa > owed && (
        <p className="rounded-lg bg-blue-50 px-3 py-2 text-base text-blue-900">
          {rs(paisa - owed)} more than we owe him — it becomes an advance (peshgi / پیشگی), used first on his next work.
        </p>
      )}
      <SaveControls safe={safe} valid={valid} label="Pay / ادائیگی کریں" onStartOver={() => setAmount('')} />
      {!safe.locked && <Cancel onClick={onCancel} />}
    </form>
  )
}

function WorkerForm({ worker, onCancel, onSaved }: { worker?: WorkerRow; onCancel: () => void; onSaved: (name: string) => void }) {
  const [name, setName] = useState(worker?.name ?? '')
  const [phone, setPhone] = useState(worker?.phone ?? '')
  const [type, setType] = useState<WorkerRow['pay_type']>(worker?.pay_type ?? 'day')
  const [rate, setRate] = useState(worker ? String(worker.rate_paisa / 100) : '')
  const [area, setArea] = useState<WorkerRow['area']>(worker?.area ?? 'plant')
  const [active, setActive] = useState(worker?.is_active ?? true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const valid = name.trim() !== '' && rate.trim() !== '' && Number(rate) >= 0

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    setBusy(true)
    setError(null)
    try {
      await engine.saveWorker({ partyId: worker?.party_id ?? null, name, phone, payType: type, ratePkr: Number(rate), area, active })
      onSaved(name.trim())
    } catch (err) {
      setError(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <form onSubmit={submit} className="mt-3 space-y-3">
      {error != null && <ErrorBanner error={error} kind="save" />}
      <fieldset disabled={busy} className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Name / نام"><input type="text" value={name} onChange={(e) => setName(e.target.value)} className={inputCls} required /></Field>
          <Field label="Phone / فون (optional)"><input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} className={inputCls} /></Field>
          <Field label="Pay type / اجرت کی قسم">
            <select value={type} onChange={(e) => setType(e.target.value as WorkerRow['pay_type'])} className={inputCls}>
              {PAY_TYPES.map((p) => <option key={p.v} value={p.v}>{p.en} / {p.ur}</option>)}
            </select>
          </Field>
          <Field label="Rate / ریٹ (Rs)"><input type="number" min="0" step="0.01" inputMode="decimal" value={rate} onChange={(e) => setRate(e.target.value)} className={inputCls} required /></Field>
          <Field label="Works at / کہاں">
            <select value={area} onChange={(e) => setArea(e.target.value as WorkerRow['area'])} className={inputCls}>
              <option value="plant">Plant / پلانٹ</option>
              <option value="other">Shop / other — دکان / دیگر</option>
            </select>
          </Field>
          {worker && (
            <label className="flex min-h-11 items-center gap-3 text-base text-slate-700">
              <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} className="h-5 w-5" />
              <Bi en="Active" ur="فعال" />
            </label>
          )}
        </div>
      </fieldset>
      <button type="submit" disabled={!valid || busy} className="min-h-12 w-full rounded-xl bg-slate-900 px-4 text-lg font-bold text-white disabled:opacity-50">
        {busy ? 'Saving…' : 'Save / محفوظ کریں'}
      </button>
      <Cancel onClick={onCancel} />
    </form>
  )
}

function History({ partyId }: { partyId: number }) {
  const [rows, setRows] = useState<WorkerHistoryRow[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  useEffect(() => {
    engine.workerHistory(partyId).then(setRows).catch(setError)
  }, [partyId])
  if (error) return <ErrorBanner error={error} />
  if (!rows) return <Spinner />
  if (rows.length === 0) return <p className="mt-3 text-base text-slate-500">No work or pay yet.</p>
  return (
    <ul className="mt-3 divide-y divide-slate-100 border-t border-slate-200 text-sm">
      {rows.map((h) => (
        <li key={h.event_id} className="py-2">
          <div className="flex justify-between gap-2">
            <span className="text-slate-500">{h.occurred_on} · <span className="font-mono text-xs">{h.event_ref}</span></span>
            <span className="font-mono tabular-nums">
              {h.owed_change_paisa !== 0 && <>owed {h.owed_change_paisa > 0 ? '+' : '−'}{rs(Math.abs(h.owed_change_paisa))} </>}
              {h.advance_change_paisa !== 0 && <>advance {h.advance_change_paisa > 0 ? '+' : '−'}{rs(Math.abs(h.advance_change_paisa))}</>}
            </span>
          </div>
          <div className="text-slate-800">{h.description}</div>
        </li>
      ))}
    </ul>
  )
}
