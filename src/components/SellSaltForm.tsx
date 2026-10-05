import { useEffect, useMemo, useState } from 'react'
import { Users, Calculator } from 'lucide-react'
import { engine } from '../lib/engine'
import type { BatchRow, Customer, Product } from '../lib/types'
import { UNITS, fifoCostPaisa, lineKg, qtyWords, unitOf, type QtyUnit } from '../lib/qty'
import { batchNames, leftAndCost, withStockOldestFirst } from '../lib/batches'
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
  unit: QtyUnit
  count: string
  /** 'rate' = price per bag / man / kg (the chosen unit); 'total' = the bill total for the line */
  priceMode: 'rate' | 'total'
  price: string
  /** '' = oldest batch first (FIFO, the default); otherwise the batch baba picked */
  batchCode: string
}

const emptyLine = (): LineDraft => ({ productCode: '', unit: UNITS[0].id, count: '', priceMode: 'rate', price: '', batchCode: '' })
const rs = (n: number) => n.toLocaleString('en-PK', { maximumFractionDigits: 2 })

/** record_udhaar_sale sends the salt out from this location (its default), so only stock here can be sold. */
const PLANT = 'KHANEWAL_PLANT'
const kgText = (g: number) => (g / 1000).toLocaleString('en-PK', { maximumFractionDigits: 3 })

