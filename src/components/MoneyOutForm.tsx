import { useEffect, useState } from 'react'
import { engine } from '../lib/engine'
import { Bi, Card, DateField, Field, inputCls, JournalPreview, SectionTitle, accountName, todayPK } from './ui'
import { SaveControls, useSafeSave } from './SafeSave'

type Group = 'plant' | 'spend' | 'asset'
type Category = { id: string; label: string; account: string; eventType: string; group: Group }

const GROUPS: { group: Group; label: string }[] = [
  { group: 'plant', label: 'Plant / پلانٹ — crushing plant bills' },
  { group: 'spend', label: 'Spending' },
  { group: 'asset', label: 'Something bought that keeps its value (asset)' },
]

const CATEGORIES: Category[] = [
  { id: 'plant_electricity', label: 'Plant electricity / پلانٹ بجلی', account: '5410', eventType: 'expense', group: 'plant' },
  { id: 'plant_labour', label: 'Plant labour / پلانٹ مزدوری', account: '5420', eventType: 'expense', group: 'plant' },
  { id: 'plant_diesel', label: 'Plant diesel & repairs / ڈیزل و مرمت', account: '5430', eventType: 'expense', group: 'plant' },
  { id: 'plant_other', label: 'Plant other / پلانٹ دیگر', account: '5440', eventType: 'expense', group: 'plant' },
  { id: 'labour', label: 'Labour', account: '5000', eventType: 'expense', group: 'spend' },
  { id: 'utilities', label: 'Utilities', account: '5100', eventType: 'expense', group: 'spend' },
  { id: 'fuel', label: 'Fuel', account: '5300', eventType: 'expense', group: 'spend' },
  { id: 'site', label: 'Site Meals & Welfare', account: '5500', eventType: 'expense', group: 'spend' },
  { id: 'travel', label: 'Travel', account: '5600', eventType: 'expense', group: 'spend' },
  { id: 'repairs', label: 'Repairs & Maintenance', account: '5700', eventType: 'expense', group: 'spend' },
  { id: 'admin', label: 'Admin & Office', account: '5800', eventType: 'expense', group: 'spend' },
  { id: 'other_biz', label: 'Other Business Expense', account: '5900', eventType: 'expense', group: 'spend' },
  { id: 'bike', label: 'Vehicle (1400)', account: '1400', eventType: 'asset_purchase', group: 'asset' },
  { id: 'goats', label: 'Livestock (1450)', account: '1450', eventType: 'asset_purchase', group: 'asset' },
  { id: 'equipment', label: 'Equipment / other assets (1500)', account: '1500', eventType: 'asset_purchase', group: 'asset' },
  { id: 'drawings', label: 'Owner Drawings (personal take-out)', account: '3100', eventType: 'drawings', group: 'spend' },
  { id: 'personal', label: 'Personal / Unclear — Suspense for review', account: '1900', eventType: 'expense', group: 'spend' },
]

