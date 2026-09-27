// Self-check for src/lib/friendly.ts: raw database text is never shown. Run: bun scripts/check-friendly.ts
import assert from 'node:assert/strict'
import { friendlyMessage } from '../src/lib/friendly'

const server = (message: string) => ({ message, definite: true, fromServer: true })

// no answer after sending: honest wording, never "nothing saved"
assert.equal(friendlyMessage({ message: 'TypeError: Failed to fetch', definite: false }, 'save'), 'No signal — not confirmed. Tap Retry: it never saves twice.')
assert.equal(friendlyMessage({ message: 'AbortError', definite: false }, 'load'), 'No signal — could not load. Check signal and try again.')

// known refusals -> plain sentences
assert.match(friendlyMessage(server('INVARIANT VIOLATION: Cash on Hand would go negative (balance -500 paisa)'), 'save'), /^Not enough cash/)
assert.match(friendlyMessage(server('INVARIANT VIOLATION: stock negative for batch 3 at location 1 (qty -2000 g)'), 'save'), /^Not enough salt/)
assert.match(friendlyMessage(server('INVARIANT VIOLATION: payment 500.00 exceeds Haji Ali\'s outstanding receivable of 40.00 - overpayments belong on Customer Advances, not here'), 'save'), /more than this customer owes/)
assert.match(friendlyMessage(server('Not authorised'), 'save'), /not allowed/)
assert.match(friendlyMessage(server('JWT expired'), 'load'), /sign-in has expired/)

// anything else from the server: general sentence, and never the raw text
const raw = 'INVARIANT VIOLATION: something internal (debit 5, credit 6 paisa)'
const msg = friendlyMessage(server(raw), 'save')
assert.equal(msg, 'The books refused this entry, so nothing was saved. Check the numbers and try again.')
assert.ok(!msg.includes('INVARIANT') && !msg.includes('paisa'))

// delete / restore refusals are written in plain words by the database: shown without the 'Cannot delete:' prefix
assert.equal(friendlyMessage(server('Cannot delete: Salt from BATCH-075 was already used by EV-000171. Delete those first.'), 'save'), 'Salt from BATCH-075 was already used by EV-000171. Delete those first.')
assert.equal(friendlyMessage(server('Cannot restore: an entry with the same number already exists.'), 'save'), 'an entry with the same number already exists.')

// our own plain checks pass through; our own strings pass through
assert.equal(friendlyMessage({ message: 'Supplier name is required.', definite: true, fromServer: false }, 'save'), 'Supplier name is required.')
assert.equal(friendlyMessage('Cash plus advance is more than the bill total — reduce the cash received.', 'save'), 'Cash plus advance is more than the bill total — reduce the cash received.')

// a plain JS crash: general sentence, not the crash text
assert.equal(friendlyMessage(new TypeError("Cannot read properties of undefined (reading 'x')"), 'load'), 'Something went wrong loading this screen. Try again.')
console.log('friendly message check: OK')
