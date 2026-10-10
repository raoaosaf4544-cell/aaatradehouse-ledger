// Self-check for src/lib/crushCosts.ts. Run: bun scripts/check-crush-costs.ts
import assert from 'node:assert/strict'
import { costPerKg } from '../src/lib/crushCosts'

// Rao's example: rock 7,513.10 + plant cost 2,000 over 950 kg = Rs 10.01/kg (10.0138), Rs 500.69 per 50 kg bag
assert.equal(Math.round(costPerKg(751310 + 200000, 950000) * 100) / 100, 10.01)
assert.equal(Math.round(costPerKg(951310, 950000) * 50 * 100) / 100, 500.69)
console.log('crush costs check: OK')
