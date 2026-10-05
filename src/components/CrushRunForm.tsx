import { useEffect, useMemo, useState } from 'react'
import { engine } from '../lib/engine'
import type { BatchRow, CrushPreview, Product } from '../lib/types'
import { batchNames, leftAndCost, withStockOldestFirst } from '../lib/batches'
import { bagsLooseGrams, crushWastage } from '../lib/qty'
import { COST_KINDS, ELECTRICITY_PARTY, costPerKg, newCostDraft, paidNowPaisa, toCosts, type CostDraft } from '../lib/crushCosts'
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
  const [costRows, setCostRows] = useState<CostDraft[]>(() => [newCostDraft('labour')])
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
  const { costs, problems: costProblems, alreadyBookedPaisa } = toCosts(costRows)

  const qtyWithinStock = !!selectedBatch && inputG <= selectedBatch.onhand_grams
  const massOk = inputG > 0 && outG > 0 && !waste.over
  const valid = !!inputBatch && outputsKnown && massOk && qtyWithinStock && costProblems.length === 0

  // The preview is the database's own calculation (the same function the save uses), asked again 0.4 s after typing stops.
  const previewKey = JSON.stringify([inputBatch, inputG, fineG, daanaG, costs])
  useEffect(() => {
    setPreview(null)
    setPreviewError(null)
    if (!inputBatch || !outputsKnown || !massOk || !qtyWithinStock || costProblems.length > 0) return
    let alive = true
    const t = setTimeout(() => {
      engine
        .crushPreview({ inputBatchCode: inputBatch, inputQtyKg: inputG / 1000, outputs, wastageKg: waste.g / 1000, costs })
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
    setCostRows([newCostDraft('labour')])
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    // costs already in Money Out are only noted on the entry (not paid again, not in this salt's cost)
    const booked = alreadyBookedPaisa > 0 ? `Rs ${(alreadyBookedPaisa / 100).toLocaleString()} crushing cost already in Money Out, not in this cost per kg` : ''
    const res = await safe.save((key) =>
      engine.recordCrush({
        inputBatchCode: inputBatch,
        inputQtyKg: inputG / 1000,
        outputs,
        wastageKg: waste.g / 1000,
        costs,
        occurredOn: date,
        note: [note.trim(), booked].filter(Boolean).join('; ') || undefined,
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

        <CostTable rows={costRows} setRows={setCostRows} suppliers={suppliers} problems={costProblems} />

        <Field label="Note (optional)">
          <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. day shift" className={inputCls} />
        </Field>

        {previewError != null && <ErrorBanner error={previewError} />}
        {preview && (
          <>
            <Answer preview={preview} inputG={inputG} fineG={fineG} daanaG={daanaG} lossG={waste.g} lossPct={pct} alreadyBookedPaisa={alreadyBookedPaisa} />
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

/** Crushing cost, one line per cost; each line says how much is paid now and who is owed the rest. */
function CostTable({ rows, setRows, suppliers, problems }: {
  rows: CostDraft[]
  setRows: React.Dispatch<React.SetStateAction<CostDraft[]>>
  suppliers: string[]
  problems: string[]
}) {
  const set = (key: number, patch: Partial<CostDraft>) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)))
  return (
    <section className="space-y-3">
      <h3 className="text-base font-semibold text-slate-700">
        <Bi en="Crushing cost" ur="پسائی کا خرچ" />
      </h3>
      {rows.map((d) => {
        const amount = Number(d.amount) > 0 ? Math.round(Number(d.amount) * 100) : 0
        const paid = paidNowPaisa(d)
        const later = amount > 0 && paid >= 0 && paid <= amount ? amount - paid : 0
        return (
          <div key={d.key} className="space-y-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Field label="What / کس چیز کا">
                <select
                  value={d.kind}
                  onChange={(e) => {
                    const kind = e.target.value as CostDraft['kind']
                    // a new kind starts with its own default paid-now; electricity is owed to the bill by default
                    set(d.key, { kind, paidNow: '', paidEdited: false, owedTo: kind === 'electricity' && !d.owedTo ? ELECTRICITY_PARTY : d.owedTo })
                  }}
                  className={inputCls}
                >
                  {COST_KINDS.map((k) => (
                    <option key={k.kind} value={k.kind}>{k.en} / {k.ur}</option>
                  ))}
                </select>
              </Field>
              <Field label="Amount / رقم (Rs)">
                <input type="number" min="0" step="0.01" inputMode="decimal" value={d.amount} onChange={(e) => set(d.key, { amount: e.target.value })} className={inputCls} />
              </Field>
            </div>

            <label className="flex min-h-11 items-center gap-3 text-base text-slate-700">
              <input type="checkbox" checked={d.alreadyBooked} onChange={(e) => set(d.key, { alreadyBooked: e.target.checked })} className="h-5 w-5" />
              <span><Bi en="Already entered in Money Out" ur="پہلے ہی خرچ میں درج ہے" /></span>
            </label>

            {d.alreadyBooked ? (
              <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">
                Nothing is paid again and the cost per kg will not include this — next time enter it here instead.
              </p>
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Paid now / ابھی دیا (Rs)">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      inputMode="decimal"
                      value={d.paidEdited ? d.paidNow : amount > 0 ? String(paid / 100) : ''}
                      onChange={(e) => set(d.key, { paidNow: e.target.value, paidEdited: true })}
                      className={inputCls}
                    />
                  </Field>
                  <div>
                    <span className="mb-1.5 block text-base font-semibold text-slate-700">Rest later / باقی بعد میں</span>
                    <div className="flex min-h-11 items-center rounded-xl bg-white px-3 text-lg font-bold text-slate-900">{rs(later)}</div>
                  </div>
                </div>
                {later > 0 && (
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <Field label="Owed to / کس کو دینا ہے">
                      <input
                        type="text"
                        list="crush-suppliers"
                        value={d.owedTo}
                        onChange={(e) => set(d.key, { owedTo: e.target.value })}
                        placeholder="worker name, diesel pump…"
                        className={inputCls}
                      />
                    </Field>
                    <Field label="Expected date / کب دینا ہے (optional)">
                      <input type="date" value={d.expectedOn} onChange={(e) => set(d.key, { expectedOn: e.target.value })} className={inputCls} />
                    </Field>
                  </div>
                )}
              </>
            )}
            {d.kind === 'electricity' && (
              <p className="text-sm text-slate-600">
                Electricity: enter an estimate as “rest later” to {ELECTRICITY_PARTY}; when the real bill comes, pay it in full from
                Pay supplier — any extra goes to Utilities.
              </p>
            )}
            {rows.length > 1 && (
              <button
                type="button"
                onClick={() => setRows((rs) => rs.filter((r) => r.key !== d.key))}
                className="min-h-11 rounded-lg border border-slate-300 px-3 text-base font-semibold text-slate-700 hover:bg-white"
              >
                Remove this line / ہٹائیں
              </button>
            )}
          </div>
        )
      })}
      <datalist id="crush-suppliers">
        {suppliers.map((s) => <option key={s} value={s} />)}
      </datalist>
      <div className="flex flex-wrap gap-2">
        {COST_KINDS.map((k) => (
          <button
            key={k.kind}
            type="button"
            onClick={() => setRows((rs) => [...rs, newCostDraft(k.kind)])}
            className="min-h-11 rounded-lg border border-slate-300 bg-white px-3 text-sm font-semibold text-slate-700 hover:bg-slate-50"
          >
            + {k.en} / <span lang="ur" dir="rtl">{k.ur}</span>
          </button>
        ))}
      </div>
      {problems.map((p) => (
        <p key={p} role="alert" className="text-base font-semibold text-rose-700">{p}</p>
      ))}
    </section>
  )
}

/** The answer before Save: what the salt cost, per kg and per 50 kg bag (the database's own figures). */
function Answer({ preview, inputG, fineG, daanaG, lossG, lossPct, alreadyBookedPaisa }: {
  preview: CrushPreview
  inputG: number
  fineG: number
  daanaG: number
  lossG: number
  lossPct: string
  alreadyBookedPaisa: number
}) {
  const perKg = costPerKg(preview.pool_paisa, preview.output_grams)
  const rockPerKg = costPerKg(preview.input_value_paisa, inputG)
  const k = preview.costs
  const owedTo = k.owed.map((o) => `${o.name} ${rs(o.amount_paisa)}`).join(', ')
  const r2 = (n: number) => n.toLocaleString('en-PK', { maximumFractionDigits: 2 })
  return (
    <section className="space-y-2 rounded-2xl border-2 border-amber-300 bg-amber-50 p-4 text-base text-slate-800">
      <div>
        Rock used: <strong>{kgText(inputG)} kg × Rs {r2(rockPerKg)}/kg = {rs(preview.input_value_paisa)}</strong>
      </div>
      <div>
        Crushing cost: <strong>{rs(k.total_paisa)}</strong>
        <span className="block text-sm text-slate-600">
          paid now {rs(k.paid_now_paisa)} · pay later {rs(k.later_paisa)}{owedTo ? ` to ${owedTo}` : ''}
        </span>
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
          ({rs(preview.input_value_paisa)} + {rs(k.total_paisa)}) ÷ {kgText(preview.output_grams)} kg
        </div>
      </div>
      {alreadyBookedPaisa > 0 && (
        <p className="text-sm text-amber-900">
          {rs(alreadyBookedPaisa)} already in Money Out is not in this cost per kg.
        </p>
      )}
    </section>
  )
}
