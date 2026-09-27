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
