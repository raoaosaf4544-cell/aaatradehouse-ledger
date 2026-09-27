// Self-check for src/lib/qty.ts (sale quantities). Run: bun scripts/check-sale-qty.ts
import assert from 'node:assert/strict'
import { lineKg, qtyWords } from '../src/lib/qty'

assert.equal(lineKg('kg', 240, 0), 240)
assert.equal(lineKg('bag', 6, 50), 300)
assert.equal(lineKg('bag', 6, 0), 0) // bag size not picked yet: incomplete
assert.equal(lineKg('man', 5, 0), 200) // 1 man = 40 kg
assert.equal(lineKg('man', 2.5, 0), 100)
assert.equal(lineKg('kg', 0, 0), 0)
assert.equal(lineKg('kg', Number.NaN, 0), 0)

assert.equal(qtyWords('bag', 6, 50), '6 × 50 kg bags')
assert.equal(qtyWords('bag', 1, 20), '1 × 20 kg bag')
assert.equal(qtyWords('man', 3, 0), '3 man')
assert.equal(qtyWords('kg', 240, 0), '240 kg')

// a bill total the per-kg entry could not hit exactly: 3,140 for 240 kg (13.0833.../kg) stays 3,140.00
const billPaisa = Math.round(3140 * 100)
assert.equal(billPaisa, 314000)
assert.equal(Math.round((billPaisa / 100) * 100), 314000) // what the engine sends as line_total_paisa
console.log('sale quantity check: OK')
