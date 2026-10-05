import { useEffect, useMemo, useState } from 'react'
import { engine } from '../lib/engine'
import type { BatchRow, CrushPreview, Product } from '../lib/types'
import { batchNames, leftAndCost, withStockOldestFirst } from '../lib/batches'
import { bagsLooseGrams, crushWastage } from '../lib/qty'
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
 * Crush Run: rock salt in → Fine and/or Daana out, counted in 50 kg bags + loose kg.
 * Wastage is what is left over: rock used − (fine + daana). The database prices every output (cost pool by weight,
 * wastage its weight share) and makes each output its own batch; the preview is the database's own answer, so it can
 * never differ from the save.
 */

const FINE = 'SALT_BULK'
const DAANA = 'SALT_ROCK_COARSE'
const kgText = (g: number) => (g / 1000).toLocaleString('en-PK', { maximumFractionDigits: 3 })

function BagsLoose({ label, bags, loose, onBags, onLoose, hint }: {
  label: string
  bags: string
  loose: string
  onBags: (v: string) => void
  onLoose: (v: string) => void
  hint?: string
}) {
  return (
    <fieldset className="rounded-xl border border-slate-200 bg-slate-50 p-3">
      <legend className="px-1 text-base font-semibold text-slate-700">{label}</legend>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Bags of 50 kg">
          <input type="number" min="0" step="1" inputMode="numeric" value={bags} onChange={(e) => onBags(e.target.value)} placeholder="0" className={inputCls} />
        </Field>
        <Field label="+ loose kg">
          <input type="number" min="0" step="0.001" inputMode="decimal" value={loose} onChange={(e) => onLoose(e.target.value)} placeholder="0" className={inputCls} />
        </Field>
      </div>
      <p className="mt-2 text-base text-slate-700">
        = <strong>{kgText(bagsLooseGrams(bags, loose))} kg</strong>
        {hint && <span className="text-slate-500"> · {hint}</span>}
      </p>
    </fieldset>
  )
}

