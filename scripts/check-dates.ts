// Self-check for the entry-form dates in src/components/ui.tsx. Run: bun scripts/check-dates.ts
import assert from 'node:assert/strict'
import { dateInWords, todayPK } from '../src/components/ui'

assert.equal(dateInWords('2026-09-27'), 'Sun 27 Sep 2026')
assert.equal(dateInWords('2026-09-24'), 'Thu 24 Sep 2026')
assert.equal(dateInWords('2024-02-29'), 'Thu 29 Feb 2024')
assert.equal(dateInWords(''), '') // date box cleared: no words, no crash

// Pakistan time: 00:30 on 27 Sep in Karachi is still 26 Sep in UTC
const RealDate = Date
;(globalThis as any).Date = class extends RealDate {
  constructor(...a: any[]) { super(...(a.length ? a : ['2026-09-26T19:30:00Z']) as []) }
}
assert.equal(todayPK(), '2026-09-27')
globalThis.Date = RealDate
console.log('date check: OK')
