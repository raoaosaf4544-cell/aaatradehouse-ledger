/** Sale quantities the way they are counted at the plant: kg, bags of a size, or man (40 kg). */
export type QtyUnit = 'kg' | 'bag' | 'man'
export const MAN_KG = 40
export const BAG_SIZES = [20, 25, 40, 50]

/** kg for one line (0 when not complete). */
export function lineKg(unit: QtyUnit, count: number, bagKg: number): number {
  if (!(count > 0)) return 0
  if (unit === 'kg') return count
  if (unit === 'man') return count * MAN_KG
  return bagKg > 0 ? count * bagKg : 0
}

/** "6 × 50 kg bags", "3 man", "240 kg" — written into the note so the books match the paper. */
export function qtyWords(unit: QtyUnit, count: number, bagKg: number): string {
  if (unit === 'bag') return `${count} × ${bagKg} kg bag${count === 1 ? '' : 's'}`
  if (unit === 'man') return `${count} man`
  return `${count} kg`
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
