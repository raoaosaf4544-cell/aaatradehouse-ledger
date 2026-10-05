/**
 * Batches in plain words. The batch codes stay as they are inside the books; screens show:
 *   BATCH-001     -> "Rock – Batch 1 (bought 3 Sep)"
 *   BATCH-075     -> "Fine – bought crushed, Batch 2 (14 Sep)"
 *   BATCH-001-G1  -> "Fine – crushed in-house from Rock Batch 1 (5 Oct)"   (or "Daana – …")
 * Bought batches are numbered 1, 2, 3… by the day they came in (all batches ever, so a number never changes when
 * one runs out). Crush outputs are named after the rock batch they came from (their code is that batch + "-Gn").
 */
type B = { id: number; batch_code: string; product_code: string; opened_on: string; onhand_grams: number; value_paisa: number }

const OUTPUT = /^(.*)-G\d+$/

export const saltWord = (productCode: string) =>
  productCode === 'SALT_ROCK' || productCode === 'SALT_RAW' ? 'Rock' : productCode === 'SALT_ROCK_COARSE' ? 'Daana' : 'Fine'

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
/** "2026-09-03" -> "3 Sep" (same on every phone, whatever its language setting) */
export const shortDate = (iso: string) => {
  const [, m, d] = iso.split('-').map(Number)
  return `${d} ${MONTHS[m - 1]}`
}

const byAge = (a: B, b: B) => a.opened_on.localeCompare(b.opened_on) || a.id - b.id

/** Plain name for every batch code in `all` (pass every batch, empty ones too, so the numbers stay put). */
export function batchNames(all: B[]): Map<string, string> {
  const bought = all.filter((b) => !OUTPUT.test(b.batch_code)).sort(byAge)
  const no = new Map(bought.map((b, i) => [b.batch_code, i + 1]))
  const names = new Map<string, string>()
  for (const b of all) {
    const word = saltWord(b.product_code)
    const parent = OUTPUT.exec(b.batch_code)?.[1]
    if (parent !== undefined) {
      const p = all.find((x) => x.batch_code === parent)
      const from = p ? `${saltWord(p.product_code)} Batch ${no.get(parent)}` : parent
      names.set(b.batch_code, `${word} – crushed in-house from ${from} (${shortDate(b.opened_on)})`)
    } else if (word === 'Rock') {
      names.set(b.batch_code, `Rock – Batch ${no.get(b.batch_code)} (bought ${shortDate(b.opened_on)})`)
    } else {
      names.set(b.batch_code, `${word} – bought crushed, Batch ${no.get(b.batch_code)} (${shortDate(b.opened_on)})`)
    }
  }
  return names
}

/** Rs per kg of what is left in the batch (its book value ÷ kg). */
export const costPerKg = (b: B) => (b.onhand_grams > 0 ? b.value_paisa / 100 / (b.onhand_grams / 1000) : 0)

/** "13,850 kg left · Rs 7.51/kg" */
export const leftAndCost = (b: B) =>
  `${(b.onhand_grams / 1000).toLocaleString('en-PK', { maximumFractionDigits: 3 })} kg left · Rs ${costPerKg(b).toLocaleString('en-PK', { maximumFractionDigits: 2 })}/kg`

/** Batches with salt left, oldest first (first in, first out). */
export const withStockOldestFirst = <T extends B>(bs: T[]) => bs.filter((b) => b.onhand_grams > 0).sort(byAge)
