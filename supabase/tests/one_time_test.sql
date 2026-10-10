-- One-time tick test. Run as postgres. Always ends with an exception, so nothing is kept. Look for "ONE-TIME TEST PASS".
-- A ticked Money Out entry is saved with one_time = true; an unticked one stays null; a retry with the same key
-- returns the first entry. Books balance.
do $t$
declare a text; b text; c text; h record;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  a := public.post_event(p_event_type => 'expense', p_occurred_on => current_date, p_description => 'new signboard (test)',
         p_lines => '[{"account":"5800","debit":500000},{"account":"1000","credit":500000}]', p_party_type => 'other',
         p_idempotency_key => 'onetime-test-1', p_one_time => true);
  b := public.post_event('expense', current_date, 'tea (test)', '[{"account":"5500","debit":10000},{"account":"1000","credit":10000}]', 'other', null, null, 'onetime-test-2');
  c := public.post_event(p_event_type => 'expense', p_occurred_on => current_date, p_description => 'new signboard (test)',
         p_lines => '[{"account":"5800","debit":500000},{"account":"1000","credit":500000}]', p_party_type => 'other',
         p_idempotency_key => 'onetime-test-1', p_one_time => true);
  reset role;
  select * into h from app.v_ledger_health;
  if (select one_time from app.events where event_ref = a) is true and (select one_time from app.events where event_ref = b) is null
     and c = a and h.total_debit_paisa = h.total_credit_paisa then
    raise exception 'ONE-TIME TEST PASS: % ticked, % not, retry returned the same %', a, b, c;
  end if;
  raise exception 'ONE-TIME TEST FAIL';
end $t$;
