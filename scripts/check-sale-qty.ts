// Self-check for src/lib/qty.ts (sale quantities). Run: bun scripts/check-sale-qty.ts
import assert from 'node:assert/strict'
import { UNITS, bagsLooseGrams, crushWastage, fifoCostPaisa, lineKg, qtyWords } from '../src/lib/qty'

assert.equal(UNITS[0].id, 'bag50') // "Bag 50 kg" is first (the default)
assert.deepEqual(UNITS.map((u) => u.label), ['Bag 50 kg', 'Man 40 kg', 'Bag 25 kg', 'Bag 20 kg', 'Loose kg'])
assert.equal(lineKg('kg', 240), 240)
assert.equal(lineKg('bag50', 6), 300)
assert.equal(lineKg('bag25', 4), 100)
assert.equal(lineKg('bag20', 5), 100)
assert.equal(lineKg('man', 5), 200) // 1 man = 40 kg, never redefined
assert.equal(lineKg('man', 2.5), 100)
assert.equal(lineKg('kg', 0), 0)
assert.equal(lineKg('kg', Number.NaN), 0)

assert.equal(qtyWords('bag50', 6), '6 × 50 kg bags')
assert.equal(qtyWords('bag20', 1), '1 × 20 kg bag')
assert.equal(qtyWords('man', 3), '3 man')
assert.equal(qtyWords('kg', 240), '240 kg')

// a bill total the per-kg entry could not hit exactly: 3,140 for 240 kg (13.0833.../kg) stays 3,140.00
const billPaisa = Math.round(3140 * 100)
assert.equal(billPaisa, 314000)
assert.equal(Math.round((billPaisa / 100) * 100), 314000) // what the engine sends as line_total_paisa
// below-cost warning: BATCH-075 Fine Powder, 9,817.5 kg worth 92,284.50 -> Rs 9.40/kg.
// 15 x 40 kg for Rs 5,000 (Rs 8.33/kg) costs Rs 5,640 -> you lose Rs 640.
const bulk = [{ id: 75, opened_on: '2026-09-10', onhand_grams: 9817500, value_paisa: 9228450 }]
assert.equal(fifoCostPaisa(bulk, 0, 600000), 564000)
assert.equal(fifoCostPaisa(bulk, 0, 600000) - 500000, 64000)
// oldest batch first, then the next; an earlier line's kg are skipped
const two = [{ id: 9, opened_on: '2026-09-20', onhand_grams: 1000000, value_paisa: 2000000 }, { id: 8, opened_on: '2026-09-01', onhand_grams: 500000, value_paisa: 500000 }]
assert.equal(fifoCostPaisa(two, 0, 700000), 500000 + 400000) // 500 kg at Rs 10 + 200 kg at Rs 20
assert.equal(fifoCostPaisa(two, 400000, 200000), 100000 + 200000) // 100 kg left at Rs 10 + 100 kg at Rs 20
// crush by bag count: 40 bags + 10 kg rock = 2,010 kg; 30 bags fine + 9 bags daana + 5 kg = 1,955 kg -> 55 kg wastage
assert.equal(bagsLooseGrams('40', '10'), 2010000)
assert.equal(bagsLooseGrams('', '12.5'), 12500)
assert.equal(bagsLooseGrams('-3', 'x'), 0)
const w = crushWastage(bagsLooseGrams('40', '10'), bagsLooseGrams('30', '') + bagsLooseGrams('9', '5'))
assert.equal(w.g, 55000)
assert.equal(Math.round(w.pct * 100) / 100, 2.74)
assert.equal(w.over, false)
assert.equal(crushWastage(1000000, 1000001).over, true) // more out than in: blocked
console.log('sale quantity check: OK')
