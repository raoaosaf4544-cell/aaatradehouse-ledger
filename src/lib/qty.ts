/**
 * Sale quantities the way they are counted at the plant. Input helpers only: the books keep grams + price per kg.
 * Man is 40 kg and stays 40 kg (old entries and baba's register use it).
 */
export const MAN_KG = 40
export const UNITS = [
  { id: 'bag50', label: 'Bag 50 kg', kg: 50, one: 'bag' },
  { id: 'man', label: `Man ${MAN_KG} kg`, kg: MAN_KG, one: 'man' },
  { id: 'bag25', label: 'Bag 25 kg', kg: 25, one: 'bag' },
  { id: 'bag20', label: 'Bag 20 kg', kg: 20, one: 'bag' },
  { id: 'kg', label: 'Loose kg', kg: 1, one: 'kg' },
] as const
export type QtyUnit = (typeof UNITS)[number]['id']
export const unitOf = (id: QtyUnit) => UNITS.find((u) => u.id === id)!

/** kg for one line (0 when not complete). */
export function lineKg(unit: QtyUnit, count: number): number {
  return count > 0 ? count * unitOf(unit).kg : 0
}

/** "6 × 50 kg bags", "3 man", "240 kg" — written into the note so the books match the paper. */
export function qtyWords(unit: QtyUnit, count: number): string {
  const u = unitOf(unit)
  if (u.one === 'bag') return `${count} × ${u.kg} kg bag${count === 1 ? '' : 's'}`
  return `${count} ${u.one}`
}

export type PoolBatch = { id: number; opened_on: string; onhand_grams: number; value_paisa: number }

/**
 * What taking `takeG` grams costs, oldest batch first, after `skipG` grams already taken by earlier lines — the same
 * way the sale books it (app.fifo_pool + batch_unit_cost_paisa_per_kg: unit cost = value ÷ kg, rounded to the paisa).
 */
export function fifoCostPaisa(batches: PoolBatch[], skipG: number, takeG: number): number {
  const pool = [...batches].filter((b) => b.onhand_grams > 0).sort((a, b) => a.opened_on.localeCompare(b.opened_on) || a.id - b.id)
  let cost = 0
  for (const b of pool) {
    let avail = b.onhand_grams
    const skip = Math.min(skipG, avail)
    skipG -= skip
    avail -= skip
    const take = Math.min(takeG, avail)
    if (take <= 0) continue
    const unitPpk = Math.round(b.value_paisa / (b.onhand_grams / 1000))
    cost += Math.round((take * unitPpk) / 1000)
    takeG -= take
  }
  return cost
}
