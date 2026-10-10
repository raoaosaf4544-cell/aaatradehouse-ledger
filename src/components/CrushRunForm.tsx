import { useEffect, useMemo, useState } from 'react'
import { engine } from '../lib/engine'
import type { BatchRow, CrushPreview, Product } from '../lib/types'
import { batchNames, leftAndCost, withStockOldestFirst } from '../lib/batches'
import { bagsLooseGrams, crushWastage } from '../lib/qty'
import { costPerKg } from '../lib/crushCosts'
import { SaveControls, useSafeSave } from './SafeSave'
import {
  Bi,
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
  const [rate, setRate] = useState('')
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
    // start from the rate used last time (blank before the first crush)
    engine.lastCrushRate().then((r) => r != null && setRate((cur) => cur || String(r))).catch(() => {})
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
  const rateNum = Number(rate)
  const rateOk = rate.trim() !== '' && Number.isFinite(rateNum) && rateNum >= 0

  const qtyWithinStock = !!selectedBatch && inputG <= selectedBatch.onhand_grams
  const massOk = inputG > 0 && outG > 0 && !waste.over
  const valid = !!inputBatch && outputsKnown && massOk && qtyWithinStock && rateOk

  // The preview is the database's own calculation (the same function the save uses), asked again 0.4 s after typing stops.
  const previewKey = JSON.stringify([inputBatch, inputG, fineG, daanaG, rateNum])
  useEffect(() => {
    setPreview(null)
    setPreviewError(null)
    if (!inputBatch || !outputsKnown || !massOk || !qtyWithinStock || !rateOk) return
    let alive = true
    const t = setTimeout(() => {
      engine
        .crushPreview({ inputBatchCode: inputBatch, inputQtyKg: inputG / 1000, outputs, wastageKg: waste.g / 1000, ratePkrPerKg: rateNum })
        .then((p) => alive && setPreview(p))
        .catch((e) => alive && setPreviewError(e))
    }, 400)
    return () => {
      alive = false
      clearTimeout(t)
    }
  }, [previewKey]) // eslint-disable-line react-hooks/exhaustive-deps

  function clear() {
    for (const set of [setRockBags, setRockLoose, setFineBags, setFineLoose, setDaanaBags, setDaanaLoose, setNote]) set('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const res = await safe.save((key) =>
      engine.recordCrush({
        inputBatchCode: inputBatch,
        inputQtyKg: inputG / 1000,
        outputs,
        wastageKg: waste.g / 1000,
        ratePkrPerKg: rateNum,
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

        <Field label="Crushing rate / پسائی ریٹ (Rs per kg of rock)">
          <input type="number" min="0" step="0.01" inputMode="decimal" value={rate} onChange={(e) => setRate(e.target.value)} placeholder="e.g. 2" className={inputCls} required />
        </Field>
        <p className="-mt-3 text-sm text-slate-600">
          Our own plant: no cash moves here. The real plant bills (electricity, workers, diesel) go in Money Out as usual.
        </p>

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. day shift" className={inputCls} />
        </Field>

        {previewError != null && <ErrorBanner error={previewError} />}
        {preview && (
          <>
            <Answer preview={preview} inputG={inputG} fineG={fineG} daanaG={daanaG} lossG={waste.g} lossPct={pct} />
            <JournalPreview
              lines={preview.lines.map((l) => ({
                account: l.account,
                accountName: accountName(l.account) + (l.party ? ` — ${l.party}` : ''),
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

const rs = (paisa: number) => `Rs ${(paisa / 100).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`

/** The answer before Save: what the salt cost, per kg and per 50 kg bag (the database's own figures). */
function Answer({ preview, inputG, fineG, daanaG, lossG, lossPct }: {
  preview: CrushPreview
  inputG: number
  fineG: number
  daanaG: number
  lossG: number
  lossPct: string
}) {
  const perKg = costPerKg(preview.pool_paisa, preview.output_grams)
  const rockPerKg = costPerKg(preview.input_value_paisa, inputG)
  const r2 = (n: number) => n.toLocaleString('en-PK', { maximumFractionDigits: 2 })
  return (
    <section className="space-y-2 rounded-2xl border-2 border-amber-300 bg-amber-50 p-4 text-base text-slate-800">
      <div>
        Rock used: <strong>{kgText(inputG)} kg × Rs {r2(rockPerKg)}/kg = {rs(preview.input_value_paisa)}</strong>
      </div>
      <div>
        Plant cost: <strong>{kgText(inputG)} kg × Rs {r2(preview.rate_paisa_per_kg / 100)}/kg = {rs(preview.plant_cost_paisa)}</strong>
      </div>
      <div>
        Good salt out: Fine {kgText(fineG)} kg + Daana {kgText(daanaG)} kg = <strong>{kgText(preview.output_grams)} kg</strong>
        <span className="block text-sm text-slate-600">loss {kgText(lossG)} kg ({lossPct}%) — inside the cost below</span>
      </div>
      <div className="rounded-xl bg-white p-3 text-center">
        <div className="text-sm font-semibold text-slate-600">
          <Bi en="Cost per kg of crushed salt" ur="فی کلو لاگت" />
        </div>
        <div className="text-3xl font-bold text-amber-800">Rs {r2(perKg)}</div>
        <div className="text-base text-slate-700">Rs {r2(perKg * 50)} per 50 kg bag</div>
        <div className="mt-1 text-xs text-slate-500">
          ({rs(preview.input_value_paisa)} + {rs(preview.plant_cost_paisa)}) ÷ {kgText(preview.output_grams)} kg
        </div>
      </div>
    </section>
  )
}
