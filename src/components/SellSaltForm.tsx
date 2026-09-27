import { useEffect, useMemo, useState } from 'react'
import { Users, Calculator } from 'lucide-react'
import { engine } from '../lib/engine'
import type { Customer, Product } from '../lib/types'
import { SaveControls, useSafeSave } from './SafeSave'
import {
  Card,
  DateField,
  ErrorBanner,
  Field,
  inputCls,
  JournalPreview,
  SectionTitle,
  accountName,
  todayPK,
} from './ui'

/**
 * Sell Salt: ONE step. The invoice and the salt leaving (FIFO, exact batch cost) are recorded together by
 * record_udhaar_sale, dated the day the salt actually left. The engine computes every paisa; this form only
 * previews the sale side.
 */

type LineDraft = {
  productCode: string
  qtyKg: string
  unitPricePkr: string
}

export default function SellSaltForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [customers, setCustomers] = useState<Customer[] | null>(null)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [customerChoice, setCustomerChoice] = useState<'existing' | 'new'>('existing')
  const [existingCustomerId, setExistingCustomerId] = useState('')
  const [newName, setNewName] = useState('')
  const [newPhone, setNewPhone] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([{ productCode: '', qtyKg: '', unitPricePkr: '' }])
  const [cashPkr, setCashPkr] = useState('')
  const [note, setNote] = useState('')
  const [advancePaisa, setAdvancePaisa] = useState(0)
  const [error, setError] = useState<unknown>(null) // loading errors only
  const safe = useSafeSave()

  useEffect(() => {
    Promise.all([engine.customers(), engine.products()])
      .then(([c, p]) => {
        setCustomers(c)
        setProducts(p.filter((x) => x.form !== 'packaging_material'))
      })
      .catch(setError)
  }, [])

  const selectedCustomer = customers?.find((c) => String(c.id) === existingCustomerId) ?? null
  const customerName = customerChoice === 'new' ? newName.trim() : selectedCustomer?.name ?? ''

  useEffect(() => {
    let alive = true
    if (customerChoice === 'existing' && selectedCustomer) {
      engine
        .customerAdvanceBalance(selectedCustomer.id)
        .then((v) => alive && setAdvancePaisa(v))
        .catch(() => alive && setAdvancePaisa(0))
    } else if (alive) {
      setAdvancePaisa(0)
    }
    return () => {
      alive = false
    }
  }, [customerChoice, selectedCustomer?.id])

  const parsed = useMemo(
    () =>
      lines.map((l) => {
        const qty = Number(l.qtyKg)
        const price = Number(l.unitPricePkr)
        const qtyOk = Number.isFinite(qty) && qty > 0
        const priceOk = Number.isFinite(price) && price > 0
        const product = products?.find((p) => p.code === l.productCode) ?? null
        const revenuePaisa = qtyOk && priceOk ? Math.round(qty * price * 100) : 0
        return { ...l, qty, price, qtyOk, priceOk, product, revenuePaisa }
      }),
    [lines, products],
  )

  const revenuePaisa = parsed.reduce((s, l) => s + l.revenuePaisa, 0)
  const cashPaisa = Number.isFinite(Number(cashPkr)) && Number(cashPkr) > 0 ? Math.round(Number(cashPkr) * 100) : 0
  const advanceApply = Math.min(Math.max(advancePaisa, 0), revenuePaisa)
  const arPaisa = revenuePaisa - Math.min(cashPaisa, revenuePaisa) - advanceApply
  const cashOk = cashPaisa + advanceApply <= revenuePaisa
  const linesValid = parsed.length > 0 && parsed.every((l) => l.qtyOk && l.priceOk && l.product)
  const customerValid = customerChoice === 'new' ? newName.trim().length > 0 : !!selectedCustomer
  const valid = customerValid && linesValid && cashOk

  const saleLines = [
    { account: '1000', debit: Math.min(cashPaisa, revenuePaisa), credit: 0 },
    { account: '2200', debit: advanceApply, credit: 0 },
    { account: '1100', debit: arPaisa, credit: 0 },
    { account: '4000', debit: 0, credit: revenuePaisa },
  ].filter((l) => l.debit > 0 || l.credit > 0)

  function clearSale() {
    setLines([{ productCode: '', qtyKg: '', unitPricePkr: '' }])
    setCashPkr('')
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((key) =>
      engine.recordUdhaarSale({
        customerName,
        items: parsed.map((l) => ({ productCode: l.product!.code, qtyKg: l.qty, unitPricePkrPerKg: l.price })),
        cashReceivedPkr: cashPaisa / 100,
        customerPhone: customerChoice === 'new' ? newPhone : undefined,
        occurredOn: date,
        note: note.trim() || undefined,
        idempotencyKey: key,
      }),
    )
    if (r === null) return
    clearSale()
    onPosted()
  }

  return (
    <Card>
      <SectionTitle>Sell salt</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        {error != null && <ErrorBanner error={error} onDismiss={() => setError(null)} />}
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date salt left" value={date} onChange={setDate} />
          <Field label="Customer">
            <div className="grid grid-cols-2 gap-2">
              {(['existing', 'new'] as const).map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setCustomerChoice(c)}
                  className={`flex min-h-11 items-center justify-center gap-2 rounded-xl border-2 px-3 py-2.5 text-base font-semibold transition ${
                    customerChoice === c
                      ? 'border-blue-500 bg-blue-50 text-blue-800 ring-4 ring-blue-100'
                      : 'border-slate-200 bg-white text-slate-600 hover:border-slate-300'
                  }`}
                >
                  <Users className="h-5 w-5" />
                  {c === 'existing' ? 'Existing' : 'New customer'}
                </button>
              ))}
            </div>
          </Field>
        </div>

        {customerChoice === 'existing' ? (
          <Field
            label="Pick customer"
            hint={advancePaisa > 0 ? `This customer holds an advance of PKR ${(advancePaisa / 100).toLocaleString()} — it will be applied automatically.` : undefined}
          >
            <select value={existingCustomerId} onChange={(e) => setExistingCustomerId(e.target.value)} className={inputCls} required>
              <option value="">— choose —</option>
              {customers?.map((c) => (
                <option key={c.id} value={String(c.id)}>
                  {c.name}
                  {c.phone ? ` — ${c.phone}` : ''}
                </option>
              ))}
            </select>
          </Field>
        ) : (
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
            <Field label="Customer name">
              <input type="text" value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="e.g. Haji Akram" className={inputCls} required />
            </Field>
            <Field label="Phone (optional)">
              <input type="tel" value={newPhone} onChange={(e) => setNewPhone(e.target.value)} placeholder="e.g. 0300-1234567" className={inputCls} />
            </Field>
          </div>
        )}

        <div>
          <div className="mb-2 flex items-center justify-between">
            <span className="text-base font-semibold text-slate-700">What are they buying?</span>
            <button
              type="button"
              onClick={() => setLines((ls) => [...ls, { productCode: '', qtyKg: '', unitPricePkr: '' }])}
              className="min-h-11 rounded-lg border border-slate-300 px-3 text-sm font-semibold text-slate-600 hover:bg-slate-50"
            >
              + Add line
            </button>
          </div>
          <div className="space-y-3">
            {parsed.map((l, i) => (
              <div key={i} className="grid grid-cols-12 items-end gap-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
                <div className="col-span-12 sm:col-span-5">
                  <Field label={i === 0 ? 'Product' : ''}>
                    <select
                      value={l.productCode}
                      onChange={(e) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, productCode: e.target.value } : x)))}
                      className={inputCls}
                      required
                    >
                      <option value="">— choose —</option>
                      {products?.map((p) => (
                        <option key={p.code} value={p.code}>
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </Field>
                </div>
                <div className="col-span-6 sm:col-span-3">
                  <Field label={i === 0 ? 'Quantity (kg)' : ''}>
                    <input
                      type="number"
                      min="1"
                      step="0.001"
                      inputMode="decimal"
                      value={l.qtyKg}
                      onChange={(e) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, qtyKg: e.target.value } : x)))}
                      placeholder="e.g. 4000"
                      className={inputCls}
                      required
                    />
                  </Field>
                </div>
                <div className="col-span-6 sm:col-span-4">
                  <Field label={i === 0 ? 'Price (PKR per kg)' : ''}>
                    <input
                      type="number"
                      min="1"
                      step="0.01"
                      inputMode="decimal"
                      value={l.unitPricePkr}
                      onChange={(e) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, unitPricePkr: e.target.value } : x)))}
                      placeholder="e.g. 12.50"
                      className={inputCls}
                      required
                    />
                  </Field>
                </div>
                {l.revenuePaisa > 0 && (
                  <div className="col-span-12 flex items-center gap-2 text-sm text-slate-600">
                    <Calculator className="h-4 w-4" />
                    Line total: <strong>PKR {(l.revenuePaisa / 100).toLocaleString()}</strong>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <Field label="Cash received now (PKR)" hint="Anything not paid now becomes customer receivable — tracked on the Debtors page.">
          <input
            type="number"
            min="0"
            step="0.01"
            inputMode="decimal"
            value={cashPkr}
            onChange={(e) => setCashPkr(e.target.value)}
            placeholder="0 = full credit"
            className={inputCls}
          />
        </Field>

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. truck LEA-4455, 2nd load" className={inputCls} />
        </Field>

        {!cashOk && <ErrorBanner error={'Cash plus advance is more than the bill total — reduce the cash received.'} />}

        <JournalPreview
          lines={saleLines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account),
            debit: l.debit || undefined,
            credit: l.credit || undefined,
          }))}
          okLabel="The sale and the salt leaving stock (at its exact batch cost) are saved together."
        />

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Sell & record salt leaving" onStartOver={clearSale} />
      </form>
    </Card>
  )
}
