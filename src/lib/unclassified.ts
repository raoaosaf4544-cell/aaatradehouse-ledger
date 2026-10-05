/** 5950 Personal/Unclassified: where an unclear register line waits until baba says what it was. */
export const UNCLASSIFIED = '5950'

/** Where baba can move a line, in English + Urdu (owner-approved list, 5 Oct 2026). */
export const MOVE_TARGETS = [
  { code: '5300', en: 'Fuel', ur: 'پیٹرول' },
  { code: '5500', en: 'Site meals', ur: 'کھانا' },
  { code: '5600', en: 'Travel', ur: 'کرایہ سفر' },
  { code: '5700', en: 'Repairs', ur: 'مرمت' },
  { code: '5000', en: 'Labour', ur: 'مزدوری' },
  { code: '5100', en: 'Utilities', ur: 'بل' },
  { code: '5800', en: 'Admin', ur: 'دفتری' },
  { code: '5200', en: 'Freight', ur: 'کرایہ مال' },
  { code: '5900', en: 'Other business', ur: 'دیگر کاروباری' },
  { code: '3100', en: 'Personal', ur: 'ذاتی خرچ' },
] as const

export const DEFAULT_REASON = 'baba confirmed / بابا نے تصدیق کی'

type Line = { account: string; debit: number; credit: number }

/**
 * The entry as it should be: the same lines (same amount, same cash side), with the 5950 line moved to `to`.
 * Null when the entry has no 5950 line (nothing to move).
 */
export function moveLines(lines: Line[], to: string): { account: string; debit?: number; credit?: number }[] | null {
  if (!lines.some((l) => l.account === UNCLASSIFIED)) return null
  return lines.map((l) => ({
    account: l.account === UNCLASSIFIED ? to : l.account,
    ...(l.debit > 0 ? { debit: l.debit } : { credit: l.credit }),
  }))
}
