import { supabase } from './supabase'
import type {
  AccountBalance,
  EventRow,
  LedgerEntryRow,
  PostEventInput,
  ProcessRunResult,
  Product,
  PurchaseResult,
  ReviewItem,
  StockOnHand,
  Location,
  BatchRow,
  GradeOutput,
  Customer,
  SaleRow,
  DispatchAllocationRow,
  DebtorRow,
  FifoBatch,
  AccountLineRow,
  SaleResult,
  DispatchResult,
  DispatchLineInput,
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
  /** app.users.id of the signed-in person; set by App after login via current_app_user(). */
  userId: string | null = null

  private createdBy(): string {
    if (!this.userId) throw new InvariantError('Not signed in — please sign in again before recording.')
    return this.userId
  }

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

  /** All batches with on-hand, value and wastage (from public.v_batches). */
  async batches(): Promise<BatchRow[]> {
    const { data, error } = await supabase
      .from('v_batches')
      .select('*')
      .order('opened_on', { ascending: false })
    if (error) throw new InvariantError(error.message)
    return data as BatchRow[]
  }

  /** Active products for dropdowns. */
  async products(): Promise<Product[]> {
    const { data, error } = await supabase
      .from('v_products')
      .select('*')
      .eq('is_active', true)
      .order('code', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return data as Product[]
  }

  /** Active locations for dropdowns. */
  async locations(): Promise<Location[]> {
    const { data, error } = await supabase
      .from('v_locations')
      .select('*')
      .eq('is_active', true)
      .order('name', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return data as Location[]
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

  /**
   * Every ledger line of one account, with date/ref/description resolved from
   * the events table. Read-only transparency drill-down — nothing is derived,
   * every line is shown exactly as the append-only ledger holds it.
   */
  async accountLines(accountCode: string): Promise<AccountLineRow[]> {
    const { data: lines, error } = await supabase
      .from('v_ledger_lines')
      .select('event_id, entry_seq, debit_paisa, credit_paisa')
      .eq('account_code', accountCode)
      .order('event_id', { ascending: true })
      .order('entry_seq', { ascending: true })
    if (error) throw new InvariantError(error.message)

    const eventIds = [...new Set((lines ?? []).map((l: any) => l.event_id as number))]
    const eventsById = new Map<number, { occurred_on: string; event_ref: string; description: string }>()
    if (eventIds.length > 0) {
      const { data: evs, error: evErr } = await supabase
        .from('v_events_with_party')
        .select('id, occurred_on, event_ref, description')
        .in('id', eventIds)
      if (evErr) throw new InvariantError(evErr.message)
      for (const e of (evs ?? []) as any[]) {
        eventsById.set(e.id, { occurred_on: e.occurred_on, event_ref: e.event_ref, description: e.description })
      }
    }

    return (lines ?? []).map((l: any) => ({
      event_id: l.event_id,
      entry_seq: l.entry_seq,
      debit_paisa: l.debit_paisa,
      credit_paisa: l.credit_paisa,
      occurred_on: eventsById.get(l.event_id)?.occurred_on ?? '',
      event_ref: eventsById.get(l.event_id)?.event_ref ?? '',
      description: eventsById.get(l.event_id)?.description ?? '',
    })) as AccountLineRow[]
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
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as string
  }

  /**
   * Record a salt purchase. Creates a new batch (BATCH-00n) + PURCHASE_RECEIPT
   * movement and posts Dr Inventory / Cr Cash-or-AP through the guarded RPC.
   */
  async recordPurchase(input: {
    supplier: string
    productCode: string
    locationCode: string
    qtyKg: number
    landedCostPkr: number
    payCash: boolean
    occurredOn: string
    note?: string
  }): Promise<PurchaseResult> {
    if (!input.supplier.trim()) throw new InvariantError('Supplier name is required.')
    if (!(input.qtyKg > 0)) throw new InvariantError('Quantity must be positive.')
    if (!(input.landedCostPkr > 0)) throw new InvariantError('Landed cost must be positive.')
    const { data, error } = await supabase.rpc('record_purchase', {
      p_supplier: input.supplier.trim(),
      p_product_code: input.productCode,
      p_location_code: input.locationCode,
      p_qty_grams: Math.round(input.qtyKg * 1000),
      p_landed_cost_paisa: Math.round(input.landedCostPkr * 100),
      p_pay_cash: input.payCash,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as PurchaseResult
  }

  /**
   * Record a crush/processing run: consumes input batch at its weighted-average
   * cost, creates one child batch per output grade, and books wastage at its
   * direct weight-share of the total cost pool. The DB enforces mass and cost
   * conservation; any violation aborts the whole run atomically.
   */
  async recordProcessRun(input: {
    inputBatchCode: string
    inputQtyKg: number
    outputs: GradeOutput[]
    wastageKg: number
    conversionCostPkr: number
    payCash: boolean
    occurredOn: string
    note?: string
  }): Promise<ProcessRunResult> {
    if (!(input.inputQtyKg > 0)) throw new InvariantError('Input quantity must be positive.')
    if (input.outputs.length === 0) throw new InvariantError('At least one output grade is required.')
    if (!(input.wastageKg >= 0)) throw new InvariantError('Wastage cannot be negative.')
    const { data, error } = await supabase.rpc('record_process_run', {
      p_input_batch_code: input.inputBatchCode,
      p_input_qty_grams: Math.round(input.inputQtyKg * 1000),
      p_outputs: input.outputs.map((o) => ({
        product_code: o.product_code,
        qty_grams: Math.round(o.qty_kg * 1000),
        ...(o.value_pkr && o.value_pkr > 0 ? { value_paisa: Math.round(o.value_pkr * 100) } : {}),
      })),
      p_wastage_grams: Math.round(input.wastageKg * 1000),
      p_conversion_cost_paisa: Math.round(input.conversionCostPkr * 100),
      p_pay_cash: input.payCash,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as ProcessRunResult
  }

  /* ---------- Phase 3: Sales & Dispatch ---------- */

  /** Customers for the sale form dropdown (public.v_customers). */
  async customers(): Promise<Customer[]> {
    const { data, error } = await supabase
      .from('v_customers')
      .select('party_id, party_ref, name, phone')
      .eq('is_active', true)
      .order('name', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return (data ?? []).map((c: any) => ({ id: c.party_id, party_ref: c.party_ref, name: c.name, phone: c.phone, kind: 'customer' }))
  }

  /** Quick-add a customer through the guarded RPC. */
  async createCustomer(name: string, phone?: string): Promise<Customer> {
    if (!name.trim()) throw new InvariantError('Customer name is required.')
    const { data, error } = await supabase.rpc('create_customer', {
      p_name: name.trim(),
      p_phone: phone?.trim() || null,
      p_note: null,
    })
    if (error) throw new InvariantError(error.message)
    const created = (Array.isArray(data) ? data[0] : data) as Customer
    if (!created?.id) throw new InvariantError('Customer could not be created.')
    return created
  }

  /** How much advance credit this customer holds (public.v_advances). */
  async customerAdvanceBalance(partyId: number): Promise<number> {
    const { data, error } = await supabase
      .from('v_advances')
      .select('advance_balance_paisa')
      .eq('party_id', partyId)
      .maybeSingle()
    if (error) throw new InvariantError(error.message)
    return data?.advance_balance_paisa ?? 0
  }

  /** Invoices (public.v_sales) with dispatch progress and gross margin. */
  async sales(limit = 200): Promise<SaleRow[]> {
    const { data, error } = await supabase
      .from('v_sales')
      .select('*')
      .order('occurred_on', { ascending: false })
      .limit(limit)
    if (error) throw new InvariantError(error.message)
    return data as SaleRow[]
  }

  /** Per-batch COGS allocations (public.v_dispatch_allocations). */
  async dispatchAllocations(limit = 500): Promise<DispatchAllocationRow[]> {
    const { data, error } = await supabase
      .from('v_dispatch_allocations')
      .select('*')
      .order('occurred_on', { ascending: false })
      .limit(limit)
    if (error) throw new InvariantError(error.message)
    return data as DispatchAllocationRow[]
  }

  /** Who owes what (public.v_debtors). */
  async debtors(): Promise<DebtorRow[]> {
    const { data, error } = await supabase
      .from('v_debtors')
      .select('*')
      .order('outstanding_paisa', { ascending: false })
    if (error) throw new InvariantError(error.message)
    return data as DebtorRow[]
  }

  /**
   * FIFO pool for the dispatch form: open batches of this product at this
   * location, oldest first, with exact book-value unit cost. Direct SQL view
   * over app.fifo_pool so the client previews exactly what the engine will do.
   */
  async fifoPool(productCode: string, locationCode: string): Promise<FifoBatch[]> {
    const { data, error } = await supabase
      .from('v_batches')
      .select('id, batch_code, opened_on, onhand_grams, value_paisa')
      .eq('product_code', productCode)
      .eq('location_code', locationCode)
      .eq('status', 'open')
      .gt('onhand_grams', 0)
      .order('opened_on', { ascending: true })
    if (error) throw new InvariantError(error.message)
    return ((data ?? []) as { id: number; batch_code: string; opened_on: string; onhand_grams: number; value_paisa: number }[]).map(
      (b) => ({
        batch_id: b.id,
        batch_code: b.batch_code,
        opened_on: b.opened_on,
        onhand_grams: b.onhand_grams,
        unit_cost_ppk: b.onhand_grams > 0 ? Math.round(b.value_paisa / (b.onhand_grams / 1000)) : 0,
      }),
    )
  }

  /**
   * Record an invoice through record_sale (SECURITY DEFINER). Money math —
   * per-kg pricing, advance application, cash/AR split — happens in the DB.
   */
  async recordSale(input: {
    customerName: string
    items: { productCode: string; qtyKg: number; unitPricePkrPerKg: number }[]
    cashReceivedPkr: number
    customerPhone?: string
    occurredOn: string
    note?: string
  }): Promise<SaleResult> {
    if (!input.customerName.trim()) throw new InvariantError('Customer name is required.')
    if (input.items.length === 0) throw new InvariantError('At least one sale line is required.')
    if (!(input.cashReceivedPkr >= 0)) throw new InvariantError('Cash received cannot be negative.')
    const { data, error } = await supabase.rpc('record_sale', {
      p_party: input.customerName.trim(),
      p_items: input.items.map((it) => ({
        product_code: it.productCode,
        qty_grams: Math.round(it.qtyKg * 1000),
        unit_price_paisa_per_kg: Math.round(it.unitPricePkrPerKg * 100),
      })),
      p_cash_received_paisa: Math.round(input.cashReceivedPkr * 100),
      p_customer_phone: input.customerPhone?.trim() || null,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: null,
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as SaleResult
  }

  /**
   * Dispatch against an invoice through record_dispatch. FIFO allocation with
   * per-batch FOR UPDATE locks, exact book-value COGS, batch auto-close.
   */
  async recordDispatch(input: {
    saleRef: string
    lines: DispatchLineInput[]
    occurredOn: string
    note?: string
  }): Promise<DispatchResult> {
    if (input.lines.length === 0) throw new InvariantError('At least one dispatch line is required.')
    const { data, error } = await supabase.rpc('record_dispatch', {
      p_sale_ref: input.saleRef,
      p_lines: input.lines.map((l) => ({
        product_code: l.productCode,
        qty_grams: Math.round(l.qtyKg * 1000),
        location_code: l.locationCode,
        ...(l.mode === 'manual'
          ? {
              override_reason: l.overrideReason?.trim() || '',
              allocations: (l.allocations ?? []).map((a) => ({
                batch_code: a.batchCode,
                qty_grams: Math.round(a.qtyKg * 1000),
              })),
            }
          : {}),
      })),
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: null,
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as DispatchResult
  }

  /**
   * ONE-TAP udhaar sale (public.record_udhaar_sale): invoice + immediate FIFO
   * dispatch in one transaction. Pass either unitPricePkrPerKg or lineTotalPkr
   * per line — the DB books the exact total when lineTotalPkr is given.
   */
  async recordUdhaarSale(input: {
    customerName: string
    items: { productCode: string; qtyKg: number; unitPricePkrPerKg?: number; lineTotalPkr?: number }[]
    cashReceivedPkr: number
    customerPhone?: string
    occurredOn: string
    note?: string
  }): Promise<{ sale_ref: string; dispatch_ref: string; revenue_paisa: number; cash_paisa: number; ar_paisa: number; cogs_paisa: number; party_created: boolean } | { duplicate: boolean; sale_ref: string }> {
    if (!input.customerName.trim()) throw new InvariantError('Customer name is required.')
    if (input.items.length === 0) throw new InvariantError('At least one sale line is required.')
    if (!(input.cashReceivedPkr >= 0)) throw new InvariantError('Cash received cannot be negative.')
    const { data, error } = await supabase.rpc('record_udhaar_sale', {
      p_party: input.customerName.trim(),
      p_items: input.items.map((it) => {
        const qtyKg = Math.round(it.qtyKg * 1000) / 1000
        if (it.lineTotalPkr !== undefined && it.lineTotalPkr > 0) {
          return { product_code: it.productCode, qty_kg: qtyKg, line_total_paisa: Math.round(it.lineTotalPkr * 100) }
        }
        if (!(it.unitPricePkrPerKg && it.unitPricePkrPerKg > 0)) {
          throw new InvariantError('Each line needs a price per kg or a line total.')
        }
        return { product_code: it.productCode, qty_kg: qtyKg, unit_price_paisa_per_kg: Math.round(it.unitPricePkrPerKg * 100) }
      }),
      p_cash_received_paisa: Math.round(input.cashReceivedPkr * 100),
      p_customer_phone: input.customerPhone?.trim() || null,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: null,
      p_created_by: this.createdBy(),
    })
    if (error) throw new InvariantError(error.message)
    return data as { sale_ref: string; dispatch_ref: string; revenue_paisa: number; cash_paisa: number; ar_paisa: number; cogs_paisa: number; party_created: boolean } | { duplicate: boolean; sale_ref: string }
  }

  /** Record a customer payment (Dr Cash / Cr AR) through the guarded RPC. */
  async recordCustomerPayment(input: {
    customerName: string
    amountPkr: number
    occurredOn: string
    note?: string
  }): Promise<void> {
    if (!(input.amountPkr > 0)) throw new InvariantError('Payment amount must be positive.')
    if (!input.customerName.trim()) throw new InvariantError('Customer name is required.')
    const { error } = await supabase.rpc('record_customer_payment', {
      p_customer: input.customerName.trim(),
      p_amount_paisa: Math.round(input.amountPkr * 100),
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_created_by: this.createdBy(),
      p_idempotency_key: null,
    })
    if (error) throw new InvariantError(error.message)
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
