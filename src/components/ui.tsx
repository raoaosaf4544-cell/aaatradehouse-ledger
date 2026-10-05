import React, { useCallback, useEffect, useRef, useState } from 'react'
import { paisaToPkr, gramsToKg } from '../lib/types'
import { PAGE_SIZE } from '../lib/engine'
import { friendlyMessage, type ErrorKind } from '../lib/friendly'

export function Money({ paisa, className = '' }: { paisa: number; className?: string }) {
  const negative = paisa < 0
  return (
    <span className={`font-mono tabular-nums text-[max(0.875rem,1em)] ${negative ? 'text-rose-600' : ''} ${className}`}>
      {negative ? '−' : ''}PKR {paisaToPkr(Math.abs(paisa))}
    </span>
  )
}

export function Kg({ grams, className = '' }: { grams: number; className?: string }) {
  return <span className={`font-mono tabular-nums ${className}`}>{gramsToKg(grams)} kg</span>
}

export function Card({
  children,
  className = '',
}: {
  children: React.ReactNode
  className?: string
}) {
  return (
    <div className={`bg-white rounded-xl border border-slate-200 shadow-sm p-5 ${className}`}>
      {children}
    </div>
  )
}

export function StatCard({
  label,
  sub,
  children,
  tone = 'slate',
  onClick,
}: {
  label: string
  sub?: string
  children: React.ReactNode
  tone?: 'slate' | 'emerald' | 'amber' | 'rose' | 'blue'
  /** makes the whole card a button (e.g. open the screen behind the figure) */
  onClick?: () => void
}) {
  const tones: Record<string, string> = {
    slate: 'text-slate-900',
    emerald: 'text-emerald-700',
    amber: 'text-amber-700',
    rose: 'text-rose-700',
    blue: 'text-blue-700',
  }
  const body = (
    <Card>
      <div className="text-xs uppercase tracking-wide text-slate-500 font-semibold">{label}</div>
      <div className={`mt-2 text-2xl font-bold ${tones[tone]}`}>{children}</div>
      {sub && <div className="mt-1 text-sm text-slate-500">{sub}</div>}
    </Card>
  )
  return onClick ? (
    <button type="button" onClick={onClick} className="block w-full rounded-2xl text-left transition hover:brightness-95">
      {body}
    </button>
  ) : (
    body
  )
}

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500 mb-3">
      {children}
    </h2>
  )
}

/** Plain-language error box. Raw database text is never shown (lib/friendly.ts). */
export function ErrorBanner({ error, onDismiss, kind = 'load' }: { error: unknown; onDismiss?: () => void; kind?: ErrorKind }) {
  const message = friendlyMessage(error, kind)
  const title = typeof error === 'string' ? 'Check this' : kind === 'save' ? 'Not saved' : 'Could not load'
  return (
    <div className="mb-4 flex items-start gap-3 rounded-xl border border-rose-200 bg-rose-50 p-4">
      <div className="mt-0.5 h-2 w-2 shrink-0 rounded-full bg-rose-500" />
      <div className="min-w-0 flex-1">
        <div className="text-base font-bold text-rose-800">{title}</div>
        <div className="mt-1 break-words text-base text-rose-800">{message}</div>
      </div>
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="min-h-11 shrink-0 rounded-lg border border-rose-300 px-3 text-sm font-semibold text-rose-800 hover:bg-rose-100"
        >
          Dismiss
        </button>
      )}
    </div>
  )
}

export function Spinner({ label = 'Loading from database…' }: { label?: string }) {
  return (
    <div className="flex items-center gap-3 text-slate-500">
      <span className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-slate-600" />
      <span className="text-sm">{label}</span>
    </div>
  )
}

export function EmptyState({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-500">
      {children}
    </div>
  )
}

/* ---------- form kit: big, father-proof fields ---------- */

export function Field({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-base font-semibold text-slate-700">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-sm text-slate-600">{hint}</span>}
    </label>
  )
}

