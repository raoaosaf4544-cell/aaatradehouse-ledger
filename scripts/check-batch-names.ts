// Self-check for src/lib/batches.ts (plain batch names). Run: bun scripts/check-batch-names.ts
import assert from 'node:assert/strict'
import { batchNames, costPerKg, withStockOldestFirst } from '../src/lib/batches'

const all = [
  { id: 75, batch_code: 'BATCH-075', product_code: 'SALT_BULK', opened_on: '2026-09-14', onhand_grams: 6525500, value_paisa: 6133970 },
  { id: 1, batch_code: 'BATCH-001', product_code: 'SALT_ROCK', opened_on: '2026-09-03', onhand_grams: 13850000, value_paisa: 10405640 },
  { id: 90, batch_code: 'BATCH-001-G1', product_code: 'SALT_BULK', opened_on: '2026-10-05', onhand_grams: 0, value_paisa: 0 },
  { id: 91, batch_code: 'BATCH-001-G2', product_code: 'SALT_ROCK_COARSE', opened_on: '2026-10-05', onhand_grams: 400000, value_paisa: 400000 },
]
const n = batchNames(all)
assert.equal(n.get('BATCH-001'), 'Rock – Batch 1 (bought 3 Sep)')
assert.equal(n.get('BATCH-075'), 'Fine – bought crushed, Batch 2 (14 Sep)')
assert.equal(n.get('BATCH-001-G1'), 'Fine – crushed in-house from Rock Batch 1 (5 Oct)')
assert.equal(n.get('BATCH-001-G2'), 'Daana – crushed in-house from Rock Batch 1 (5 Oct)')
assert.equal(Math.round(costPerKg(all[1]) * 100) / 100, 7.51)
// empty batches are hidden; oldest first
assert.deepEqual(withStockOldestFirst(all).map((b) => b.batch_code), ['BATCH-001', 'BATCH-075', 'BATCH-001-G2'])
console.log('batch names check: OK')
