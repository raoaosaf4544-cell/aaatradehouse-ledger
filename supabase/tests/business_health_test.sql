-- Business health test. Run as postgres. Reads only, then ends with an exception. Look for "BUSINESS HEALTH TEST PASS".
-- The page's "Since start" figures must equal the same figures summed straight from the ledger:
-- sales (4000), cost of salt sold (4100), gross profit, running + one-time costs (other expense accounts), net profit
-- (= the books' profit and loss), drawings (3100). Product and customer breakdowns + adjustments add up to the totals.
do $t$
declare
  j jsonb; problems text[] := '{}';
  s bigint; c bigint; x bigint; oi bigint; d bigint; pl bigint;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  j := public.business_health(null, null);
  reset role;
  select -sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '4000'),
          sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '4100'),
          sum(le.debit_paisa - le.credit_paisa) filter (where a.type = 'expense' and a.code <> '4100'),
         -sum(le.debit_paisa - le.credit_paisa) filter (where a.type = 'income' and a.code <> '4000'),
          sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '3100'),
         -sum(le.debit_paisa - le.credit_paisa) filter (where a.type in ('income', 'expense'))
    into s, c, x, oi, d, pl
    from app.ledger_entries le join app.accounts a on a.id = le.account_id;
  if (j->'sales'->>'total_paisa')::bigint <> s then problems := problems || format('sales %s vs %s', j->'sales'->>'total_paisa', s); end if;
  if (j->'gross'->>'cogs_paisa')::bigint <> c then problems := problems || format('cogs %s vs %s', j->'gross'->>'cogs_paisa', c); end if;
  if (j->'gross'->>'profit_paisa')::bigint <> s - c then problems := problems || format('gross %s vs %s', j->'gross'->>'profit_paisa', s - c); end if;
  if (j->'costs'->>'running_paisa')::bigint + (j->'costs'->>'one_time_paisa')::bigint <> x then problems := problems || format('costs %s vs %s', j->'costs', x); end if;
  if (j->>'other_income_paisa')::bigint <> oi then problems := problems || format('other income %s vs %s', j->>'other_income_paisa', oi); end if;
  if (j->>'net_profit_paisa')::bigint <> pl or (j->>'ledger_profit_paisa')::bigint <> pl then problems := problems || format('net %s vs P&L %s', j->>'net_profit_paisa', pl); end if;
  if (j->'ghar'->>'drawings_paisa')::bigint <> d then problems := problems || format('drawings %s vs %s', j->'ghar'->>'drawings_paisa', d); end if;
  if (select sum((p->>'revenue_paisa')::bigint) from jsonb_array_elements(j->'sales'->'by_product') p) + (j->'sales'->>'adjustments_paisa')::bigint <> s then
    problems := problems || 'products + adjustments do not add up to sales'::text;
  end if;
  if cardinality(problems) = 0 then
    raise exception 'BUSINESS HEALTH TEST PASS. since start: sales %, cost of salt %, gross %, running %, one-time %, other income %, net %, drawings %',
      s, c, s - c, j->'costs'->>'running_paisa', j->'costs'->>'one_time_paisa', oi, pl, d;
  end if;
  raise exception 'BUSINESS HEALTH TEST FAIL: %', to_jsonb(problems);
end $t$;
