// Self-check for src/lib/unclassified.ts. Run: bun scripts/check-unclassified.ts
import assert from 'node:assert/strict'
import { DEFAULT_REASON, MOVE_TARGETS, moveLines } from '../src/lib/unclassified'
import { reasonProblem } from '../src/lib/friendly'

// EV-000531 as it is now (the database's opening lines): Dr 5950 / Cr Cash, Rs 100 -> moved to Site meals, cash side kept
const now = [
  { account: '5950', debit: 10000, credit: 0 },
  { account: '1000', debit: 0, credit: 10000 },
]
assert.deepEqual(moveLines(now, '5500'), [{ account: '5500', debit: 10000 }, { account: '1000', credit: 10000 }])
assert.equal(moveLines([{ account: '5500', debit: 1, credit: 0 }, { account: '1000', debit: 0, credit: 1 }], '5300'), null) // no 5950 line
assert.deepEqual(MOVE_TARGETS.map((t) => t.code), ['5300', '5500', '5600', '5700', '5000', '5100', '5800', '5200', '5900', '3100'])
assert.ok(!MOVE_TARGETS.some((t) => (t.code as string) === '5950'))
assert.equal(reasonProblem(DEFAULT_REASON), null) // the pre-filled reason passes the 4-letter rule
console.log('unclassified check: OK')
