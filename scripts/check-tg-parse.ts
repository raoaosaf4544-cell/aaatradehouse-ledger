// Self-check for the Telegram parser in supabase/functions/tg-webhook/parse.ts. Run: bun scripts/check-tg-parse.ts
import assert from 'node:assert/strict'
import {
  CB, UNKNOWN_REPLY, decisionReply, duration, fmtDay, fmtKarachi, parseCallback, parseMessage, snoozeReply, staleWarnings,
} from '../supabase/functions/tg-webhook/parse'

const P = parseMessage
const approve3 = { kind: 'decision', decision: 'approve', aprId: 'APR-3' }

// pairing
assert.deepEqual(P('/pair 4821-XY'), { kind: 'pair', code: '4821-XY' })
assert.deepEqual(P('/pair'), { kind: 'unknown' })

// approve / reject: words, numbers, buttons
for (const t of ['approve APR-3', 'approve 3', 'Approve apr-3', 'APPROVE APR 3', '/approve 3', '/approve@JarvisBot APR-3', '  approve 03 '])
  assert.deepEqual(P(t), approve3, t)
assert.deepEqual(P('reject 3'), { kind: 'decision', decision: 'reject', aprId: 'APR-3' })
for (const t of ['approve', 'approve it', 'approve 3 and 4', 'please approve 3', '/approve'])
  assert.notEqual(P(t).kind, 'decision', t)
assert.deepEqual(parseCallback(CB.approve('APR-3')), approve3)
assert.deepEqual(parseCallback(CB.reject('APR-12')), { kind: 'decision', decision: 'reject', aprId: 'APR-12' })
assert.deepEqual(parseCallback(CB.seen(42)), { kind: 'seen', outboxId: 42 })
assert.deepEqual(parseCallback('d:delete:APR-1'), { kind: 'unknown' })
assert.ok(CB.approve('APR-999999999').length <= 64)

// snooze: commands, plain phrases, default 2h, cap 24h
assert.deepEqual(P('/snooze 2h'), { kind: 'snooze', minutes: 120 })
assert.deepEqual(P('/snooze 30m'), { kind: 'snooze', minutes: 30 })
assert.deepEqual(P('/snooze'), { kind: 'snooze', minutes: 120 })
assert.deepEqual(P('/wake'), { kind: 'wake' })
assert.deepEqual(P('sleeping 3 hours'), { kind: 'snooze', minutes: 180 })
assert.deepEqual(P('going to sleep for 45 min'), { kind: 'snooze', minutes: 45 })
assert.deepEqual(P('dnd 1.5h'), { kind: 'snooze', minutes: 90 })
assert.deepEqual(P('Don’t disturb 2 hours'), { kind: 'snooze', minutes: 120 }) // phone apostrophe
assert.deepEqual(P("don't disturb"), { kind: 'snooze', minutes: 120 })
assert.deepEqual(P('sleep'), { kind: 'snooze', minutes: 120 })
assert.equal(duration('sleep 99h'), 24 * 60)
assert.equal(duration('sleep 0m'), 1)
assert.equal(duration('sleeping now'), null)
assert.equal(P('sleepy customers').kind, 'unknown') // whole words only

// commands
for (const c of ['cash', 'udhaar', 'runway', 'waiting', 'status', 'help'])
  assert.deepEqual(P(`/${c}`), { kind: 'command', name: c })
assert.deepEqual(P('/CASH@JarvisBot'), { kind: 'command', name: 'cash' })
assert.deepEqual(P('/start'), { kind: 'command', name: 'help' })

// anything else
for (const t of ['hello', 'how much cash?', '/delete everything', '', 'cash'])
  assert.deepEqual(P(t), { kind: 'unknown' }, t)
assert.equal(UNKNOWN_REPLY, "Got it — I'll answer when AI chat is switched on")

// Pakistan time (UTC+5, no daylight saving)
assert.equal(fmtKarachi(new Date('2026-10-03T09:30:00Z')), '14:30, Sat 3 Oct')
assert.equal(fmtKarachi(new Date('2026-10-03T19:05:00Z')), '00:05, Sun 4 Oct')
assert.equal(snoozeReply(new Date('2026-10-03T11:30:00Z')),
  'Snoozed until 16:30, Sat 3 Oct (Pakistan time). No rings until then — send /wake to cancel.')

// honest replies about the laptop (fresh = heartbeat within 2 minutes)
const now = new Date('2026-10-03T09:30:00Z')
assert.equal(decisionReply(approve3 as any, new Date('2026-10-03T09:29:00Z'), now), 'Approved APR-3 — the laptop will pick it up now.')
assert.equal(decisionReply(approve3 as any, new Date('2026-10-03T09:27:59Z'), now),
  'Approved APR-3 — will run when the laptop is on (last seen 14:27, Sat 3 Oct)')
assert.equal(decisionReply({ decision: 'reject', aprId: 'APR-3' }, null, now),
  'Rejected APR-3 — the laptop will be told when it is on (not seen yet)')

// stale-books warnings. Today's data (3 Oct): newest sale 18 Sep, newest entry 27 Sep -> both show.
assert.equal(fmtDay('2026-09-18'), '18 Sep')
assert.deepEqual(staleWarnings({ newest_entry_on: '2026-09-27', newest_sale_on: '2026-09-18', sales_stale: true, books_stale: true }), [
  '⚠ No sales entered since 18 Sep — cash and udhaar may be out of date',
  '⚠ Books last updated 27 Sep',
])
assert.deepEqual(staleWarnings({ newest_entry_on: '2026-10-03', newest_sale_on: '2026-10-02', sales_stale: false, books_stale: false }), [])
assert.deepEqual(staleWarnings({ newest_entry_on: null, newest_sale_on: null, sales_stale: true, books_stale: true }), [
  '⚠ No sales entered yet — cash and udhaar may be out of date',
  '⚠ No entries in the books yet',
])
console.log('telegram parser check: OK')
