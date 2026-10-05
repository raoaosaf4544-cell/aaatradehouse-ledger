/**
 * Plain-language messages. Raw database text is never shown to the user: every known refusal is turned into a short
 * sentence that gives the real reason (with its numbers); anything unmatched gets a general one (and Sentry gets the
 * raw text, so a rule can be added). Our own form checks (already plain) pass through.
 */
export type ErrorKind = 'save' | 'load'

type ErrLike = { message?: string; definite?: boolean; fromServer?: boolean }

// ponytail: names by code for messages only; add a line here when a product is added
const PRODUCT_NAMES: Record<string, string> = {
  SALT_ROCK: 'Rock Salt (whole / dalay)',
  SALT_BULK: 'Fine Powder Salt',
  SALT_ROCK_COARSE: 'Coarse Salt (daana)',
}
const product = (code: string) => PRODUCT_NAMES[code] ?? code
const kg = (s: string) => Number(s).toLocaleString('en-PK', { maximumFractionDigits: 3 })
const day = (iso: string) => {
  const [y, mo, d] = iso.split('-').map(Number)
  return `${d} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][mo - 1]} ${y}`
}
const rs = (s: string) => `Rs ${Number(s).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`

/** Delete / correct / edit need a real reason; the database checks the same rule (app.reason_problem). */
export const REASON_RULE = 'Write a short reason, at least 4 letters (not only numbers).'
export const reasonProblem = (reason: string) => ((reason.match(/\p{L}/gu)?.length ?? 0) < 4 ? REASON_RULE : null)

type Rule = [RegExp, string | ((m: RegExpMatchArray) => string)]

