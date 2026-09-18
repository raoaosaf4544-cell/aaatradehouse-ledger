import { supabase } from './supabase'
import type {
  AccountBalance,
  EventRow,
  LedgerEntryRow,
  PostEventInput,
  ReviewItem,
  StockOnHand,
} from './types'

/**
 * Data-access layer over the `app` schema.
 * Rules:
 *  - Every write goes through app.post_event (guarded, append-only).
 *  - Every read comes from derived views or direct row selects — the DB is the
 *    single calculator; the client never re-derives balances its own way.
 *  - Invariant violations surface as thrown errors carrying the DB's exact message.
 */

export class InvariantError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'InvariantError'
  }
}

type AccountRow = { id: number; code: string; name: string }

export class LedgerEngine {
  /** Events with totals (from app.v_events_with_party). */
  async listEvents(limit = 500): Promise<EventRow[]> {
    const { data, error } = await supabase
      .from('v_events_with_party')
      .select('*')
      .order('occurred_on', { ascending: false })
      .order('event_ref', { ascending: true })
      .limit(limit)
    if (error) throw new InvariantError(error.message)
    return data as EventRow[]
  }

  /** Account balances (from app.v_account_balances). */
  async accountBalances(): Promise<AccountBalance[]> {
    const { data, error } = await supabase
      .from('v_account_balances')
      .select('*')
      .order('code', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return data as AccountBalance[]
  }

  /** Stock on hand per batch/product/location (from app.v_stock_onhand). */
  async stockOnHand(): Promise<StockOnHand[]> {
    const { data, error } = await supabase
      .from('v_stock_onhand')
      .select('*')
      .order('batch_code', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return data as StockOnHand[]
  }

  /** Open review-queue items (from public.v_review_queue). */
  async openReviewItems(): Promise<ReviewItem[]> {
    const { data, error } = await supabase
      .from('v_review_queue')
      .select('*')
      .eq('status', 'open')
      .order('id', { ascending: true })
      .limit(200)
    if (error) throw new InvariantError(error.message)
    return data as ReviewItem[]
  }

  /**
   * Ledger lines for given events (from public.v_ledger_lines — account codes
   * resolved server-side).
   */
  async eventLines(eventIds: number[]): Promise<Map<number, LedgerEntryRow[]>> {
    const result = new Map<number, LedgerEntryRow[]>()
    if (eventIds.length === 0) return result

    const { data, error } = await supabase
      .from('v_ledger_lines')
      .select('id, event_id, entry_seq, debit_paisa, credit_paisa, account_code, account_name')
      .in('event_id', eventIds)
      .order('entry_seq', { ascending: true })
    if (error) throw new InvariantError(error.message)

    for (const l of (data ?? []) as LedgerEntryRow[]) {
      const list = result.get(l.event_id) ?? []
      list.push(l)
      result.set(l.event_id, list)
    }
    return result
  }

  /** Post a balanced event through the guarded RPC. Returns the new event_ref. */
  async postEvent(input: PostEventInput): Promise<string> {
    if (input.lines.length < 2) {
      throw new InvariantError('A posting needs at least two ledger lines.')
    }
    if (!input.description.trim()) {
      throw new InvariantError('A description is required — every event must be explainable.')
    }
    const { data, error } = await supabase.rpc('post_event', {
      p_event_type: input.eventType,
      p_occurred_on: input.occurredOn,
      p_description: input.description,
      p_lines: input.lines,
      p_party_type: input.partyType ?? null,
      p_party_name: input.partyName ?? null,
      p_created_by: '11111111-1111-1111-1111-111111111111',
    })
    if (error) throw new InvariantError(error.message)
    return data as string
  }

  /**
   * Resolve a review item. NOTE: writes to review_queue require RLS policies /
   * auth; this method is wired for the Phase 4+ authenticated release.
   */
  async resolveReviewItem(id: number, note: string, dismissed = false): Promise<void> {
    if (!note.trim()) {
      throw new InvariantError('A resolution note is required — corrections must never be silent.')
    }
    const { error } = await supabase.rpc('resolve_review_item', {
      p_id: id,
      p_note: note,
      p_dismissed: dismissed,
    })
    if (error) throw new InvariantError(error.message)
  }
}

export const engine = new LedgerEngine()