/** Today's date (YYYY-MM-DD) in Pakistan time — UTC would give yesterday between midnight and 5 am. */
export const todayPK = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Karachi' })

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
/** "2026-09-27" → "Sun 27 Sep 2026" */
export function dateInWords(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  if (!y || !m || !d) return ''
  return `${DAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]} ${d} ${MONTHS[m - 1]} ${y}`
}

/** The date box every entry form puts first: label, the date in words, and "change if not today". */
/** The first day of the books; the database refuses entries before it (and after today). */
export const BOOKS_START = '2026-08-23'

export function DateField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const today = todayPK()
  const outside = !!value && (value < BOOKS_START || value > today)
  return (
    <label className="block">
      <span className="mb-1.5 block text-base font-semibold text-slate-700">{label}</span>
      <input type="date" value={value} min={BOOKS_START} max={today} onChange={(e) => onChange(e.target.value)} className={inputCls} required />
      <span className={`mt-1.5 block text-sm ${outside ? 'font-semibold text-rose-700' : 'text-slate-600'}`}>
        {outside ? (
          <>Pick a day from {dateInWords(BOOKS_START)} to today — {value > today ? 'that day is in the future' : 'the books start on 23 Aug 2026'}.</>
        ) : (
          <><span className="font-semibold text-slate-900">{dateInWords(value)}</span> — change if not today</>
        )}
      </span>
    </label>
  )
}

export const inputCls =
  'w-full rounded-xl border-2 border-slate-300 bg-white px-4 py-3 text-lg text-slate-900 placeholder:text-slate-500 focus:border-blue-500 focus:outline-none focus:ring-4 focus:ring-blue-100'