export default function CrushRunForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [batches, setBatches] = useState<BatchRow[] | null>(null)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [inputBatch, setInputBatch] = useState('')
  const [rockBags, setRockBags] = useState('')
  const [rockLoose, setRockLoose] = useState('')
  const [fineBags, setFineBags] = useState('')
  const [fineLoose, setFineLoose] = useState('')
  const [daanaBags, setDaanaBags] = useState('')
  const [daanaLoose, setDaanaLoose] = useState('')
  const [conversionPkr, setConversionPkr] = useState('')
  const [payCash, setPayCash] = useState(true)
  const [supplier, setSupplier] = useState('')
  const [suppliers, setSuppliers] = useState<string[]>([])
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const [loadError, setLoadError] = useState<unknown>(null)
  const [preview, setPreview] = useState<CrushPreview | null>(null)
  const [previewError, setPreviewError] = useState<unknown>(null)

  useEffect(() => {
    Promise.all([engine.batches(), engine.products()])
      .then(([b, p]) => {
        setBatches(b)
        setProducts(p)
      })
      .catch(setLoadError)
    engine.supplierNames().then(setSuppliers).catch(() => setSuppliers([]))
  }, [])

  // only rock salt goes in; Fine and Daana come out
  const availableBatches = useMemo(() => {
    const rock = new Set(products?.filter((p) => p.form === 'raw').map((p) => p.code))
    return withStockOldestFirst(batches?.filter((b) => rock.has(b.product_code)) ?? [])
  }, [batches, products])
  const names = useMemo(() => batchNames(batches ?? []), [batches])
  const selectedBatch = batches?.find((b) => b.batch_code === inputBatch)
  const outputsKnown = !!products && [FINE, DAANA].every((c) => products.some((p) => p.code === c))

  const inputG = bagsLooseGrams(rockBags, rockLoose)
  const fineG = bagsLooseGrams(fineBags, fineLoose)
  const daanaG = bagsLooseGrams(daanaBags, daanaLoose)
  const outG = fineG + daanaG
  const waste = crushWastage(inputG, outG)
  const outputs = [
    { product_code: FINE, qty_kg: fineG / 1000 },
    { product_code: DAANA, qty_kg: daanaG / 1000 },
  ].filter((o) => o.qty_kg > 0)
  const conversionP = Math.round((Number(conversionPkr) || 0) * 100)

  const qtyWithinStock = !!selectedBatch && inputG <= selectedBatch.onhand_grams
  const massOk = inputG > 0 && outG > 0 && !waste.over
  const supplierOk = payCash || conversionP === 0 || supplier.trim().length > 0
  const valid = !!inputBatch && outputsKnown && massOk && qtyWithinStock && supplierOk

  // The preview is the database's own calculation (the same function the save uses), asked again 0.4 s after typing stops.
  const previewKey = JSON.stringify([inputBatch, inputG, fineG, daanaG, conversionP, payCash])
  useEffect(() => {
    setPreview(null)
    setPreviewError(null)
    if (!inputBatch || !outputsKnown || !massOk || !qtyWithinStock) return
    let alive = true
    const t = setTimeout(() => {
      engine
        .crushRunPreview({
          inputBatchCode: inputBatch,
          inputQtyKg: inputG / 1000,
          outputs,
          wastageKg: waste.g / 1000,
          conversionCostPkr: conversionP / 100,
          payCash,
        })
        .then((p) => alive && setPreview(p))
        .catch((e) => alive && setPreviewError(e))
    }, 400)
    return () => {
      alive = false
      clearTimeout(t)
    }
  }, [previewKey]) // eslint-disable-line react-hooks/exhaustive-deps

  function clear() {
    for (const set of [setRockBags, setRockLoose, setFineBags, setFineLoose, setDaanaBags, setDaanaLoose, setConversionPkr, setNote, setSupplier]) set('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const res = await safe.save((key) =>
      engine.recordProcessRun({
        inputBatchCode: inputBatch,
        inputQtyKg: inputG / 1000,
        outputs,
        wastageKg: waste.g / 1000,
        conversionCostPkr: conversionP / 100,
        payCash,
        supplier: payCash ? undefined : supplier.trim() || undefined,
        occurredOn: date,
        note: note.trim() || undefined,
        idempotencyKey: key,
      }),
    )
    if (res === null) return
    clear()
    onPosted()
  }

  const pct = waste.pct.toLocaleString('en-PK', { maximumFractionDigits: 1 })

  return (
    <Card>
      <SectionTitle>Crush salt — rock in, Fine and Daana out</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        {loadError != null && <ErrorBanner error={loadError} />}
        {products && !outputsKnown && <ErrorBanner error="Fine or Daana is missing from the product list — tell Rao before crushing." />}
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date" value={date} onChange={setDate} />
          <Field label="Crush which rock batch?">
            <select value={inputBatch} onChange={(e) => setInputBatch(e.target.value)} className={inputCls} required>
              <option value="" disabled>Choose a batch with stock…</option>
              {availableBatches.map((b) => (
                <option key={b.batch_code} value={b.batch_code}>
                  {names.get(b.batch_code) ?? b.batch_code} — {leftAndCost(b)}
                </option>
              ))}
            </select>
          </Field>
        </div>

        <BagsLoose
          label="Rock used"
          bags={rockBags}
          loose={rockLoose}
          onBags={setRockBags}
          onLoose={setRockLoose}
          hint={selectedBatch ? `${kgText(selectedBatch.onhand_grams)} kg in this batch` : undefined}
        />
        {selectedBatch && !qtyWithinStock && (
          <p role="alert" className="text-base font-semibold text-rose-700">
            Only {kgText(selectedBatch.onhand_grams)} kg in that batch — reduce the rock used.
          </p>
        )}

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <BagsLoose label="Fine out" bags={fineBags} loose={fineLoose} onBags={setFineBags} onLoose={setFineLoose} />
          <BagsLoose label="Daana (coarse) out" bags={daanaBags} loose={daanaLoose} onBags={setDaanaBags} onLoose={setDaanaLoose} />
        </div>

        {inputG > 0 && outG > 0 && (
          waste.over ? (
            <p role="alert" className="rounded-xl border-2 border-rose-300 bg-rose-50 p-3 text-base font-semibold text-rose-900">
              Fine + Daana ({kgText(outG)} kg) is more than the rock used ({kgText(inputG)} kg). Check the counts — this cannot be saved.
            </p>
          ) : (
            <div className="rounded-xl bg-slate-100 p-3 text-base text-slate-800">
              Output <strong>{kgText(outG)} kg</strong> · wastage <strong>{kgText(waste.g)} kg ({pct}%)</strong>
              {(waste.g === 0 || waste.pct > 10) && (
                <p role="alert" className="mt-2 rounded-lg bg-amber-50 px-3 py-2 font-semibold text-amber-900">
                  {waste.g === 0
                    ? '⚠ No wastage at all — did you weigh/count everything? You can still save.'
                    : `⚠ Wastage is over 10% (${pct}%) — did you weigh/count everything? You can still save.`}
                </p>
              )}
            </div>
          )
        )}

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="Crushing cost (Rs)" hint="Crushing labour, electricity, machine diesel for this run.">
            <input
              type="number"
              min="0"
              step="0.01"
              inputMode="decimal"
              value={conversionPkr}
              onChange={(e) => setConversionPkr(e.target.value)}
              placeholder="e.g. 5000"
              className={inputCls}
            />
          </Field>
          <Field label="How is the crushing cost paid?">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {[
                { cash: true, title: 'Paid now (cash)' },
                { cash: false, title: 'On credit' },
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
                </button>
              ))}
            </div>
          </Field>
        </div>

        {!payCash && (
          <Field label="Who is owed the crushing cost?" hint="Pick from the list or type a new name (the crushing contractor).">
            <input
              type="text"
              list="crush-suppliers"
              value={supplier}
              onChange={(e) => setSupplier(e.target.value)}
              placeholder="e.g. Shida crusher"
              className={inputCls}
              required={conversionP > 0}
            />
            <datalist id="crush-suppliers">
              {suppliers.map((s) => <option key={s} value={s} />)}
            </datalist>
          </Field>
        )}

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. day shift" className={inputCls} />
        </Field>

        {previewError != null && <ErrorBanner error={previewError} />}
        {preview && (
          <>
            <div className="rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-800">
              <strong>Priced by the database:</strong> Fine and Daana share the cost by weight and wastage takes its weight
              share (cost pool Rs {(preview.pool_paisa / 100).toLocaleString()}, wastage Rs {(preview.wastage_value_paisa / 100).toLocaleString()}).
              Each output becomes its own batch, crushed in-house from this rock batch.
            </div>
            <JournalPreview
              lines={preview.lines.map((l) => ({
                account: l.account,
                accountName: accountName(l.account),
                debit: l.debit || undefined,
                credit: l.credit || undefined,
              }))}
              okLabel="Worked out by the database — the save uses the same calculation."
            />
          </>
        )}

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record crush run" onStartOver={clear} className="bg-amber-600 hover:bg-amber-700" />
      </form>
    </Card>
  )
}
