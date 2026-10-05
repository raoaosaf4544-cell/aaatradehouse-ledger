// Self-check for src/lib/friendly.ts: raw database text is never shown. Run: bun scripts/check-friendly.ts
import assert from 'node:assert/strict'
import { REASON_RULE, friendlyMessage, reasonProblem } from '../src/lib/friendly'

const server = (message: string) => ({ message, definite: true, fromServer: true })

// no answer after sending: honest wording, never "nothing saved"
assert.equal(friendlyMessage({ message: 'TypeError: Failed to fetch', definite: false }, 'save'), 'No signal — not confirmed. Tap Retry: it never saves twice.')
assert.equal(friendlyMessage({ message: 'AbortError', definite: false }, 'load'), 'No signal — could not load. Check signal and try again.')

// known refusals -> plain sentences
assert.match(friendlyMessage(server('INVARIANT VIOLATION: Cash on Hand would go negative (balance -500 paisa)'), 'save'), /^Not saved: Not enough cash/)
assert.match(friendlyMessage(server('INVARIANT VIOLATION: stock negative for batch 3 at location 1 (qty -2000 g)'), 'save'), /^Not saved: Not enough salt/)
assert.equal(friendlyMessage(server('INVARIANT VIOLATION: payment 500.00 exceeds Haji Alis outstanding receivable of 40.00 - overpayments belong on Customer Advances, not here'), 'save'),
  'Not saved: That is more than Haji Ali owes (Rs 40). Extra money goes on Customer Advances.')

// the real reason, with its numbers (messages exactly as the database words them)
const say = (raw: string) => friendlyMessage(server(raw), 'save')
assert.equal(say('INVARIANT VIOLATION: insufficient eligible stock of SALT_ROCK_COARSE at KHANEWAL_PLANT - need 600.0 kg more, nothing compatible left (FIFO pool exhausted)'),
  'Not saved: Not enough Coarse Salt (daana) in stock — 600 kg short.')
assert.equal(say('INVARIANT VIOLATION: crushed kg (990.000) + wastage (1.000) must equal kg in (1000.000)'),
  'Not saved: Crushed kg (990) + wastage (1) must equal kg in (1,000).')
assert.equal(say('INVARIANT VIOLATION: only 13078.0 kg of Rock Salt (whole / dalay) in batch BATCH-001'),
  'Not saved: Only 13,078 kg of Rock Salt (whole / dalay) in batch BATCH-001.')
assert.equal(say('INVARIANT VIOLATION: on credit needs the supplier who is owed the crushing cost'), 'Not saved: On credit: pick or type who is owed the crushing cost.')
assert.equal(say('INVARIANT VIOLATION: Rock Salt — Mesh Grade (generic) is not a crush output grade'),
  'Not saved: Rock Salt — Mesh Grade (generic) cannot come out of a crush — choose Fine Powder or Coarse.')
assert.equal(say('INVARIANT VIOLATION: cost components sum to 1000.00 but landed cost is 1200.00 - they must match exactly (no double counting)'),
  'Not saved: The cost parts add up to Rs 1,000 but the total cost is Rs 1,200 — they must match.')
assert.equal(say('INVARIANT VIOLATION: line 1 requests 600.0 kg but invoice INV-00050 has only 40.0 kg left to dispatch for SALT_BULK'),
  'Not saved: Invoice INV-00050 has only 40 kg left to send, not 600 kg.')
assert.equal(say('INVARIANT VIOLATION: wastage cannot be negative'), 'Not saved: The wastage cannot be below 0.')
assert.equal(say('null value in column "value_paisa" of relation "movements" violates not-null constraint'), 'Not saved: A required figure was missing, so nothing was saved.')
assert.equal(say('CONCURRENCY: another dispatch changed the same stock - nothing was saved, please retry'),
  'Not saved: Someone saved a change to the same stock at the same moment — nothing was saved. Tap Retry.')
assert.equal(say('INVARIANT VIOLATION: batch BATCH-075 did not exist yet on 2026-09-10 (it arrived 2026-09-14)'),
  'Not saved: Batch BATCH-075 had not arrived yet on 10 Sep 2026 — it arrived 14 Sep 2026. Change the date or the batch.')
