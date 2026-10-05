import { useEffect, useMemo, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { engine } from '../lib/engine'
import type { BatchRow, CrushPreview, Product } from '../lib/types'
import { batchNames, leftAndCost, withStockOldestFirst } from '../lib/batches'
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
 * Crush Run: rock salt in → graded salt out + weighed wastage.
 * The father enters only weights and the conversion cost. The database prices every grade (cost pool by weight,
 * wastage its weight share); the preview is the database's own answer, so it can never differ from the save.
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
        const gradeable = p.filter((x) => x.form === 'bulk_processed')
        setGrades((g) => (g[0].productCode ? g : [{ ...g[0], productCode: gradeable[0]?.code ?? '' }]))
      })
      .catch(setLoadError)
    engine.supplierNames().then(setSuppliers).catch(() => setSuppliers([]))
  }, [])

  // crush grades come out; only rock salt goes in
  const gradeProducts = useMemo(() => products?.filter((p) => p.form === 'bulk_processed') ?? [], [products])
  const availableBatches = useMemo(() => {
    const rock = new Set(products?.filter((p) => p.form === 'raw').map((p) => p.code))
    return withStockOldestFirst(batches?.filter((b) => rock.has(b.product_code)) ?? [])
  }, [batches, products])
  const names = useMemo(() => batchNames(batches ?? []), [batches])
  const selectedBatch = batches?.find((b) => b.batch_code === inputBatch)

  const inputG = Math.round((Number(inputKg) || 0) * 1000)
  const wastageG = Math.round((Number(wastageKg) || 0) * 1000)
  const conversionP = Math.round((Number(conversionPkr) || 0) * 100)
  const gradeRows = grades.map((g) => ({ ...g, qtyG: Math.round((Number(g.qtyKg) || 0) * 1000) }))
  const outG = gradeRows.reduce((s, g) => s + g.qtyG, 0)

  const massOk = inputG > 0 && outG + wastageG === inputG
  const qtyWithinStock = !!selectedBatch && inputG <= selectedBatch.onhand_grams

  const gradesOk =
    gradeRows.every((g) => g.qtyG > 0 && !!g.productCode) && new Set(gradeRows.map((g) => g.productCode)).size === gradeRows.length
  const supplierOk = payCash || conversionP === 0 || supplier.trim().length > 0
  const valid = !!inputBatch && massOk && qtyWithinStock && gradesOk && supplierOk

  // The preview is the database's own calculation (the same function the save uses), asked again 0.4 s after typing stops.
  const previewKey = JSON.stringify([inputBatch, inputG, wastageG, conversionP, payCash, gradeRows.map((g) => [g.productCode, g.qtyG])])
  useEffect(() => {
    setPreview(null)
    setPreviewError(null)
    if (!inputBatch || !massOk || !qtyWithinStock || !gradesOk) return
    let alive = true
    const t = setTimeout(() => {
      engine
        .crushRunPreview({
          inputBatchCode: inputBatch,
          inputQtyKg: inputG / 1000,
          outputs: gradeRows.map((g) => ({ product_code: g.productCode, qty_kg: g.qtyG / 1000 })),
          wastageKg: wastageG / 1000,
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
    setInputKg('')
    setWastageKg('')
    setConversionPkr('')
    setGrades([{ key: (rowKey += 1), productCode: gradeProducts[0]?.code ?? '', qtyKg: '' }])
    setNote('')
    setSupplier('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    const res = await safe.save((key) =>
      engine.recordProcessRun({
        inputBatchCode: inputBatch,
        inputQtyKg: Number(inputKg),
        outputs: gradeRows.map((g) => ({ product_code: g.productCode, qty_kg: Number(g.qtyKg) || 0 })),
        wastageKg: Number(wastageKg) || 0,
        conversionCostPkr: Number(conversionPkr) || 0,
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
                  {names.get(b.batch_code) ?? b.batch_code} — {leftAndCost(b)}
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
                <span className="text-slate-600">
                  Cost pool PKR {(preview.pool_paisa / 100).toLocaleString()} — wastage share PKR {(preview.wastage_value_paisa / 100).toLocaleString()}, graded share PKR {(preview.graded_share_paisa / 100).toLocaleString()}
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
              <strong>Priced by the database:</strong> the grades share the cost by weight and wastage takes its weight
              share. These are the exact figures that will be saved.
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