const RULES: Rule[] = [
  // money
  [/Cash on Hand would go negative/i, 'Not enough cash in the books for this. Check the amount, or record the money that came in first.'],
  [/payment ([\d.]+) exceeds (.+?)s outstanding receivable of ([\d.]+)/i,
    (m) => `That is more than ${m[2].replace(/'$/, '')} owes (${rs(m[3])}). Extra money goes on Customer Advances.`],
  [/exceeds .*outstanding receivable/i, 'That is more than this customer owes.'],
  [/cash \(.*\) plus advance application .* exceeds invoice total/i, 'Cash received plus advance is more than the bill total.'],
  [/advance application .* exceeds available advance/i, 'The customer does not hold that much advance.'],
  [/cost components sum to ([\d.]+) but landed cost is ([\d.]+)/i,
    (m) => `The cost parts add up to ${rs(m[1])} but the total cost is ${rs(m[2])} — they must match.`],
  [/unbalanced|not balanced/i, 'Debits and credits do not match, so nothing was saved.'],

  // stock
  [/insufficient eligible stock of (\S+) at \S+ - need ([\d.]+) kg more/i,
    (m) => `Not enough ${product(m[1])} in stock — ${kg(m[2])} kg short.`],
  [/batch (\S+) has only ([\d.]+) kg on hand/i, (m) => `Batch ${m[1]} has only ${kg(m[2])} kg left.`],
  [/only ([\d.]+) kg of (.+) in batch (\S+)/i, (m) => `Only ${kg(m[1])} kg of ${m[2]} in batch ${m[3]}.`],
  [/stock negative for batch/i, 'Not enough salt in stock for this.'],
  [/not enough (compatible )?stock|insufficient stock|exceeds .*on hand/i, 'Not enough salt in stock for this.'],
  [/line \S+ requests ([\d.]+) kg but invoice (\S+) has only ([\d.]+) kg left/i,
    (m) => `Invoice ${m[2]} has only ${kg(m[3])} kg left to send, not ${kg(m[1])} kg.`],
  [/batch (\S+) did not exist yet on (\d{4}-\d\d-\d\d) \(it arrived (\d{4}-\d\d-\d\d)\)/i,
    (m) => `Batch ${m[1]} had not arrived yet on ${day(m[2])} — it arrived ${day(m[3])}. Change the date or the batch.`],
  [/did not exist yet|opened on/i, 'That batch had not arrived yet on that date.'],
  [/date (\d{4}-\d\d-\d\d) is in the future/i, (m) => `${day(m[1])} is in the future. Pick today or an earlier day.`],
  [/is before the books start/i, 'The books start on 23 Aug 2026. Pick that day or later.'],
  [/CONCURRENCY/, 'Someone saved a change to the same stock at the same moment — nothing was saved. Tap Retry.'],

  // crush runs
  [/crushed kg \(([\d.]+)\) \+ wastage \(([\d.]+)\) must equal kg in \(([\d.]+)\)/i,
    (m) => `Crushed kg (${kg(m[1])}) + wastage (${kg(m[2])}) must equal kg in (${kg(m[3])}).`],
  [/mass conservation|conservation failed/i, 'The weights do not add up: kg in must equal kg out plus wastage.'],
  [/on credit needs the supplier/i, 'On credit: pick or type who is owed the crushing cost.'],
  [/only rock salt can be crushed/i, 'Only Rock Salt can be crushed.'],
  [/(.+) is not a crush output grade/i, (m) => `${m[1].replace(/^INVARIANT VIOLATION: /, '')} cannot come out of a crush — choose Fine Powder or Coarse.`],
  [/(.+) is listed twice/i, (m) => `${m[1].replace(/^INVARIANT VIOLATION: /, '')} is listed twice — put all its kg on one line.`],

  // missing or wrong figures
  [/supplier name is required/i, 'Supplier name is required.'],
  [/customer( name)? is required/i, 'Customer name is required.'],
  [/unknown customer/i, 'Customer not found. Pick the customer from the list.'],
  [/unknown (output )?product( code)?/i, 'That product is no longer offered. Pick one from the list.'],
  [/unknown (input )?batch/i, 'That batch was not found. Pick one from the list.'],
  [/(unit price|line total) must be positive/i, 'Each line needs a bill amount more than 0.'],
  [/landed cost must be positive/i, 'The cost must be more than 0.'],
  [/(payment|advance) amount must be positive/i, 'The amount must be more than 0.'],
  [/quantity must be positive|quantities must be positive|kg in must be more than 0|needs kg more than 0/i, 'The kg must be more than 0.'],
  [/(wastage|conversion cost|cash received) cannot be negative/i, (m) => `The ${m[1].toLowerCase()} cannot be below 0.`],
  [/at least one (output grade|sale line|dispatch line) is required/i, (m) => `Add at least one ${m[1].replace(' line', '').replace('output ', '')} line.`],
  [/null value in column/i, 'A required figure was missing, so nothing was saved.'],

  // corrections and review
  [/nothing changed - the correct version is the same/i, 'Nothing changed — the correct version is the same as the entry.'],
  [/(\S+) was already corrected by (.+?)\. Delete that correction first/i,
    (m) => `${m[1]} was already corrected by ${m[2]}. Delete that correction first (Delete shows what changes), then correct ${m[1]}.`],
  [/Only money entries can be corrected here/i, 'Only money entries can be corrected here. For sales, purchases, crush runs and payments: delete it and enter it again.'],
  [/cannot be used in a money-entry correction/i, 'That account cannot be used here (customer, supplier, advance or stock accounts).'],
  [/write why this entry is being corrected/i, 'Write why this entry is being corrected.'],
  [/at least 4 letters/i, REASON_RULE],
  [/may only be dated on or before the original/i, 'A correction cannot be dated after the entry it corrects.'],
  [/is itself a correction/i, 'That entry is already a correction — correct the original entry instead.'],
  [/review item .* is not open/i, 'That review item was already resolved.'],
  [/resolution note is required/i, 'Write a short note saying what was fixed.'],

  // sign-in
  [/JWT|token.*expired|PGRST30[0-9]/i, 'Your sign-in has expired. Sign out and sign in again.'],
  [/Not authorised|permission denied|42501/i, 'This login is not allowed to do this. Sign out and sign in again.'],
]

/** The plain sentence for a database refusal, or null when no rule knows it. */
export function serverReason(raw: string): string | null {
  for (const [re, text] of RULES) {
    const m = raw.match(re)
    if (m) return typeof text === 'string' ? text : text(m)
  }
  return null
}

export function friendlyMessage(error: unknown, kind: ErrorKind): string {
  if (typeof error === 'string') return error // our own message
  const e = (error ?? {}) as ErrLike
  const raw = e.message ?? ''
  if (e.definite === false) {
    // sent, but no answer came back (no signal / timeout)
    return kind === 'save'
      ? 'No signal — not confirmed. Tap Retry: it never saves twice.'
      : 'No signal — could not load. Check signal and try again.'
  }
  if (e.fromServer) {
    // the delete / restore functions answer in plain words written for this app: show them as they are
    if (/^Cannot (delete|restore):/.test(raw)) return raw.replace(/^Cannot (delete|restore): /, '')
    const reason = serverReason(raw)
    if (reason) return kind === 'save' ? `Not saved: ${reason}` : reason
    return kind === 'save'
      ? 'The books refused this entry, so nothing was saved. Check the numbers and try again.'
      : 'Could not load this screen. Try again.'
  }
  if (e.definite === true && raw) return raw // our own plain check (e.g. "Supplier name is required.")
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    return kind === 'save' ? 'No signal — nothing saved, tap Retry' : 'No signal — could not load. Check signal and try again.'
  }
  return kind === 'save'
    ? 'Something went wrong, so nothing was saved. Tap Retry.'
    : 'Something went wrong loading this screen. Try again.'
}
