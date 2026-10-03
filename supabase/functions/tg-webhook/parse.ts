// Telegram message parsing and reply wording for the JARVIS phone channel. Pure: no I/O, no imports.
// Self-check: bun scripts/check-tg-parse.ts

export type Command = 'cash' | 'udhaar' | 'runway' | 'waiting' | 'status' | 'help'

export type Parsed =
  | { kind: 'pair'; code: string }
  | { kind: 'decision'; decision: 'approve' | 'reject'; aprId: string }
  | { kind: 'seen'; outboxId: number }
  | { kind: 'snooze'; minutes: number }
  | { kind: 'wake' }
  | { kind: 'command'; name: Command }
  | { kind: 'unknown' }

const COMMANDS: readonly Command[] = ['cash', 'udhaar', 'runway', 'waiting', 'status', 'help']
export const SNOOZE_DEFAULT_MIN = 120
export const SNOOZE_MAX_MIN = 24 * 60
export const LAPTOP_FRESH_MS = 2 * 60 * 1000
export const UNKNOWN_REPLY = "Got it — I'll answer when AI chat is switched on"

// "2h", "30m", "1.5 hours", "45 min" -> minutes (1 .. 24h); null when no duration is written
export function duration(s: string): number | null {
  const m = /(?<![\d.])(\d{1,3}(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|mins?|minutes?)\b/i.exec(s)
  if (!m) return null
  const n = Number(m[1]) * (m[2].toLowerCase().startsWith('h') ? 60 : 1)
  return Math.min(SNOOZE_MAX_MIN, Math.max(1, Math.round(n)))
}

function decision(word: string, num: string): Parsed {
  return { kind: 'decision', decision: word.toLowerCase() as 'approve' | 'reject', aprId: `APR-${Number(num)}` }
}

const DECISION = /^(approve|reject)\s+(?:apr[-\s]?)?(\d{1,9})$/i
const SLEEP = /\b(sleep|sleeping|don['’]?t\s+disturb|dnd)\b/i

export function parseMessage(raw: string): Parsed {
  const text = raw.trim()
  const slash = /^\/([a-z]+)(?:@\w+)?(?:\s+([\s\S]*))?$/i.exec(text) // "/cash@MyBot" works too
  if (slash) {
    const cmd = slash[1].toLowerCase()
    const arg = (slash[2] ?? '').trim()
    if (cmd === 'pair') return arg ? { kind: 'pair', code: arg } : { kind: 'unknown' }
    if (cmd === 'snooze') return { kind: 'snooze', minutes: duration(arg) ?? SNOOZE_DEFAULT_MIN }
    if (cmd === 'wake') return { kind: 'wake' }
    if (cmd === 'start') return { kind: 'command', name: 'help' }
    if (cmd === 'approve' || cmd === 'reject') {
      const d = DECISION.exec(`${cmd} ${arg}`)
      return d ? decision(d[1], d[2]) : { kind: 'unknown' }
    }
    if ((COMMANDS as readonly string[]).includes(cmd)) return { kind: 'command', name: cmd as Command }
    return { kind: 'unknown' }
  }
  const d = DECISION.exec(text)
  if (d) return decision(d[1], d[2])
  if (SLEEP.test(text)) return { kind: 'snooze', minutes: duration(text) ?? SNOOZE_DEFAULT_MIN }
  return { kind: 'unknown' }
}

// Inline-button data (Telegram allows 64 bytes). The notifier builds it, the webhook reads it.
export const CB = {
  approve: (aprId: string) => `d:approve:${aprId}`,
  reject: (aprId: string) => `d:reject:${aprId}`,
  seen: (outboxId: number) => `seen:${outboxId}`,
}

export function parseCallback(data: string): Parsed {
  let m = /^d:(approve|reject):APR-(\d{1,9})$/.exec(data)
  if (m) return decision(m[1], m[2])
  m = /^seen:(\d{1,18})$/.exec(data)
  if (m) return { kind: 'seen', outboxId: Number(m[1]) }
  return { kind: 'unknown' }
}

// "14:30, Sat 3 Oct" in Pakistan time
export function fmtKarachi(d: Date): string {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Karachi', weekday: 'short', day: 'numeric', month: 'short',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(d).map((x) => [x.type, x.value]),
  )
  return `${p.hour}:${p.minute}, ${p.weekday} ${p.day} ${p.month}`
}

// '2026-09-18' -> '18 Sep' (a date only, so no time-zone shift)
export function fmtDay(iso: string): string {
  const [, m, d] = iso.split('-').map(Number)
  return `${d} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1]}`
}

export function snoozeReply(until: Date): string {
  return `Snoozed until ${fmtKarachi(until)} (Pakistan time). No rings until then — send /wake to cancel.`
}

export function decisionReply(p: { decision: 'approve' | 'reject'; aprId: string }, lastSeen: Date | null, now: Date): string {
  const word = p.decision === 'approve' ? 'Approved' : 'Rejected'
  if (lastSeen && now.getTime() - lastSeen.getTime() <= LAPTOP_FRESH_MS) return `${word} ${p.aprId} — the laptop will pick it up now.`
  const seen = lastSeen ? `last seen ${fmtKarachi(lastSeen)}` : 'not seen yet'
  return p.decision === 'approve'
    ? `${word} ${p.aprId} — will run when the laptop is on (${seen})`
    : `${word} ${p.aprId} — the laptop will be told when it is on (${seen})`
}

// Lines that go above every figure (commands and briefs). The rule itself lives in app.v_books_freshness.
export function staleWarnings(f: { newest_entry_on: string | null; newest_sale_on: string | null; sales_stale: boolean; books_stale: boolean }): string[] {
  const out: string[] = []
  if (f.sales_stale) {
    out.push(f.newest_sale_on
      ? `⚠ No sales entered since ${fmtDay(f.newest_sale_on)} — cash and udhaar may be out of date`
      : '⚠ No sales entered yet — cash and udhaar may be out of date')
  }
  if (f.books_stale) out.push(f.newest_entry_on ? `⚠ Books last updated ${fmtDay(f.newest_entry_on)}` : '⚠ No entries in the books yet')
  return out
}