assert.equal(say('INVARIANT VIOLATION: date 2026-10-04 is in the future (today is 2026-10-03)'), 'Not saved: 4 Oct 2026 is in the future. Pick today or an earlier day.')
assert.equal(say('INVARIANT VIOLATION: date 2026-08-22 is before the books start (23 Aug 2026)'), 'Not saved: The books start on 23 Aug 2026. Pick that day or later.')
assert.equal(say('INVARIANT VIOLATION: nothing changed - the correct version is the same as the entry'), 'Not saved: Nothing changed — the correct version is the same as the entry.')
assert.equal(say('INVARIANT VIOLATION: CL-20260823-003 was already corrected by EV-000441. Delete that correction first (it shows what changes), then correct CL-20260823-003.'),
  'Not saved: CL-20260823-003 was already corrected by EV-000441. Delete that correction first (Delete shows what changes), then correct CL-20260823-003.')
for (const m of [
  'INVARIANT VIOLATION: supplier name is required', 'INVARIANT VIOLATION: unknown product code X', 'INVARIANT VIOLATION: quantity must be positive (line 1)',
  'INVARIANT VIOLATION: a correction may only be dated on or before the original (2026-09-30 is after 2026-09-24)',
  'INVARIANT VIOLATION: event 12 unbalanced (debit 5, credit 6 paisa)', 'INVARIANT VIOLATION: at least one sale line is required',
]) {
  const t = say(m)
  assert.ok(t.startsWith('Not saved: ') && !/INVARIANT|paisa|_/.test(t), `${m} -> ${t}`)
}
assert.match(friendlyMessage(server('Not authorised'), 'save'), /not allowed/)
assert.match(friendlyMessage(server('JWT expired'), 'load'), /sign-in has expired/)

// anything else from the server: general sentence, and never the raw text
const raw = 'INVARIANT VIOLATION: something internal (code 5)'
const msg = friendlyMessage(server(raw), 'save')
assert.equal(msg, 'The books refused this entry, so nothing was saved. Check the numbers and try again.')
assert.ok(!msg.includes('INVARIANT') && !msg.includes('paisa'))

// delete / restore refusals are written in plain words by the database: shown without the 'Cannot delete:' prefix
assert.equal(friendlyMessage(server('Cannot delete: Salt from BATCH-075 was already used by EV-000171. Delete those first.'), 'save'), 'Salt from BATCH-075 was already used by EV-000171. Delete those first.')
assert.equal(friendlyMessage(server('Cannot restore: an entry with the same number already exists.'), 'save'), 'an entry with the same number already exists.')

// our own plain checks pass through; our own strings pass through
assert.equal(friendlyMessage({ message: 'Supplier name is required.', definite: true, fromServer: false }, 'save'), 'Supplier name is required.')
assert.equal(friendlyMessage('Cash plus advance is more than the bill total — reduce the cash received.', 'save'), 'Cash plus advance is more than the bill total — reduce the cash received.')

// reason rule (same as app.reason_problem): at least 4 letters, not only numbers/symbols
for (const bad of ['', 'x', '1234', 'ab 12 !!']) assert.equal(reasonProblem(bad), REASON_RULE, bad)
for (const ok of ['baba confirmed', 'test', 'بابا نے کہا']) assert.equal(reasonProblem(ok), null, ok)
assert.equal(say('INVARIANT VIOLATION: Write a short reason, at least 4 letters (not only numbers).'), `Not saved: ${REASON_RULE}`)
assert.equal(friendlyMessage(server('Cannot delete: Write a short reason, at least 4 letters (not only numbers).'), 'save'), REASON_RULE)

// a correction chain: an older version is refused with the newest one named
assert.equal(say('INVARIANT VIOLATION: EV-000531 was replaced by EV-000550 - correct EV-000550 instead.'),
  'Not saved: EV-000531 was already changed — the newest version is EV-000550. Open EV-000550 instead.')

// a plain JS crash: general sentence, not the crash text
assert.equal(friendlyMessage(new TypeError("Cannot read properties of undefined (reading 'x')"), 'load'), 'Something went wrong loading this screen. Try again.')
console.log('friendly message check: OK')
