import { useEffect, useMemo, useState } from 'react'
import { Truck, Users, Calculator } from 'lucide-react'
import { engine } from '../lib/engine'
import type { Customer, Product, FifoBatch, Location } from '../lib/types'
import { gramsToKg } from '../lib/types'
import { SaveControls, SavedBanner, useSafeSave } from './SafeSave'
import {
  Badge,
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
 * Sell Salt / Dispatch — two steps, both previewed live:
 *   1. Invoice   → record_sale (Dr Cash + Dr AR (− advance) / Cr Revenue 4000)
 *   2. Dispatch  → record_dispatch (Dr COGS 4100 / Cr Inventory 12xx, FIFO batches)
 *
 * The engine computes every paisa; this form only previews what the DB will do.
 */


type LineDraft = {
  productCode: string
  qtyKg: string
  unitPricePkr: string
}

type PreviewAlloc = {
  batch_code: string
  qty_grams: number
  unit_cost_ppk: number
  cogs_paisa: number
}

export default function SellSaltForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [customers, setCustomers] = useState<Customer[] | null>(null)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [locations, setLocations] = useState<Location[] | null>(null)
  const [customerChoice, setCustomerChoice] = useState<'existing' | 'new'>('existing')
  const [existingCustomerId, setExistingCustomerId] = useState('')
  const [newName, setNewName] = useState('')
  const [newPhone, setNewPhone] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([{ productCode: '', qtyKg: '', unitPricePkr: '' }])
  const [cashPkr, setCashPkr] = useState('')
  const [note, setNote] = useState('')
  const [advancePaisa, setAdvancePaisa] = useState(0)
  const [error, setError] = useState<unknown>(null) // loading errors only
  const saleSafe = useSafeSave()
  const dispatchSafe = useSafeSave()
  const [sellMode, setSellMode] = useState<'one' | 'two'>('one')

  // Dispatch state
  const [dispatchOpen, setDispatchOpen] = useState(false)
  const [invoiceRef, setInvoiceRef] = useState<string | null>(null)
  const [dispatchQty, setDispatchQty] = useState<Record<number, string>>({})
  const [locationCode, setLocationCode] = useState('')
  const [mode, setMode] = useState<'fifo' | 'manual'>('fifo')
  const [manual, setManual] = useState<Record<string, string>>({})
  const [overrideReason, setOverrideReason] = useState('')
  const [dispatchNote, setDispatchNote] = useState('')
  const [fifo, setFifo] = useState<FifoBatch[] | null>(null)
  const [dispatchCount, setDispatchCount] = useState(0)

  useEffect(() => {
    Promise.all([engine.customers(), engine.products(), engine.locations()])
      .then(([c, p, l]) => {
        setCustomers(c)
        setProducts(p.filter((x) => x.form !== 'packaging_material'))
        setLocations(l)
        setLocationCode((prev) => prev || l.find((x) => x.kind === 'plant')?.code || l[0]?.code || '')
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
        const revenuePaisa = qtyOk && priceOk ? Math.round((qty * price * 100) / 1) : 0
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

  const invAccount = useMemo(() => {
    switch (parsed[0]?.product?.form) {
      case 'raw': return '1200'
      case 'bulk_processed': return '1210'
      case 'packaged': return '1220'
      case 'packaging_material': return '1230'
      default: return '1500'
    }
  }, [parsed])

  // Reload the FIFO pool whenever the dispatch panel opens, the invoice or the
  // stock-affecting inputs change, or a dispatch completes (partials shift stock).
  useEffect(() => {
    setFifo(null)
    if (!dispatchOpen || !invoiceRef || !locationCode || !parsed[0]?.product) return
    let alive = true
    engine
      .fifoPool(parsed[0].product.code, locationCode)
      .then((pool) => alive && setFifo(pool))
      .catch(() => alive && setFifo([]))
    return () => {
      alive = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dispatchOpen, invoiceRef, locationCode, parsed[0]?.product?.code, dispatchCount])

  const dispatchTotalKg = parsed.reduce((s, l) => s + (l.qtyOk ? l.qty : 0), 0)
  const manualAllocs: PreviewAlloc[] = useMemo(
    () =>
      (fifo ?? []).flatMap((b) => {
        const kg = Number(manual[b.batch_code] ?? 0)
        if (!Number.isFinite(kg) || kg <= 0) return []
        const grams = Math.round(kg * 1000)
        return [{ batch_code: b.batch_code, qty_grams: grams, unit_cost_ppk: b.unit_cost_ppk, cogs_paisa: Math.round((grams * b.unit_cost_ppk) / 1000) }]
      }),
    [fifo, manual],
  )

  const fifoAllocs: PreviewAlloc[] = useMemo(() => {
    if (mode !== 'fifo' || !fifo) return []
    let remaining = Math.round(dispatchTotalKg * 1000)
    const out: PreviewAlloc[] = []
    for (const b of fifo) {
      if (remaining <= 0) break
      const take = Math.min(remaining, b.onhand_grams)
      out.push({ batch_code: b.batch_code, qty_grams: take, unit_cost_ppk: b.unit_cost_ppk, cogs_paisa: Math.round((take * b.unit_cost_ppk) / 1000) })
      remaining -= take
    }
    return out
  }, [mode, fifo, dispatchTotalKg])

  const previewAllocs = mode === 'manual' ? manualAllocs : fifoAllocs
  const previewCogs = previewAllocs.reduce((s, a) => s + a.cogs_paisa, 0)
  const manualSumKg = manualAllocs.reduce((s, a) => s + a.qty_grams, 0) / 1000
  const manualBalanced = Math.round(manualSumKg * 1000) === Math.round(dispatchTotalKg * 1000)
  const fifoShort = mode === 'fifo' && fifo !== null && fifoAllocs.reduce((s, a) => s + a.qty_grams, 0) < Math.round(dispatchTotalKg * 1000)
  const singleLine = parsed.length === 1

  function clearSale() {
    setLines([{ productCode: '', qtyKg: '', unitPricePkr: '' }])
    setCashPkr('')
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid || !cashOk) return
    const sale = {
      customerName,
      items: parsed.map((l) => ({ productCode: l.product!.code, qtyKg: l.qty, unitPricePkrPerKg: l.price })),
      cashReceivedPkr: cashPaisa / 100,
      customerPhone: customerChoice === 'new' ? newPhone : undefined,
      occurredOn: date,
      note: note.trim() || undefined,
    }
    if (sellMode === 'one') {
      const r = await saleSafe.save((key) => engine.recordUdhaarSale({ ...sale, idempotencyKey: key }))
      if (r === null) return
      clearSale()
      onPosted()
      return
    }
    const res = await saleSafe.save((key) => engine.recordSale({ ...sale, idempotencyKey: key }))
    if (res === null) return
    setInvoiceRef(res.sale_ref)
    setDispatchOpen(true)
    setDispatchQty(Object.fromEntries(parsed.map((l, i) => [i, l.qtyOk ? String(l.qty) : ''])))
    onPosted()
  }

  // Two-step sale: once the invoice is saved it stays locked until "New sale", so a second tap on
  // "Record invoice" can never create a second invoice by accident.
  const invoiceSaved = invoiceRef !== null && dispatchOpen

  function newSale() {
    setInvoiceRef(null)
    setDispatchOpen(false)
    clearSale()
    clearDispatch()
  }

  function clearDispatch() {
    setManual({})
    setOverrideReason('')
    setDispatchNote('')
  }

  const dispatchValid =
    singleLine &&
    Number(dispatchQty[0] ?? 0) > 0 &&
    !(mode === 'manual' && (overrideReason.trim().length === 0 || !manualBalanced)) &&
    !fifoShort

  async function submitDispatch(e: React.FormEvent) {
    e.preventDefault()
    if (!invoiceRef || !dispatchValid) return
    const qtyKg = Number(dispatchQty[0] ?? 0)
    const res = await dispatchSafe.save((key) =>
      engine.recordDispatch({
        saleRef: invoiceRef,
        lines: [
          {
            productCode: parsed[0].product!.code,
            qtyKg,
            locationCode,
            mode,
            overrideReason: mode === 'manual' ? overrideReason.trim() || undefined : undefined,
            allocations:
              mode === 'manual'
                ? manualAllocs.map((a) => ({ batchCode: a.batch_code, qtyKg: a.qty_grams / 1000 }))
                : undefined,
          },
        ],
        occurredOn: date,
        note: dispatchNote.trim() || undefined,
        idempotencyKey: key,
      }),
    )
    if (res === null) return
    setManual({})
    setOverrideReason('')
    setDispatchCount((c) => c + 1)
    onPosted()
  }

  return (
    <div className="space-y-5">
      <Card>
        <SectionTitle>Sell salt — step 1: the invoice</SectionTitle>
        <form onSubmit={submit} className="space-y-5">
          {error != null && <ErrorBanner error={error} onDismiss={() => setError(null)} />}
          <fieldset disabled={saleSafe.locked || dispatchSafe.locked || invoiceSaved} className="space-y-5">
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
            <DateField label="Date" value={date} onChange={setDate} />
            <Field label="Customer">
              <div className="grid grid-cols-2 gap-2">
                {(['existing', 'new'] as const).map((c) => (
                  <button
                    key={c}
                    type="button"
                    onClick={() => setCustomerChoice(c)}
                    className={`flex items-center justify-center gap-2 rounded-xl border-2 px-3 py-2.5 text-base font-semibold transition ${
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
                      <span className="text-slate-400">
                        ({l.qty.toLocaleString()} kg × PKR {l.price.toLocaleString()}/kg)
                      </span>
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

          {!cashOk && <ErrorBanner error={'Cash plus advance application exceeds the invoice total — reduce the cash received.'} />}

          <div className="grid grid-cols-2 gap-3">
            {([
              { id: 'one', title: 'Sell & dispatch now', sub: 'Stock leaves today — one tap' },
              { id: 'two', title: 'Invoice only, dispatch later', sub: 'Salt leaves later — two steps' },
            ] as const).map((m) => (
              <button
                key={m.id}
                type="button"
                onClick={() => setSellMode(m.id)}
                className={`rounded-xl border-2 px-4 py-3 text-left transition ${
                  sellMode === m.id ? 'border-blue-500 bg-blue-50 ring-4 ring-blue-100' : 'border-slate-200 bg-white hover:border-slate-300'
                }`}
              >
                <div className="text-base font-bold text-slate-800">{m.title}</div>
                <div className="text-xs text-slate-500">{m.sub}</div>
              </button>
            ))}
          </div>

          <JournalPreview
            lines={saleLines.map((l) => ({
              account: l.account,
              accountName: accountName(l.account),
              debit: l.debit || undefined,
              credit: l.credit || undefined,
            }))}
            okLabel={
              sellMode === 'one'
                ? 'One tap: revenue AND the COGS/inventory dispatch both post together when you save.'
                : 'Revenue posts now. Stock is only relieved when you dispatch — the next step below.'
            }
          />

          </fieldset>

          {invoiceSaved ? (
            <div className="space-y-3">
              <SavedBanner safe={saleSafe} />
              <button
                type="button"
                onClick={newSale}
                disabled={dispatchSafe.locked}
                className="min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 py-3.5 text-lg font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-60"
              >
                New sale
              </button>
            </div>
          ) : (
            <SaveControls
              safe={saleSafe}
              valid={valid && cashOk && !dispatchSafe.locked}
              label={sellMode === 'one' ? 'Sell & dispatch' : 'Record invoice'}
              onStartOver={clearSale}
            />
          )}
        </form>
      </Card>

      {dispatchOpen && invoiceRef && (
        <Card>
          <SectionTitle>
            <span className="flex items-center gap-2">
              <Truck className="h-4 w-4" /> Step 2: dispatch stock for {invoiceRef}
            </span>
          </SectionTitle>

          {!singleLine ? (
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
              Multi-product invoices dispatch one product at a time. Record this invoice's other products
              from the invoice list on the Debtors &amp; Sales page after its dispatch form opens there.
            </div>
          ) : (
            <form onSubmit={submitDispatch} className="space-y-5">
              <fieldset disabled={dispatchSafe.locked} className="space-y-5">
              <div className="flex items-center justify-between rounded-xl bg-blue-50 px-4 py-3 text-sm text-blue-800">
                <span>Default is FIFO — the oldest salt of this product at the chosen location goes first.</span>
                <Badge tone="blue">{fifo === null ? 'checking stock…' : `${fifo.length} open batch(es)`}</Badge>
              </div>

              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <Field label="Dispatch quantity (kg)" hint={`Invoice quantity: ${parsed[0]?.qty.toLocaleString()} kg`}>
                  <input
                    type="number"
                    min="1"
                    step="0.001"
                    inputMode="decimal"
                    value={dispatchQty[0] ?? ''}
                    onChange={(e) => setDispatchQty((q) => ({ ...q, 0: e.target.value }))}
                    className={inputCls}
                    required
                  />
                </Field>
                <Field label="From where?" hint="Stock at one place is never silently taken from another.">
                  <select value={locationCode} onChange={(e) => setLocationCode(e.target.value)} className={inputCls} required>
                    {locations?.map((l) => (
                      <option key={l.code} value={l.code}>
                        {l.name}
                      </option>
                    ))}
                  </select>
                </Field>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {(['fifo', 'manual'] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setMode(m)}
                    className={`rounded-xl border-2 px-4 py-3 text-left transition ${
                      mode === m ? 'border-blue-500 bg-blue-50 ring-4 ring-blue-100' : 'border-slate-200 bg-white hover:border-slate-300'
                    }`}
                  >
                    <div className="text-base font-bold text-slate-800">{m === 'fifo' ? 'Automatic (FIFO)' : 'Choose batches myself'}</div>
                    <div className="text-xs text-slate-500">
                      {m === 'fifo' ? 'Engine takes oldest compatible batches' : 'Requires a reason — kept in the audit trail'}
                    </div>
                  </button>
                ))}
              </div>

              {mode === 'manual' && (
                <div className="space-y-3">
                  {(fifo ?? []).length === 0 && (
                    <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                      No open batches of this product at this location.
                    </div>
                  )}
                  {(fifo ?? []).map((b) => (
                    <Field
                      key={b.batch_code}
                      label={`${b.batch_code} — ${gramsToKg(b.onhand_grams)} kg available @ PKR ${(b.unit_cost_ppk / 100).toFixed(2)}/kg`}
                    >
                      <input
                        type="number"
                        min="0"
                        step="0.001"
                        inputMode="decimal"
                        value={manual[b.batch_code] ?? ''}
                        onChange={(e) => setManual((m) => ({ ...m, [b.batch_code]: e.target.value }))}
                        placeholder="kg from this batch"
                        className={inputCls}
                      />
                    </Field>
                  ))}
                  {Object.values(manual).some((v) => Number(v) > 0) && !manualBalanced && (
                    <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                      Batch picks must exactly cover {dispatchTotalKg.toLocaleString()} kg — currently {manualSumKg.toLocaleString()} kg.
                    </div>
                  )}
                  <Field label="Reason for choosing batches manually" hint="Required — recorded permanently against this dispatch.">
                    <input
                      type="text"
                      value={overrideReason}
                      onChange={(e) => setOverrideReason(e.target.value)}
                      placeholder="e.g. father wants the newer stock"
                      className={inputCls}
                      required
                    />
                  </Field>
                </div>
              )}

              {mode === 'fifo' && fifoShort && (
                <div className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
                  Not enough compatible stock here — the engine will refuse. Buy or process more first.
                </div>
              )}

              <JournalPreview
                lines={[
                  { account: '4100', accountName: accountName('4100'), debit: previewCogs || undefined },
                  { account: invAccount, accountName: accountName(invAccount), credit: previewCogs || undefined },
                ]}
                okLabel={
                  previewAllocs.length > 0
                    ? `Exact per-batch cost from ${previewAllocs.length} batch(es), priced by the engine at the moment of dispatch.`
                    : 'The engine prices each batch at its exact book value when you save.'
                }
              />

              {previewAllocs.length > 0 && (
                <div className="rounded-xl border border-slate-200 bg-white p-4">
                  <div className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500">
                    Batches being consumed ({mode === 'fifo' ? 'FIFO' : 'manual'})
                  </div>
                  <ul className="space-y-1 text-sm text-slate-700">
                    {previewAllocs.map((a) => (
                      <li key={a.batch_code} className="flex justify-between">
                        <span>
                          {a.batch_code} — {gramsToKg(a.qty_grams)} kg @ PKR {(a.unit_cost_ppk / 100).toFixed(2)}/kg
                        </span>
                        <span className="font-mono tabular-nums">PKR {(a.cogs_paisa / 100).toLocaleString()}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <Field label="Dispatch note (optional)">
                <input type="text" value={dispatchNote} onChange={(e) => setDispatchNote(e.target.value)} placeholder="e.g. loaded on truck" className={inputCls} />
              </Field>

              </fieldset>

              <SaveControls
                safe={dispatchSafe}
                valid={dispatchValid && !saleSafe.locked}
                label="Record dispatch"
                onStartOver={clearDispatch}
                className="bg-indigo-600 hover:bg-indigo-700"
              />
            </form>
          )}
        </Card>
      )}
    </div>
  )
}
