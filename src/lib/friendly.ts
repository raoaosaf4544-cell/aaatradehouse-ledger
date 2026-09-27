/**
 * Plain-language messages. Raw database text is never shown to the user: server refusals are matched
 * to a short sentence, anything unmatched gets a general one. Our own form checks (already plain) pass through.
 */
export type ErrorKind = 'save' | 'load'

type ErrLike = { message?: string; definite?: boolean; fromServer?: boolean }

const RULES: [RegExp, string][] = [
  [/Cash on Hand would go negative/i, 'Not enough cash in the books for this. Check the amount, or record the money that came in first.'],
  [/stock negative|not enough (compatible )?stock|insufficient stock|exceeds .*on hand/i, 'Not enough salt in stock for this.'],
  [/did not exist yet|opened on/i, 'That batch had not arrived yet on that date.'],
  [/exceeds .*outstanding receivable/i, 'That is more than this customer owes.'],
  [/unknown customer/i, 'Customer not found. Pick the customer from the list.'],
  [/mass|conservation/i, 'The weights do not add up: kg in must equal kg out plus wastage.'],
  [/JWT|token.*expired|PGRST30[0-9]/i, 'Your sign-in has expired. Sign out and sign in again.'],
  [/Not authorised|permission denied|42501/i, 'This login is not allowed to do this. Sign out and sign in again.'],
]

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
    for (const [re, text] of RULES) if (re.test(raw)) return text
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
