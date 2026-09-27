import { useEffect, useMemo, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { engine } from '../lib/engine'
import type { BatchRow, Product } from '../lib/types'
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
 * Crush Run: raw/bulk salt in → graded salt out + weighed wastage.
 * The father enters only weights and the conversion cost; the engine prices
 * every grade by weight-share (AUTO mode) and enforces mass + cost conservation.
 * The preview mirrors the engine's exact formulas; the database recomputes
 * and blocks the save if anything disagrees.
 */

type GradeRow = { key: number; productCode: string; qtyKg: string }

let rowKey = 1

export default function CrushRunForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [batches, setBatches] = useState<BatchRow[] | null>(null)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [inputBatch, setInputBatch] = useState('')
  const [inputKg, setInputKg] = useState('')
  const [grades, setGrades] = useState<GradeRow[]>([{ key: 0, productCode: '', qtyKg: '' }])
  const [wastageKg, setWastageKg] = useState('')
  const [conversionPkr, setConversionPkr] = useState('')
  const [payCash, setPayCash] = useState(true)
  const [note, setNote] = useState('')
  const safe = useSafeSave()
  const [loadError, setLoadError] = useState<unknown>(null)

  useEffect(() => {
    Promise.all([engine.batches(), engine.products()])
      .then(([b, p]) => {
        setBatches(b)
        setProducts(p)
        const gradeable = p.filter((x) => x.form === 'bulk_processed' || x.form === 'packaged')
        setGrades((g) => (g[0].productCode ? g : [{ ...g[0], productCode: gradeable[0]?.code ?? '' }]))
      })
      .catch(setLoadError)
  }, [])

  const gradeProducts = useMemo(
    () => products?.filter((p) => p.form === 'bulk_processed' || p.form === 'packaged') ?? [],
    [products],
  )
  const availableBatches = useMemo(
    () => batches?.filter((b) => b.onhand_grams > 0) ?? [],
    [batches],
  )
  const selectedBatch = batches?.find((b) => b.batch_code === inputBatch)

  const inputG = Math.round((Number(inputKg) || 0) * 1000)
  const wastageG = Math.round((Number(wastageKg) || 0) * 1000)
  const conversionP = Math.round((Number(conversionPkr) || 0) * 100)
  const gradeRows = grades.map((g) => ({ ...g, qtyG: Math.round((Number(g.qtyKg) || 0) * 1000) }))
  const outG = gradeRows.reduce((s, g) => s + g.qtyG, 0)

  const massOk = inputG > 0 && outG + wastageG === inputG
  const qtyWithinStock = !!selectedBatch && inputG <= selectedBatch.onhand_grams

  /* ---- mirror of the engine's pricing formulas (for the live preview) ---- */
  const preview = useMemo(() => {
    if (!selectedBatch || !qtyWithinStock || inputG <= 0) return null
    const onhand = selectedBatch.onhand_grams
    const bookValue = selectedBatch.value_paisa
    const inputValue = onhand > 0 ? Math.round((bookValue * inputG) / onhand) : 0
    const pool = inputValue + conversionP
    const wastValue =
      wastageG > 0 ? Math.round((pool * wastageG) / (wastageG + outG)) : 0
    const remaining = pool - wastValue

    // AUTO weight-share, cumulative rounding — identical to the engine
    let cumG = 0
    let assignedCum = 0
    const values: number[] = []
    gradeRows.forEach((g, i) => {
      cumG += g.qtyG
      const assigned =
        i < gradeRows.length - 1
          ? Math.round((remaining * cumG) / outG)
          : remaining - assignedCum
      assignedCum += assigned
      values.push(assigned)
    })

    const invIn = accountFor(products?.find((x) => x.code === selectedBatch.product_code)?.form, products)
    const lineList = [
      { account: invIn, debit: undefined as number | undefined, credit: inputValue },
    ]
    gradeRows.forEach((g, i) => {
      const p = products?.find((x) => x.code === g.productCode)
      lineList.push({ account: accountFor(p?.form, products), debit: values[i], credit: undefined })
    })
    if (wastValue > 0) {
      lineList.push({ account: '5250', debit: wastValue, credit: undefined })
    }
    if (conversionP > 0) {
      lineList.push({ account: payCash ? '1000' : '2000', debit: undefined, credit: conversionP })
    }
    return { lineList, inputValue, pool, wastValue, values }
  }, [selectedBatch, inputG, outG, wastageG, conversionP, payCash, products, qtyWithinStock]) // eslint-disable-line react-hooks/exhaustive-deps

  const valid =
    !!inputBatch &&
    massOk &&
    qtyWithinStock &&
    gradeRows.every((g) => g.qtyG > 0 && !!g.productCode) &&
    new Set(gradeRows.map((g) => g.productCode)).size === gradeRows.length

  function clear() {
    setInputKg('')
    setWastageKg('')
    setConversionPkr('')
    setGrades([{ key: (rowKey += 1), productCode: gradeProducts[0]?.code ?? '', qtyKg: '' }])
    setNote('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const res = await safe.save((key) =>
      engine.recordProcessRun({
        inputBatchCode: inputBatch,
        inputQtyKg: Number(inputKg),
        outputs: gradeRows.map((g) => ({
          product_code: g.productCode,
          qty_kg: Number(g.qtyKg) || 0,
          value_pkr: 0, // AUTO pricing — engine prices by weight-share
        })),
        wastageKg: Number(wastageKg) || 0,
        conversionCostPkr: Number(conversionPkr) || 0,
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
      <SectionTitle>Crush salt — raw in, graded out</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        {loadError != null && <ErrorBanner error={loadError} />}
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date" value={date} onChange={setDate} />
          <Field label="Crush which batch?">
            <select value={inputBatch} onChange={(e) => setInputBatch(e.target.value)} className={inputCls} required>
              <option value="" disabled>Choose a batch with stock…</option>
              {availableBatches.map((b) => (
                <option key={b.batch_code} value={b.batch_code}>
                  {b.batch_code} — {b.product_name}, {(b.onhand_grams / 1000).toLocaleString()} kg, {b.location_name}
                </option>
              ))}
            </select>
          </Field>
        </div>

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="How many kg go in?" hint={selectedBatch ? `Available: ${(selectedBatch.onhand_grams / 1000).toLocaleString()} kg` : undefined}>
            <input
              type="number"
              min="1"
              step="1"
              inputMode="numeric"
              value={inputKg}
              onChange={(e) => setInputKg(e.target.value)}
              placeholder="e.g. 10000"
              className={inputCls}
              required
            />
          </Field>
          <Field label="Weighed wastage (kg)" hint="Stone, dust, moisture loss — as measured on the scale.">
            <input
              type="number"
              min="0"
              step="1"
              inputMode="numeric"
              value={wastageKg}
              onChange={(e) => setWastageKg(e.target.value)}
              placeholder="e.g. 200"
              className={inputCls}
            />
          </Field>
        </div>

        {/* grade output rows */}
        <div>
          <div className="mb-2 flex items-center justify-between">
            <span className="text-base font-semibold text-slate-700">Output grades (kg out)</span>
            <button
              type="button"
              onClick={() => setGrades((g) => [...g, { key: (rowKey += 1), productCode: gradeProducts[0]?.code ?? '', qtyKg: '' }])}
              className="inline-flex min-h-11 items-center gap-1 rounded-lg border border-slate-300 px-3 text-sm font-semibold text-slate-700 hover:bg-slate-50"
            >
              <Plus className="h-4 w-4" /> Add grade
            </button>
          </div>
          <div className="space-y-3">
            {gradeRows.map((g, i) => (
              <div key={g.key} className="grid grid-cols-1 gap-3 sm:grid-cols-[1fr_1fr_auto]">
                <select
                  value={g.productCode}
                  onChange={(e) =>
                    setGrades((rows) => rows.map((r) => (r.key === g.key ? { ...r, productCode: e.target.value } : r)))
                  }
                  className={inputCls}
                >
                  <option value="" disabled>Grade…</option>
                  {gradeProducts.map((p) => (
                    <option key={p.code} value={p.code}>{p.name}</option>
                  ))}
                </select>
                <input
                  type="number"
                  min="1"
                  step="1"
                  inputMode="numeric"
                  value={g.qtyKg}
                  onChange={(e) =>
                    setGrades((rows) => rows.map((r) => (r.key === g.key ? { ...r, qtyKg: e.target.value } : r)))
                  }
                  placeholder="kg out"
                  className={inputCls}
                />
                <button
                  type="button"
                  onClick={() => setGrades((rows) => (rows.length > 1 ? rows.filter((r) => r.key !== g.key) : rows))}
                  className="flex min-h-11 min-w-11 items-center justify-center rounded-xl border border-slate-300 px-3 text-slate-600 hover:bg-rose-50 hover:text-rose-600"
                  aria-label="Remove grade row"
                >
                  <Trash2 className="h-5 w-5" />
                </button>
              </div>
            ))}
          </div>
          {outG > 0 && (
            <div className="mt-3 flex flex-wrap items-center gap-3 text-sm">
              <Badge tone={massOk ? 'emerald' : 'rose'}>
                {massOk ? 'Mass checks out ✓' : `Mismatch: ${((outG + wastageG) / 1000).toLocaleString()} kg out vs ${(inputG / 1000).toLocaleString()} kg in`}
              </Badge>
              {preview && (
                <span className="text-slate-500">
                  Cost pool PKR {((preview.pool) / 100).toLocaleString()} — wastage share PKR {(preview.wastValue / 100).toLocaleString()}, graded share PKR {(preview.pool - preview.wastValue) / 100 > 0 ? ((preview.pool - preview.wastValue) / 100).toLocaleString() : '0'}
                </span>
              )}
            </div>
          )}
          {selectedBatch && !qtyWithinStock && (
            <div className="mt-2 text-sm font-semibold text-rose-600">
              Only {(selectedBatch.onhand_grams / 1000).toLocaleString()} kg in that batch — reduce the input quantity.
            </div>
          )}
        </div>

        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <Field label="Conversion cost (PKR)" hint="Crushing labour, electricity, machine diesel for this run.">
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
          <Field label="How is the conversion cost paid?">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {[
                { cash: true, title: 'Cash now' },
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

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. day shift, mesh 30 run" className={inputCls} />
        </Field>

        {preview && (
          <>
            <div className="rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-800">
              <strong>Engine pricing:</strong> grades are priced by weight automatically. No need to enter any rupee
              values for the grades — the database computes them and blocks the save if anything disagrees.
            </div>
            <JournalPreview
              lines={preview.lineList.map((l) => ({
                account: l.account,
                accountName: accountName(l.account),
                debit: l.debit,
                credit: l.credit,
              }))}
              okLabel="The engine re-prices everything server-side; these figures use the identical formulas."
            />
          </>
        )}

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record crush run" onStartOver={clear} className="bg-amber-600 hover:bg-amber-700" />
      </form>
    </Card>
  )
}

function accountFor(productForm: string | undefined, products: Product[] | undefined): string {
  const form =
    productForm ??
    products?.find((p) => p.form === 'bulk_processed')?.form // fallback shouldn't happen
  switch (form) {
    case 'raw': return '1200'
    case 'bulk_processed': return '1210'
    case 'packaged': return '1220'
    case 'packaging_material': return '1230'
    default: return '1500'
  }
}
