-- Sale stock test (ledger fix B). Run as postgres. Always ends with an exception, so nothing is kept
-- (it uses up invoice and event numbers). Look for "B TEST PASS".
-- The sale form offers only products with open stock at KHANEWAL_PLANT (where record_udhaar_sale sends salt from).
-- Expected stock is the figure on 3 Oct 2026; update it when the stock changes.
do $t$
declare
  problems text[] := '{}'; stock jsonb; r jsonb; msg text; ok_rock text; ok_bulk text;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  -- what the sale form reads: open batches with stock at the plant, per product
  select jsonb_object_agg(product_code, kg) into stock from (
    select product_code, sum(onhand_grams) / 1000.0 kg from public.v_batches
     where location_code = 'KHANEWAL_PLANT' and status = 'open' and onhand_grams > 0 group by 1) x;
  if stock is distinct from '{"SALT_ROCK": 15078.0, "SALT_BULK": 9817.5}'::jsonb then problems := problems || format('stock %s', stock); end if;
  -- a grade with no stock is refused
  begin
    perform public.record_udhaar_sale('Test Customer B', '[{"product_code": "SALT_ROCK_OTHER", "qty_kg": 600, "line_total_paisa": 500000}]',
                                      0, null, current_date, 'test B', 'test-B-1', null);
    problems := problems || 'sale of a 0-stock grade was accepted'::text;
  exception when others then msg := sqlerrm;
  end;
  -- the two products in stock can be sold
  r := public.record_udhaar_sale('Test Customer B', '[{"product_code": "SALT_BULK", "qty_kg": 600, "line_total_paisa": 500000}]',
                                 0, null, current_date, 'test B', 'test-B-2', null);
  ok_bulk := r->>'sale_ref';
  r := public.record_udhaar_sale('Test Customer B', '[{"product_code": "SALT_ROCK", "qty_kg": 40, "line_total_paisa": 50000}]',
                                 0, null, current_date, 'test B', 'test-B-3', null);
  ok_rock := r->>'sale_ref';
  reset role;
  if cardinality(problems) = 0 then
    raise exception 'B TEST PASS. Stock at plant: %. 0-stock refusal: "%". Sold fine: % and %', stock, msg, ok_bulk, ok_rock;
  end if;
  raise exception 'B TEST FAIL: %', to_jsonb(problems);
end $t$;