export default function MoneyOutForm({ onPosted }: { onPosted: () => void }) {
  const [date, setDate] = useState(todayPK)
  const [categoryId, setCategoryId] = useState('') // no default: the type must be picked every time
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [onCredit, setOnCredit] = useState(false)
  const [supplier, setSupplier] = useState('')
  const [suppliers, setSuppliers] = useState<string[]>([])
  const safe = useSafeSave()

  useEffect(() => {
    engine.supplierNames().then(setSuppliers).catch(() => setSuppliers([]))
  }, [])

  const category = CATEGORIES.find((c) => c.id === categoryId)
  // only a plant bill can be left to pay later (to a supplier, paid from Pay supplier)
  const credit = onCredit && category?.group === 'plant'
  // hint only: a plant bill entered under ordinary spending
  const looksLikePlant = category?.group === 'spend' && ['labour', 'utilities', 'fuel', 'repairs'].includes(category.id)
    && /crush|plant|machine|پسائی|مشین|پلانٹ|چکی/i.test(description)
  const amountPaisa = (() => {
    const n = Number(amount)
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0
  })()
  const valid = !!category && amountPaisa > 0 && description.trim().length > 0 && (!credit || supplier.trim().length > 0)

  const lines = category
    ? [
        { account: category.account, debit: amountPaisa },
        credit ? { account: '2000', credit: amountPaisa, party: supplier.trim() } : { account: '1000', credit: amountPaisa },
      ]
    : []

  function clear() {
    setCategoryId('')
    setAmount('')
    setDescription('')
    setOnCredit(false)
    setSupplier('')
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid || !category) return
    const ref = await safe.save((key) =>
      engine.postEvent({
        eventType: category.eventType,
        occurredOn: date,
        description: description.trim(),
        lines,
        partyType: 'other',
        idempotencyKey: key,
      }),
    )
    if (ref === null) return
    clear()
    onPosted()
  }

  return (
    <Card>
      <SectionTitle>Record money out</SectionTitle>
      <form onSubmit={submit} className="space-y-5">
        <fieldset disabled={safe.locked} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DateField label="Date paid" value={date} onChange={setDate} />
          <Field label="What kind of spending?">
            <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className={inputCls} required>
              <option value="" disabled>Pick one…</option>
              {GROUPS.map((g) => (
                <optgroup key={g.group} label={g.label}>
                  {CATEGORIES.filter((c) => c.group === g.group).map((c) => (
                    <option key={c.id} value={c.id}>{c.label}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </Field>
        </div>

        <Field label="Amount (PKR)">
          <input
            type="number"
            min="1"
            step="0.01"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className={inputCls}
            required
          />
        </Field>

        <Field label="What was it for?" hint="Write it the way you'd say it — the engine records it word for word.">
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="e.g. Qasim weekly wages, bill house…"
            className={inputCls}
            required
          />
        </Field>

        {category?.group === 'plant' && (
          <fieldset className="space-y-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
            <legend className="px-1 text-base font-semibold text-slate-700"><Bi en="Paid how?" ur="ادائیگی کیسے؟" /></legend>
            <div className="grid grid-cols-2 gap-2">
              {[false, true].map((later) => (
                <label key={String(later)} className={`flex min-h-11 items-center gap-2 rounded-lg border px-3 text-base ${onCredit === later ? 'border-slate-900 bg-white font-semibold' : 'border-slate-300'}`}>
                  <input type="radio" name="paid-how" checked={onCredit === later} onChange={() => setOnCredit(later)} className="h-5 w-5" />
                  {later ? <Bi en="Pay later" ur="بعد میں" /> : <Bi en="Cash now" ur="ابھی نقد" />}
                </label>
              ))}
            </div>
            {credit && (
              <Field label="Owed to / کس کو دینا ہے" hint="Pay it later from Pay supplier.">
                <input type="text" list="moneyout-suppliers" value={supplier} onChange={(e) => setSupplier(e.target.value)} placeholder="e.g. MEPCO bijli bill, diesel pump…" className={inputCls} required />
                <datalist id="moneyout-suppliers">
                  {suppliers.map((n) => <option key={n} value={n} />)}
                </datalist>
              </Field>
            )}
          </fieldset>
        )}

        {looksLikePlant && (
          <p role="note" className="rounded-xl bg-amber-50 px-4 py-3 text-base text-amber-900">
            <Bi en="Plant bills go under Plant" ur="پلانٹ کے بل پلانٹ میں ڈالیں" />.
          </p>
        )}

        <JournalPreview
          lines={lines.map((l) => ({
            account: l.account,
            accountName: accountName(l.account) + ('party' in l && l.party ? ` — ${l.party}` : ''),
            debit: l.debit || undefined,
            credit: l.credit || undefined,
          }))}
        />

        </fieldset>

        <SaveControls safe={safe} valid={valid} label="Record it" onStartOver={clear} className="bg-slate-900 hover:bg-slate-700" />
      </form>
    </Card>
  )
}