export default function SellSaltForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [customers, setCustomers] = useState<Customer[] | null>(null)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [batches, setBatches] = useState<BatchRow[]>([])
  const [names, setNames] = useState<Map<string, string>>(new Map())
  const [customerChoice, setCustomerChoice] = useState<'existing' | 'new'>('existing')
  const [existingCustomerId, setExistingCustomerId] = useState('')
  const [newName, setNewName] = useState('')
  const [newPhone, setNewPhone] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([emptyLine()])
  const [cashPkr, setCashPkr] = useState('')
  const [note, setNote] = useState('')
  const [advancePaisa, setAdvancePaisa] = useState(0)
  const [error, setError] = useState<unknown>(null) // loading errors only
  const safe = useSafeSave()

  useEffect(() => {
    Promise.all([engine.customers(), engine.products(), engine.batches()])
      .then(([c, p, b]) => {
        setCustomers(c)
        setProducts(p.filter((x) => x.form !== 'packaging_material'))
        setNames(batchNames(b))
        setBatches(withStockOldestFirst(b.filter((x) => x.location_code === PLANT && x.status === 'open')))
      })
      .catch(setError)
  }, [])

  // grams in stock at the plant per product; products with none are not offered
  const stockG = useMemo(() => {
    const m = new Map<string, number>()
    for (const b of batches) m.set(b.product_code, (m.get(b.product_code) ?? 0) + b.onhand_grams)
    return m
  }, [batches])
  const sellable = useMemo(() => products?.filter((p) => (stockG.get(p.code) ?? 0) > 0) ?? [], [products, stockG])

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
        const count = Number(l.count)
        const kg = lineKg(l.unit, Number.isFinite(count) ? count : 0)
        const qty = Math.round(kg * 1000) / 1000
        const price = Number(l.price)
        const qtyOk = qty > 0
        const priceOk = Number.isFinite(price) && price > 0
        const product = products?.find((p) => p.code === l.productCode) ?? null
        // the line total in paisa is what the books keep; a rate is turned into it here
        const revenuePaisa = !qtyOk || !priceOk ? 0 : l.priceMode === 'total' ? Math.round(price * 100) : Math.round(count * price * 100)
        const billOk = revenuePaisa > 0
        const perKg = billOk ? revenuePaisa / 100 / qty : 0
        // the batches this product can come from, oldest first; picking the oldest is the same as the default
        const choices = batches.filter((b) => b.product_code === l.productCode)
        const picked = l.batchCode && l.batchCode !== choices[0]?.batch_code ? choices.find((b) => b.batch_code === l.batchCode) ?? null : null
        return { ...l, countN: count, qty, qtyOk, billOk, product, revenuePaisa, perKg, choices, picked }
      }),
    [lines, products, batches],
  )

  // kg asked for per product across all lines, against what the plant holds
  const askedG = new Map<string, number>()
  for (const l of parsed) if (l.product) askedG.set(l.product.code, (askedG.get(l.product.code) ?? 0) + Math.round(l.qty * 1000))
  const shortOf = (code: string) => Math.max(0, (askedG.get(code) ?? 0) - (stockG.get(code) ?? 0))
  // a picked batch must hold the whole line (together with other lines picking the same batch)
  const pickedShortG = parsed.map((l) =>
    l.picked
      ? Math.max(0, parsed.reduce((s, x) => s + (x.picked?.batch_code === l.picked!.batch_code ? Math.round(x.qty * 1000) : 0), 0) - l.picked.onhand_grams)
      : 0,
  )
  const stockOk = [...askedG.keys()].every((code) => shortOf(code) === 0) && pickedShortG.every((g) => g === 0)

  // what each line's salt cost (its picked batch, or oldest batch first after earlier lines of the same product) —
  // warn below cost, never block
  const lineCost = parsed.map((l, i) => {
    if (!l.product || !l.qtyOk || shortOf(l.product.code) > 0 || pickedShortG[i] > 0) return null
    if (l.picked) return fifoCostPaisa([l.picked], 0, Math.round(l.qty * 1000))
    const code = l.product.code
    const skipG = parsed.slice(0, i).reduce((s, x) => s + (x.product?.code === code && !x.picked ? Math.round(x.qty * 1000) : 0), 0)
    return fifoCostPaisa(batches.filter((b) => b.product_code === code), skipG, Math.round(l.qty * 1000))
  })

  const revenuePaisa = parsed.reduce((s, l) => s + l.revenuePaisa, 0)
  const totalKg = Math.round(parsed.reduce((s, l) => s + l.qty, 0) * 1000) / 1000
  const cashPaisa = Number.isFinite(Number(cashPkr)) && Number(cashPkr) > 0 ? Math.round(Number(cashPkr) * 100) : 0
  const advanceApply = Math.min(Math.max(advancePaisa, 0), revenuePaisa)
  const arPaisa = revenuePaisa - Math.min(cashPaisa, revenuePaisa) - advanceApply
  const cashOk = cashPaisa + advanceApply <= revenuePaisa
  const linesValid = parsed.length > 0 && parsed.every((l) => l.qtyOk && l.billOk && l.product)
  const customerValid = customerChoice === 'new' ? newName.trim().length > 0 : !!selectedCustomer
  const valid = customerValid && linesValid && cashOk && stockOk

  const saleLines = [
    { account: '1000', debit: Math.min(cashPaisa, revenuePaisa), credit: 0 },
    { account: '2200', debit: advanceApply, credit: 0 },
    { account: '1100', debit: arPaisa, credit: 0 },
    { account: '4000', debit: 0, credit: revenuePaisa },
  ].filter((l) => l.debit > 0 || l.credit > 0)

  function clearSale() {
    setLines([emptyLine()])
    setCashPkr('')
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const r = await safe.save((key) =>
      engine.recordUdhaarSale({
        customerName,
        // the typed bill total goes to the database as-is (no per-kg rounding loss)
        items: parsed.map((l) => ({ productCode: l.product!.code, qtyKg: l.qty, lineTotalPkr: l.revenuePaisa / 100, batchCode: l.picked?.batch_code })),
        cashReceivedPkr: cashPaisa / 100,
        customerPhone: customerChoice === 'new' ? newPhone : undefined,
        occurredOn: date,
        note: [parsed.map((l) => qtyWords(l.unit, l.countN)).join(' + '), note.trim()].filter(Boolean).join(' — '),
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
              onClick={() => setLines((ls) => [...ls, emptyLine()])}
              className="min-h-11 rounded-lg border border-slate-300 px-3 text-sm font-semibold text-slate-600 hover:bg-slate-50"
            >
              + Add line
            </button>
          </div>
          <div className="space-y-3">
            {parsed.map((l, i) => {
              const set = (patch: Partial<LineDraft>) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, ...patch } : x)))
              return (
                <div key={i} className="space-y-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
                  <Field
                    label={`Product${parsed.length > 1 ? ` (line ${i + 1})` : ''}`}
                    hint={products && sellable.length === 0 ? 'No salt in stock at the plant — record a purchase or crush run first.' : undefined}
                  >
                    <select value={l.productCode} onChange={(e) => set({ productCode: e.target.value, batchCode: '' })} className={inputCls} required>
                      <option value="">— choose —</option>
                      {sellable.map((p) => (
                        <option key={p.code} value={p.code}>
                          {p.name} — {kgText(stockG.get(p.code) ?? 0)} kg in stock
                        </option>
                      ))}
                    </select>
                  </Field>
                  {l.choices.length > 0 && (
                    <div>
                      <span className="mb-1.5 block text-base font-semibold text-slate-700">From which batch?</span>
                      <div className="grid grid-cols-1 gap-2">
                        {l.choices.map((b, k) => {
                          const on = (l.picked?.batch_code ?? l.choices[0].batch_code) === b.batch_code
                          return (
                            <button
                              key={b.batch_code}
                              type="button"
                              aria-pressed={on}
                              onClick={() => set({ batchCode: k === 0 ? '' : b.batch_code })}
                              className={`min-h-11 rounded-xl border-2 px-3 py-2 text-left transition ${
                                on ? 'border-blue-500 bg-blue-50 text-blue-900' : 'border-slate-200 bg-white text-slate-700'
                              }`}
                            >
                              <span className="block text-base font-semibold">
                                {names.get(b.batch_code) ?? b.batch_code}
                                {k === 0 && <span className="font-normal"> · oldest, used first</span>}
                              </span>
                              <span className="block text-sm">{leftAndCost(b)}</span>
                            </button>
                          )
                        })}
                      </div>
                      {!l.picked && l.choices.length > 1 && (
                        <p className="mt-1 text-sm text-slate-500">If the oldest batch runs out, the rest comes from the next oldest.</p>
                      )}
                      {pickedShortG[i] > 0 && (
                        <p role="alert" className="mt-1 text-base font-semibold text-rose-700">
                          This batch has only {kgText(l.picked!.onhand_grams)} kg — reduce the quantity or pick another batch.
                        </p>
                      )}
                    </div>
                  )}
                  <div>
                    <span className="mb-1.5 block text-base font-semibold text-slate-700">Quantity counted in</span>
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
                      {UNITS.map((u) => (
                        <button
                          key={u.id}
                          type="button"
                          onClick={() => set({ unit: u.id })}
                          className={`min-h-11 rounded-xl border-2 px-2 text-base font-semibold transition ${
                            l.unit === u.id ? 'border-blue-500 bg-blue-50 text-blue-800' : 'border-slate-200 bg-white text-slate-700'
                          }`}
                        >
                          {u.label}
                        </button>
                      ))}
                    </div>
                  </div>
                  {(() => {
                    const u = unitOf(l.unit)
                    return (
                      <>
                        <Field label={`How many ${u.one === 'kg' ? 'kg' : u.one === 'man' ? 'man' : `${u.kg} kg bags`}?`}>
                          <input
                            type="number"
                            min="0"
                            step={u.one === 'bag' ? '1' : u.one === 'man' ? '0.01' : '0.001'}
                            inputMode="decimal"
                            value={l.count}
                            onChange={(e) => set({ count: e.target.value })}
                            className={inputCls}
                            required
                          />
                        </Field>
                        <div>
                          <span className="mb-1.5 block text-base font-semibold text-slate-700">Price</span>
                          <div className="mb-2 grid grid-cols-2 gap-2">
                            {([
                              { id: 'rate', label: `Rs per ${u.one === 'bag' ? 'bag' : u.one}` },
                              { id: 'total', label: 'Bill total' },
                            ] as const).map((m) => (
                              <button
                                key={m.id}
                                type="button"
                                onClick={() => set({ priceMode: m.id })}
                                className={`min-h-11 rounded-xl border-2 px-2 text-base font-semibold transition ${
                                  l.priceMode === m.id ? 'border-blue-500 bg-blue-50 text-blue-800' : 'border-slate-200 bg-white text-slate-700'
                                }`}
                              >
                                {m.label}
                              </button>
                            ))}
                          </div>
                          <input
                            type="number"
                            min="0"
                            step="0.01"
                            inputMode="decimal"
                            aria-label={l.priceMode === 'rate' ? `Rupees per ${u.one}` : 'Bill total for this line in rupees'}
                            value={l.price}
                            onChange={(e) => set({ price: e.target.value })}
                            placeholder={l.priceMode === 'rate' ? `Rs for one ${u.one === 'bag' ? `${u.kg} kg bag` : u.one}` : 'exactly as on the bill'}
                            className={inputCls}
                            required
                          />
                        </div>
                      </>
                    )
                  })()}
                  {l.qtyOk && (
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-lg bg-white px-3 py-2 text-base text-slate-700">
                      <Calculator className="h-4 w-4 shrink-0" />
                      <span>
                        Total <strong>{l.qty.toLocaleString()} kg</strong>
                        {l.billOk && (
                          <>
                            {' '}· <strong>Rs {rs(l.revenuePaisa / 100)}</strong> · <strong>Rs {rs(l.perKg)} per kg</strong>
                          </>
                        )}
                      </span>
                    </div>
                  )}
                  {l.billOk && lineCost[i] != null && l.revenuePaisa < lineCost[i]! && (
                    <p role="alert" className="rounded-lg bg-amber-50 px-3 py-2 text-base font-semibold text-amber-900">
                      ⚠ Below cost: you lose Rs {((lineCost[i]! - l.revenuePaisa) / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })} on this sale
                      <span className="block text-sm font-normal">
                        Cost Rs {rs(lineCost[i]! / 100 / l.qty)}/kg · price Rs {rs(l.perKg)}/kg. You can still save.
                      </span>
                    </p>
                  )}
                  {l.product && shortOf(l.product.code) > 0 && (
                    <p role="alert" className="text-base font-semibold text-rose-700">
                      Only {kgText(stockG.get(l.product.code) ?? 0)} kg of {l.product.name} in stock
                      {parsed.filter((x) => x.product?.code === l.product!.code).length > 1 ? ' for all its lines together' : ''} — reduce the quantity.
                    </p>
                  )}
                  {parsed.length > 1 && (
                    <button
                      type="button"
                      onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}
                      className="min-h-11 rounded-lg border border-slate-300 px-3 text-base font-semibold text-slate-700 hover:bg-white"
                    >
                      Remove this line
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        </div>

        {revenuePaisa > 0 && (
          <div className="rounded-xl bg-blue-50 px-4 py-3 text-base text-blue-900">
            Bill total: <strong>Rs {rs(revenuePaisa / 100)}</strong> for <strong>{totalKg.toLocaleString()} kg</strong>
            {totalKg > 0 && <> · <strong>Rs {rs(revenuePaisa / 100 / totalKg)} per kg</strong></>}
          </div>
        )}

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
