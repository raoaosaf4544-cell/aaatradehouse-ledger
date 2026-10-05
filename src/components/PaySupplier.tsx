import { useEffect, useState } from 'react'
import { HandCoins } from 'lucide-react'
import { engine } from '../lib/engine'
import { REASON_RULE, reasonProblem } from '../lib/friendly'
import type { PaySupplierResult, SupplierBalance } from '../lib/types'
import { SaveControls, useSafeSave } from './SafeSave'
import { Bi, Card, DateField, ErrorBanner, Field, Money, Spinner, inputCls, todayPK } from './ui'

/**
 * Pay supplier — everyone we owe (workers, diesel pump, the electricity bill…), from public.v_supplier_balances.
 * Paying lowers what we owe (2000) and cash. A person can never be paid more than owed. A monthly bill (electricity)
 * can: the extra goes to Utilities, and a leftover estimate can be cleared with a reason. The database checks it all.
 */
export default function PaySupplier({ onPosted }: { onPosted: () => void }) {
  const [rows, setRows] = useState<SupplierBalance[] | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [paying, setPaying] = useState<number | null>(null)
  const [clearing, setClearing] = useState<number | null>(null)
  const [done, setDone] = useState<string | null>(null)

  const load = () => engine.supplierBalances().then(setRows).catch(setError)
  useEffect(() => {
    load()
  }, [])

  // people we owe nothing are hidden; a bill party stays listed (its real bill can come after the estimate was cleared)
  const shown = (rows ?? []).filter((r) => r.owed_paisa > 0 || r.extra_to_account)
  const total = (rows ?? []).reduce((s, r) => s + Math.max(r.owed_paisa, 0), 0)

  function finished(message: string) {
    setPaying(null)
    setClearing(null)
    setDone(message)
    load()
    onPosted()
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">
          <Bi en="Pay supplier" ur="ادائیگی" />
        </h2>
        <p className="mt-1 text-base text-slate-600">Everyone we owe for crushing and supplies. Partial payments are fine.</p>
      </div>
      {error != null && <ErrorBanner error={error} />}
      {done && (
        <div role="status" className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4 text-lg font-bold text-emerald-900">
          {done}
        </div>
      )}
      {!rows ? (
        error == null && <Spinner />
      ) : (
        <>
          <Card>
            <div className="text-sm font-semibold uppercase tracking-wide text-slate-500">
              <Bi en="We owe" ur="ہم نے دینا ہے" />
            </div>
            <div className="mt-1 text-3xl font-bold text-amber-700"><Money paisa={total} /></div>
          </Card>
          {shown.length === 0 && <Card><p className="text-lg text-slate-700">We owe nobody right now. ✓</p></Card>}
          {shown.map((r) => (
            <Card key={r.party_id}>
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <div className="text-xl font-bold text-slate-900">{r.name}</div>
                <div className="text-2xl font-bold text-slate-900"><Money paisa={r.owed_paisa} /></div>
              </div>
              <div className="mt-1 text-sm text-slate-500">
                {r.extra_to_account ? 'Monthly bill — pay the full real bill; any extra goes to Utilities.' : 'Pay at most what we owe.'}
                {r.last_paid_on && ` Last paid ${r.last_paid_on}.`}
              </div>
              {paying === r.party_id ? (
                <PayForm supplier={r} onCancel={() => setPaying(null)} onPaid={(res) => finished(paidWords(res))} />
              ) : clearing === r.party_id ? (
                <ClearForm supplier={r} onCancel={() => setClearing(null)} onCleared={(paisa) => finished(`Cleared ✓ — Rs ${(paisa / 100).toLocaleString()} leftover estimate removed for ${r.name}.`)} />
              ) : (
                <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <button
                    type="button"
                    onClick={() => {
                      setDone(null)
                      setPaying(r.party_id)
                    }}
                    className="flex min-h-12 items-center justify-center gap-2 rounded-xl bg-emerald-600 px-4 text-lg font-bold text-white hover:bg-emerald-700"
                  >
                    <HandCoins className="h-5 w-5" /> <Bi en="Pay" ur="ادائیگی" />
                  </button>
                  {r.extra_to_account && r.owed_paisa > 0 && (
                    <button
                      type="button"
                      onClick={() => {
                        setDone(null)
                        setClearing(r.party_id)
                      }}
                      className="min-h-12 rounded-xl border-2 border-slate-300 px-4 text-base font-semibold text-slate-700 hover:bg-slate-50"
                    >
                      Clear leftover estimate
                    </button>
                  )}
                </div>
              )}
            </Card>
          ))}
        </>
      )}
    </div>
  )
}

