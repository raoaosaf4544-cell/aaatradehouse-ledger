import type { CrushCost } from './types'

/** Crushing-cost kinds, English + Urdu. Labour is usually paid on the spot; electricity at month end. */
export const COST_KINDS = [
  { kind: 'labour', en: 'Labour', ur: 'مزدوری' },
  { kind: 'electricity', en: 'Electricity', ur: 'بجلی' },
  { kind: 'diesel', en: 'Diesel', ur: 'ڈیزل' },
  { kind: 'bags', en: 'Empty bags', ur: 'خالی بوریاں' },
  { kind: 'other', en: 'Other', ur: 'دیگر' },
] as const satisfies readonly { kind: CrushCost['kind']; en: string; ur: string }[]

export const ELECTRICITY_PARTY = 'MEPCO bijli bill'

/** One row of the cost table as typed. Until paid-now is edited it follows its kind's default (full; electricity 0). */
export type CostDraft = {
  key: number
  kind: CrushCost['kind']
  amount: string
  paidNow: string
  paidEdited: boolean
  owedTo: string
  expectedOn: string
  /** already booked in Money Out: adds nothing to cash or to the salt cost */
  alreadyBooked: boolean
}

let nextKey = 1
export const newCostDraft = (kind: CrushCost['kind']): CostDraft => ({
  key: nextKey++,
  kind,
  amount: '',
  paidNow: '',
  paidEdited: false,
  owedTo: kind === 'electricity' ? ELECTRICITY_PARTY : '',
  expectedOn: '',
  alreadyBooked: false,
})

const paisa = (s: string) => (Number.isFinite(Number(s)) && Number(s) > 0 ? Math.round(Number(s) * 100) : 0)

/** Paid now in paisa: as typed (blank = 0), or the kind's default (full amount, 0 for electricity). -1 = not a number. */
export function paidNowPaisa(d: CostDraft): number {
  if (!d.paidEdited) return d.kind === 'electricity' ? 0 : paisa(d.amount)
  const n = Number(d.paidNow.trim() || '0')
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) : -1
}

/**
 * The rows the database gets (already-booked rows and empty rows are left out), the problems to fix before saving,
 * and the already-booked total (shown, not costed).
 */
export function toCosts(drafts: CostDraft[]): { costs: CrushCost[]; problems: string[]; alreadyBookedPaisa: number } {
  const costs: CrushCost[] = []
  const problems: string[] = []
  let alreadyBookedPaisa = 0
  for (const d of drafts) {
    const amount = paisa(d.amount)
    if (amount === 0) continue
    if (d.alreadyBooked) {
      alreadyBookedPaisa += amount
      continue
    }
    const paid = paidNowPaisa(d)
    const name = COST_KINDS.find((k) => k.kind === d.kind)!.en
    if (paid < 0 || paid > amount) {
      problems.push(`${name}: paid now must be between 0 and Rs ${(amount / 100).toLocaleString()}.`)
      continue
    }
    if (paid < amount && !d.owedTo.trim()) {
      problems.push(`${name}: Rs ${((amount - paid) / 100).toLocaleString()} is to pay later — say who it is owed to.`)
      continue
    }
    costs.push({
      kind: d.kind,
      amount_paisa: amount,
      paid_now_paisa: paid,
      ...(paid < amount ? { owed_to: d.owedTo.trim(), ...(d.expectedOn ? { expected_on: d.expectedOn } : {}) } : {}),
    })
  }
  return { costs, problems, alreadyBookedPaisa }
}

/** Rs per kg of crushed salt = (rock cost used + crushing cost) / good kg out. */
export const costPerKg = (poolPaisa: number, outGrams: number) => (outGrams > 0 ? poolPaisa / 100 / (outGrams / 1000) : 0)
