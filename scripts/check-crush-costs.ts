// Self-check for src/lib/crushCosts.ts. Run: bun scripts/check-crush-costs.ts
import assert from 'node:assert/strict'
import { costPerKg, newCostDraft, paidNowPaisa, toCosts, type CostDraft } from '../src/lib/crushCosts'

const row = (kind: CostDraft['kind'], patch: Partial<CostDraft>): CostDraft => ({ ...newCostDraft(kind), ...patch })

// defaults: labour paid in full now, electricity all later (to the bill party)
assert.equal(paidNowPaisa(row('labour', { amount: '2000' })), 200000)
assert.equal(paidNowPaisa(row('electricity', { amount: '800' })), 0)
assert.equal(row('electricity', {}).owedTo, 'MEPCO bijli bill')

// Rao's mixed case: labour 2,000 (1,500 now, 500 later to a worker) + electricity 800 later + bags 500 now
assert.equal(paidNowPaisa(row('labour', { amount: '2000', paidNow: '', paidEdited: true })), 0) // cleared while typing = 0, not back to full
const mixed = toCosts([
  row('labour', { amount: '2000', paidNow: '1500', paidEdited: true, owedTo: 'Test worker' }),
  row('electricity', { amount: '800' }),
  row('bags', { amount: '500' }),
  row('diesel', { amount: '' }), // empty row: ignored
])
assert.deepEqual(mixed.problems, [])
assert.deepEqual(mixed.costs, [
  { kind: 'labour', amount_paisa: 200000, paid_now_paisa: 150000, owed_to: 'Test worker' },
  { kind: 'electricity', amount_paisa: 80000, paid_now_paisa: 0, owed_to: 'MEPCO bijli bill' },
  { kind: 'bags', amount_paisa: 50000, paid_now_paisa: 50000 },
])

// already entered in Money Out: not costed, not paid, shown
const booked = toCosts([row('labour', { amount: '700', alreadyBooked: true })])
assert.deepEqual(booked.costs, [])
assert.equal(booked.alreadyBookedPaisa, 70000)

// problems: pay later with no name; paid now above the amount
assert.equal(toCosts([row('labour', { amount: '1000', paidNow: '400', paidEdited: true })]).problems.length, 1)
assert.equal(toCosts([row('labour', { amount: '1000', paidNow: '1200', paidEdited: true })]).problems.length, 1)

// Rao's example: rock 7,513.10 + crushing 2,000 over 950 kg = Rs 10.01/kg (10.0138), Rs 500.69 per 50 kg bag
assert.equal(Math.round(costPerKg(751310 + 200000, 950000) * 100) / 100, 10.01)
assert.equal(Math.round(costPerKg(951310, 950000) * 50 * 100) / 100, 500.69)
console.log('crush costs check: OK')