export function Badge({
  children,
  tone = 'slate',
}: {
  children: React.ReactNode
  tone?: 'slate' | 'emerald' | 'amber' | 'rose' | 'blue' | 'indigo'
}) {
  const tones: Record<string, string> = {
    slate: 'bg-slate-100 text-slate-600',
    emerald: 'bg-emerald-100 text-emerald-700',
    amber: 'bg-amber-100 text-amber-700',
    rose: 'bg-rose-100 text-rose-700',
    blue: 'bg-blue-100 text-blue-700',
    indigo: 'bg-indigo-100 text-indigo-700',
  }
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${tones[tone]}`}>
      {children}
    </span>
  )
}

/* ---------- live journal preview ---------- */

export type PreviewLine = {
  account: string
  accountName: string
  debit?: number
  credit?: number
}

export function JournalPreview({
  lines,
  okLabel = 'The database verifies this stays balanced before saving.',
}: {
  lines: PreviewLine[]
  okLabel?: string
}) {
  const dr = lines.reduce((s, l) => s + (l.debit ?? 0), 0)
  const cr = lines.reduce((s, l) => s + (l.credit ?? 0), 0)
  const balanced = dr === cr && dr > 0
  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-xs font-bold uppercase tracking-wide text-slate-500">
          Live journal preview — what will be recorded
        </div>
        {balanced ? (
          <Badge tone="emerald">Balanced ✓</Badge>
        ) : (
          <Badge tone="slate">Enter details above</Badge>
        )}
      </div>
      <div className="overflow-hidden rounded-lg border border-slate-200 bg-white">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
              <th className="px-3 py-2">Account</th>
              <th className="px-3 py-2 text-right">Debit</th>
              <th className="px-3 py-2 text-right">Credit</th>
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={i} className="border-b border-slate-100 last:border-0">
                <td className="px-3 py-2">
                  <span className="font-mono text-xs text-slate-500">{l.account}</span>{' '}
                  <span className="font-medium text-slate-800">{l.accountName}</span>
                </td>
                <td className="px-3 py-2 text-right font-mono tabular-nums text-slate-800">
                  {l.debit ? <Money paisa={l.debit} /> : '—'}
                </td>
                <td className="px-3 py-2 text-right font-mono tabular-nums text-slate-800">
                  {l.credit ? <Money paisa={l.credit} /> : '—'}
                </td>
              </tr>
            ))}
            <tr className="bg-slate-50 font-semibold">
              <td className="px-3 py-2 text-xs uppercase tracking-wide text-slate-500">Totals</td>
              <td className="px-3 py-2 text-right font-mono tabular-nums">
                {dr > 0 ? <Money paisa={dr} /> : '—'}
              </td>
              <td className="px-3 py-2 text-right font-mono tabular-nums">
                {cr > 0 ? <Money paisa={cr} /> : '—'}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div className="mt-2 text-xs text-slate-500">{okLabel}</div>
    </div>
  )
}

/** Account names for previews (mirrors the live chart of accounts). */
export const ACCOUNT_NAMES: Record<string, string> = {
  '1000': 'Cash on Hand',
  '1050': 'Cash — Bank (future use)',
  '1100': 'Accounts Receivable — Trade',
  '1200': 'Inventory — Raw Salt',
  '1210': 'Inventory — Bulk Processed Salt',
  '1220': 'Inventory — Packaged Goods',
  '1230': 'Inventory — Packaging Material',
  '1400': 'Vehicle (Motorcycle)',
  '1450': 'Livestock — Side Activity (Goats)',
  '1500': 'Other Fixed Assets',
  '1900': 'Suspense / Unclassified',
  '2000': 'Accounts Payable — Trade',
  '2100': 'Accrued Expenses',
  '2200': 'Customer Advances (liability)',
  '3000': 'Owner Capital',
  '3100': 'Owner Drawings',
  '4000': 'Salt Sales Revenue',
  '4100': 'Cost of Goods Sold — Salt',
  '4900': 'Other Income',
  '5000': 'Labour',
  '5100': 'Utilities',
  '5250': 'Wastage / Shrinkage (production)',
  '5300': 'Fuel',
  '5500': 'Site Meals & Welfare',
  '5600': 'Travel',
  '5700': 'Repairs & Maintenance',
  '5800': 'Admin & Office',
  '5900': 'Other Business Expense',
}

export function accountName(code: string): string {
  return ACCOUNT_NAMES[code] ?? `Account ${code}`
}

/* ---------- paged lists: never load "everything" (the API returns at most 1000 rows) ---------- */

/** Loads a list one page at a time. `resetKey` change = start again from the first page. */
export function usePaged<T>(fetchPage: (limit: number, offset: number) => Promise<T[]>, resetKey: unknown = null) {
  const [rows, setRows] = useState<T[] | null>(null)
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const fetchRef = useRef(fetchPage)
  fetchRef.current = fetchPage
  const rowsRef = useRef<T[] | null>(null)

  const load = useCallback(async (reset: boolean) => {
    setBusy(true)
    setError(null)
    try {
      const offset = reset ? 0 : (rowsRef.current?.length ?? 0)
      const page = await fetchRef.current(PAGE_SIZE, offset)
      const next = reset || !rowsRef.current ? page : [...rowsRef.current, ...page]
      rowsRef.current = next
      setRows(next)
      setHasMore(page.length === PAGE_SIZE)
    } catch (e) {
      setError(e)
    } finally {
      setBusy(false)
    }
  }, [])

  useEffect(() => {
    rowsRef.current = null
    setRows(null)
    load(true)
  }, [load, resetKey])

  return { rows, hasMore, busy, error, more: () => load(false), reload: () => load(true) }
}

export function ShowMore({ paged }: { paged: { hasMore: boolean; busy: boolean; more: () => void } }) {
  if (!paged.hasMore) return null
  return (
    <button
      type="button"
      onClick={paged.more}
      disabled={paged.busy}
      className="mt-3 min-h-11 w-full rounded-xl border-2 border-slate-300 px-4 py-3 text-base font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-60"
    >
      {paged.busy ? 'Loading…' : 'Show more'}
    </button>
  )
}