function paidWords(r: PaySupplierResult) {
  const rs = (p: number) => `Rs ${(p / 100).toLocaleString()}`
  return [
    `Paid ✓ — ${rs(r.paid_paisa)} to ${r.supplier}.`,
    r.extra_paisa > 0 ? `${rs(r.extra_paisa)} extra went to Utilities.` : '',
    r.owed_after_paisa > 0 ? `${rs(r.owed_after_paisa)} still owed.` : '',
  ].filter(Boolean).join(' ')
}

function PayForm({ supplier, onCancel, onPaid }: { supplier: SupplierBalance; onCancel: () => void; onPaid: (r: PaySupplierResult) => void }) {
  const [amount, setAmount] = useState('')
  const [date, setDate] = useState(todayPK)
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const paisa = Number(amount) > 0 ? Math.round(Number(amount) * 100) : 0
  const owed = Math.max(supplier.owed_paisa, 0)
  const bill = !!supplier.extra_to_account
  const tooMuch = !bill && paisa > owed
  const valid = paisa > 0 && !tooMuch

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((k) => engine.paySupplier({ idempotencyKey: k, partyId: supplier.party_id, amountPkr: paisa / 100, occurredOn: date, note }))
    if (r !== null) onPaid(r)
  }

  return (
    <form onSubmit={submit} className="mt-3 space-y-3">
      <fieldset disabled={safe.locked} className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Amount paid / رقم (Rs)" hint={`We owe Rs ${(owed / 100).toLocaleString()}`}>
            <input type="number" min="1" step="0.01" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} className={inputCls} required />
          </Field>
          <DateField label="Date paid" value={date} onChange={setDate} />
        </div>
        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder={bill ? 'e.g. September bill' : 'e.g. rest of the wages'} className={inputCls} />
        </Field>
      </fieldset>
      {tooMuch && (
        <p role="alert" className="text-base font-semibold text-rose-700">
          That is more than we owe {supplier.name}. Pay at most Rs {(owed / 100).toLocaleString()}.
        </p>
      )}
      {bill && paisa > owed && (
        <p className="rounded-lg bg-amber-50 px-3 py-2 text-base text-amber-900">
          Rs {((paisa - owed) / 100).toLocaleString()} more than the estimates — it will go to Utilities.
        </p>
      )}
      {bill && paisa > 0 && paisa < owed && (
        <p className="rounded-lg bg-amber-50 px-3 py-2 text-base text-amber-900">
          Rs {((owed - paisa) / 100).toLocaleString()} of the estimate will stay owed. If the bill is fully paid, clear it after saving.
        </p>
      )}
      <SaveControls safe={safe} valid={valid} label="Pay / ادائیگی کریں" onStartOver={() => setAmount('')} />
      {!safe.locked && (
        <button type="button" onClick={onCancel} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
          Cancel / منسوخ
        </button>
      )}
    </form>
  )
}

function ClearForm({ supplier, onCancel, onCleared }: { supplier: SupplierBalance; onCancel: () => void; onCleared: (paisa: number) => void }) {
  const [reason, setReason] = useState('')
  const safe = useSafeSave()
  const valid = !reasonProblem(reason)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((k) => engine.clearSupplierLeftover({ idempotencyKey: k, partyId: supplier.party_id, occurredOn: todayPK(), reason }))
    if (r !== null) onCleared(r.cleared_paisa)
  }

  return (
    <form onSubmit={submit} className="mt-3 space-y-3">
      <p className="text-base text-slate-700">
        The real bill was less than the estimates. This removes the Rs {(supplier.owed_paisa / 100).toLocaleString()} still owed and lowers Utilities by the same.
      </p>
      <fieldset disabled={safe.locked}>
        <Field label="Reason / وجہ" hint={REASON_RULE}>
          <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. September bill was Rs 600" className={inputCls} />
        </Field>
      </fieldset>
      <SaveControls safe={safe} valid={valid} label="Clear leftover" onStartOver={() => setReason('')} />
      {!safe.locked && (
        <button type="button" onClick={onCancel} className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 text-lg font-semibold text-slate-700">
          Cancel / منسوخ
        </button>
      )}
    </form>
  )
}
