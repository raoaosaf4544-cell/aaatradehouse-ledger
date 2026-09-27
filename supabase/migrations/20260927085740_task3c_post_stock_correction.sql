-- Task 3c: take stock out of a named batch as a correction, the way a dispatch does:
-- kg leave the batch at the batch's own cost (Dr 4100 COGS / Cr the batch's inventory account) with a
-- matching 'out' movement, so kg AND value move together and the stock tie holds.
-- Same guard rules as post_correction: signed-in allowlisted user only (created_by = that user), own
-- idempotency key, new entries only, source_ref = the original, dated on or before the original.
-- The stock-not-negative trigger on movements still applies.
create or replace function public.post_stock_correction(
  p_original_ref    text,
  p_batch_code      text,
  p_qty_grams       bigint,
  p_idempotency_key text,
  p_note            text default null,
  p_occurred_on     date default null -- defaults to the original's date; may only be EARLIER or equal
) returns jsonb
language plpgsql security definer
set search_path = app
as $$
declare
  v_user     uuid := app.require_user();          -- "Not authorised" unless signed in and allowlisted
  v_orig     app.events%rowtype;
  v_batch    app.batches%rowtype;
  v_date     date;
  v_onhand   bigint;
  v_cost_ppk bigint;
  v_cogs     bigint;
  v_account  text;
  v_ref      text;
  v_event_id integer;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'INVARIANT VIOLATION: a correction needs its own idempotency key' using errcode = 'check_violation';
  end if;
  select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
  end if;

  select * into v_orig from app.events where event_ref = btrim(coalesce(p_original_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: original entry % not found', p_original_ref using errcode = 'check_violation';
  end if;
  if v_orig.source = 'correction' and v_orig.source_ref is not null then
    raise exception 'INVARIANT VIOLATION: % is itself a correction - correct the original entry instead', p_original_ref
      using errcode = 'check_violation';
  end if;

  v_date := coalesce(p_occurred_on, v_orig.occurred_on);
  if v_date > v_orig.occurred_on then
    raise exception 'INVARIANT VIOLATION: a correction may only be dated on or before the original (% is after %)',
      v_date, v_orig.occurred_on using errcode = 'check_violation';
  end if;

  if p_qty_grams is null or p_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: quantity must be positive' using errcode = 'check_violation';
  end if;
  select * into v_batch from app.batches where batch_code = btrim(coalesce(p_batch_code, '')) for update;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown batch %', p_batch_code using errcode = 'check_violation';
  end if;
  if v_batch.opened_on > v_date then
    raise exception 'INVARIANT VIOLATION: batch % did not exist yet on % (opened %)', v_batch.batch_code, v_date, v_batch.opened_on
      using errcode = 'check_violation';
  end if;
  select coalesce(sum(case when direction = 'in' then qty_grams when direction = 'out' then -qty_grams else 0 end), 0)
    into v_onhand from app.movements where batch_id = v_batch.id;
  if p_qty_grams > v_onhand then
    raise exception 'INVARIANT VIOLATION: batch % has only % kg on hand', v_batch.batch_code, (v_onhand / 1000.0)::numeric(12,1)
      using errcode = 'check_violation';
  end if;

  v_cost_ppk := app.batch_unit_cost_paisa_per_kg(v_batch.id);
  v_cogs := round(p_qty_grams::numeric * v_cost_ppk / 1000.0)::bigint;
  if v_cogs <= 0 then
    raise exception 'INVARIANT VIOLATION: batch % has no cost to take out', v_batch.batch_code using errcode = 'check_violation';
  end if;
  v_account := app.inventory_account(v_batch.product_id);

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name,
                          source, source_ref, created_by, idempotency_key)
  values (v_ref, 'dispatch', v_date,
          'Correction of ' || v_orig.event_ref || ' per paper register - stock out '
            || (p_qty_grams / 1000.0)::numeric(12,1) || ' kg from ' || v_batch.batch_code || ' at batch cost '
            || (v_cogs / 100.0)::numeric(14,2) || ' PKR'
            || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
          v_orig.party_type, v_orig.party_id, v_orig.party_name,
          'correction', v_orig.event_ref, v_user, p_idempotency_key)
  returning id into v_event_id;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, x.seq, a.id, x.dr, x.cr
  from (values (1, '4100', v_cogs, 0::bigint), (2, v_account, 0::bigint, v_cogs)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code;

  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, 1, v_batch.product_id, v_batch.id, v_batch.location_id, 'out', p_qty_grams, -v_cogs);

  return jsonb_build_object('event_ref', v_ref, 'occurred_on', v_date, 'source_ref', v_orig.event_ref,
                            'batch_code', v_batch.batch_code, 'qty_grams', p_qty_grams, 'cogs_paisa', v_cogs);
end $$;

revoke all on function public.post_stock_correction(text, text, bigint, text, text, date) from public, anon;
grant execute on function public.post_stock_correction(text, text, bigint, text, text, date) to authenticated;
