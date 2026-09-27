import { useEffect, useMemo, useState } from 'react'
import { engine } from '../lib/engine'
import type { Location, Product } from '../lib/types'
import { SaveControls, useSafeSave } from './SafeSave'
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
 * Salt Purchase: engine creates the batch (BATCH-00n), posts Dr Inventory /
 * Cr Cash-or-AP, and logs a PURCHASE_RECEIPT movement. Preview updates live.
 */
export default function SaltPurchaseForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [supplier, setSupplier] = useState('')
  const [products, setProducts] = useState<Product[] | null>(null)
  const [locations, setLocations] = useState<Location[] | null>(null)
  const [productCode, setProductCode] = useState('')
  const [locationCode, setLocationCode] = useState('')
  const [qtyKg, setQtyKg] = useState('')
  const [costPkr, setCostPkr] = useState('')
  const [payCash, setPayCash] = useState(true)
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const [loadError, setLoadError] = useState<unknown>(null)

  useEffect(() => {
    Promise.all([engine.products(), engine.locations()])
      .then(([p, l]) => {
        setProducts(p)
        setProductCode((prev) => prev || p.find((x) => x.code === 'SALT_RAW')?.code || p[0]?.code || '')
        setLocations(l)
        setLocationCode((prev) => prev || l.find((x) => x.kind === 'plant')?.code || l[0]?.code || '')
      })
      .catch(setLoadError)
  }, [])

  const qty = Number(qtyKg)
  const cost = Number(costPkr)
  const qtyOk = Number.isFinite(qty) && qty > 0
  const costOk = Number.isFinite(cost) && cost > 0
  const perKg = qtyOk && costOk ? cost / qty : 0

  const invAccount = useMemo(() => {
    const form = products?.find((p) => p.code === productCode)?.form
    switch (form) {
      case 'raw': return '1200'
      case 'bulk_processed': return '1210'
      case 'packaged': return '1220'
      case 'packaging_material': return '1230'
      default: return '1500'
    }
  }, [products, productCode])

  const valid = supplier.trim().length > 0 && qtyOk && costOk && !!productCode && !!locationCode

  const lines = [
    { account: invAccount, debit: costOk ? Math.round(cost * 100) : 0 },
    { account: payCash ? '1000' : '2000', credit: costOk ? Math.round(cost * 100) : 0 },
  ]

  function clear() {
    setSupplier('')
    setQtyKg('')
    setCostPkr('')
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const res = await safe.save((key) =>
      engine.recordPurchase({
        supplier: supplier.trim(),
        productCode,
        locationCode,
        qtyKg: qty,
        landedCostPkr: cost,
        payCash,
        occurredOn: date,
        note: note.trim() || undefined,
        idempotencyKey: key,
      }),
    )
    if (res === null) return
    clear()
    onPosted()
  }

  return (
    <Card>
      <SectionTitle>Buy inventory</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        {loadError != null && <ErrorBanner error={loadError} />}
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date paid" value={date} onChange={setDate} />
          <Field label="Supplier">
            <input
              type="text"
              value={supplier}
              onChange={(e) => setSupplier(e.target.value)}
              placeholder="e.g. Malik Salt Traders, Khewra"
              className={inputCls}
              required
            />
          </Field>
        </div>

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="What kind of salt?">
            <select value={productCode} onChange={(e) => setProductCode(e.target.value)} className={inputCls} required>
              {products?.map((p) => (
                <option key={p.code} value={p.code}>{p.name}</option>
              ))}
            </select>
          </Field>
          <Field label="Delivered where?">
            <select value={locationCode} onChange={(e) => setLocationCode(e.target.value)} className={inputCls} required>
              {locations?.map((l) => (
                <option key={l.code} value={l.code}>{l.name}</option>
              ))}
            </select>
          </Field>
        </div>

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="Quantity (kg)" hint="Weighbridge or supplier slip figure.">
            <input
              type="number"
              min="1"
              step="1"
              inputMode="numeric"
              value={qtyKg}
              onChange={(e) => setQtyKg(e.target.value)}
              placeholder="e.g. 15000"
              className={inputCls}
              required
            />
          </Field>
          <Field label="Total landed cost (PKR)" hint="Purchase price + freight — everything paid to get it here.">
            <input
              type="number"
              min="1"
              step="0.01"
              inputMode="decimal"
              value={costPkr}
              onChange={(e) => setCostPkr(e.target.value)}
              placeholder="e.g. 114270"
              className={inputCls}
              required
            />
          </Field>
        </div>

        <Field label="How is it paid?">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {[
              { cash: true, title: 'Paid cash now', sub: 'Cash decreases immediately' },
              { cash: false, title: 'On credit (pay later)', sub: 'Supplier owed — appears in payables' },
            ].map((opt) => (
              <button
                key={opt.cash ? 'cash' : 'credit'}
                type="button"
                onClick={() => setPayCash(opt.cash)}
                className={`rounded-xl border-2 px-4 py-3 text-left transition ${
                  payCash === opt.cash
                    ? 'border-blue-500 bg-blue-50 ring-4 ring-blue-100'
                    : 'border-slate-200 bg-white hover:border-slate-300'
                }`}
              >
                <div className="text-base font-bold text-slate-800">{opt.title}</div>
                <div className="text-xs text-slate-500">{opt.sub}</div>
              </button>
            ))}
          </div>
        </Field>

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. truck no. LEA-4455, 2nd consignment" className={inputCls} />
        </Field>

        {qtyOk && costOk && (
          <div className="flex items-center gap-3 rounded-xl bg-blue-50 px-4 py-3 text-sm text-blue-800">
            <Badge tone="blue">Rate check</Badge>
            <span>
              Cost per kg: <strong>PKR {perKg.toFixed(2)}</strong>
              {perKg > 0 && perKg < 3 && ' — unusually low, double-check the numbers.'}
              {perKg > 20 && ' — unusually high for rock salt, double-check.'}
            </span>
          </div>
        )}

        <JournalPreview
          lines={lines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account),
            debit: l.debit || undefined,
            credit: l.credit || undefined,
          }))}
          okLabel="The engine creates the new batch, records the movement, and verifies balance before saving."
        />

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record purchase" onStartOver={clear} className="bg-indigo-600 hover:bg-indigo-700" />
      </form>
    </Card>
  )
}
