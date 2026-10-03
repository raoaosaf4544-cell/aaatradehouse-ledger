-- Phone channel security and figures test. Run as postgres (Supabase SQL editor or MCP).
-- It ALWAYS ends with an exception, so everything it does is rolled back. Look for "JARVIS TEST PASS".
-- Checks:
--   1. jarvis.read_cash() / read_runway() / read_udhaar() give exactly the CFO figures the JARVIS login reads
--      (public.v_account_totals + v_cash_days, v_cfo_runway, v_udhaar_aging).
--   2. jarvis_cloud: the three read functions and both jarvis views work; SELECT/INSERT/UPDATE/DELETE on every app.* and public.* relation and
--      a call of every app.* and public.* function is refused with a permission error.
--   3. jarvis_cloud on its own tables: only the granted writes work; pairing happens once.
--   4. The JARVIS login: the six RPCs work (dedupe, claim new->taken, finish once); the jarvis tables, views and
--      read functions are refused; app.* writes are refused.
--   5. Rao's login and anon: the six RPCs are refused.
--   6. jarvis_mirror_approval accepts exactly the laptop's six statuses.
--   7. Stale-books flags: the CFO's public.v_books_freshness and the bot's v_status agree with a recount from the tables.
do $test$
declare
  c_jarvis constant text := '{"sub":"f188c46e-4ca5-4d0d-adfc-848c1328d4e1","role":"authenticated"}';
  c_rao    constant text := '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}';
  c_six    constant text[] := array[
    'select public.jarvis_notify(''test'', ''t'', ''b'', false)',
    'select public.jarvis_heartbeat(null)',
    'select public.jarvis_shutdown_clean()',
    'select public.jarvis_mirror_approval(''APR-1'', ''t'', ''d'', ''pending'', ''h'')',
    'select * from public.jarvis_claim_decisions()',
    'select public.jarvis_finish_decision(1, true, ''x'')'];
  c_statuses constant text[] := array['pending', 'approved', 'rejected', 'executing', 'done', 'failed'];
  expected jsonb; actual jsonb; problems text[] := '{}'; checks int := 0; fresh jsonb; figures jsonb;
  q text; qs text[]; qs_dml text[]; v_id bigint; v_id2 bigint; n int; v_claim jsonb;
begin
  -- 1. The CFO figures, as the JARVIS login reads them (the CFO uses this login).
  perform set_config('request.jwt.claims', c_jarvis, true);
  set local role authenticated;
  expected := jsonb_build_object(
    'cash', jsonb_build_object(
      'cash_paisa', (select t.debit_paisa - t.credit_paisa from public.v_account_totals t where t.code = '1000'),
      'today_in_paisa', coalesce((select d.in_paisa from public.v_cash_days d where d.occurred_on = (now() at time zone 'Asia/Karachi')::date), 0),
      'today_out_paisa', coalesce((select d.out_paisa from public.v_cash_days d where d.occurred_on = (now() at time zone 'Asia/Karachi')::date), 0)),
    'runway', (select to_jsonb(r) from public.v_cfo_runway r),
    'udhaar', (select jsonb_agg(jsonb_build_object('customer_name', u.customer_name, 'outstanding_paisa', u.outstanding_paisa,
                 'unpaid_over_7d_paisa', u.unpaid_over_7d_paisa, 'last_sale_on', u.last_sale_on) order by u.customer_name)
                 from public.v_udhaar_aging u));
  reset role;
  figures := expected;
  if expected->'runway' is null or expected->'cash'->>'cash_paisa' is null then
    problems := problems || 'the JARVIS login sees no CFO figures'::text;
  end if;

  set local role jarvis_cloud;
  actual := jsonb_build_object(
    'cash', (select to_jsonb(c) - 'as_of' from jarvis.read_cash() c),
    'runway', (select to_jsonb(r) from jarvis.read_runway() r),
    'udhaar', (select jsonb_agg(to_jsonb(u) order by u.customer_name) from jarvis.read_udhaar() u));
  perform 1 from jarvis.v_waiting;
  perform 1 from jarvis.v_status;
  reset role;
  checks := checks + 1;
  if actual is distinct from expected or (actual->'cash'->'cash_paisa') is distinct from (actual->'runway'->'cash_paisa') then
    problems := problems || format('figures differ: expected %s, jarvis views gave %s', expected, actual);
  end if;

  -- 2. Everything in app.* and public.* is refused to jarvis_cloud.
  select array_agg(s.q), array_agg(s.q) filter (where s.dml and s.nsp = 'app') into qs, qs_dml from (
    select n.nspname nsp, false dml, format('select 1 from %I.%I limit 0', n.nspname, c.relname) q
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname in ('app', 'public') and c.relkind in ('r', 'v', 'm', 'p', 'f')
    union all
    select n.nspname, true, x.q
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      cross join lateral (select a.attname from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                             and a.attidentity = '' and a.attgenerated = ''  -- identity columns refuse before the permission check
                           order by a.attnum limit 1) a
      cross join lateral (values (format('insert into %I.%I default values', n.nspname, c.relname)),
                                 (format('update %I.%I set %I = %I where false', n.nspname, c.relname, a.attname, a.attname)),
                                 (format('delete from %I.%I where false', n.nspname, c.relname))) x(q)
     where n.nspname in ('app', 'public') and c.relkind in ('r', 'p')
    union all
    select n.nspname, false,
           format(case p.prokind when 'p' then 'call %I.%I(%s)' else 'select %I.%I(%s)' end, n.nspname, p.proname, coalesce(x.args, ''))
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      cross join lateral (select string_agg(format('null::%s', format_type(t, null)), ', ' order by o) args
                            from unnest(p.proargtypes) with ordinality u(t, o)) x
     where n.nspname in ('app', 'public') and p.prokind in ('f', 'p', 'a')
  ) s;

  set local role jarvis_cloud;
  foreach q in array qs loop
    checks := checks + 1;
    begin
      execute q;
      problems := problems || ('jarvis_cloud ALLOWED: ' || q);
    exception
      when insufficient_privilege then null;
      when others then problems := problems || format('jarvis_cloud %s (not a permission error): %s', sqlstate, q);
    end;
  end loop;
  reset role;

  -- 4a. The JARVIS login: notify (with dedupe), heartbeat, mirror an approval; jarvis tables and app writes refused.
  perform set_config('request.jwt.claims', c_jarvis, true);
  set local role authenticated;
  v_id  := public.jarvis_notify('info', 'Test message', 'body', true, null, 'test:dedupe');
  v_id2 := public.jarvis_notify('info', 'Test message again', 'body', true, null, 'test:dedupe');
  checks := checks + 1;
  if v_id is null or v_id <> v_id2 then problems := problems || format('dedupe failed: %s vs %s', v_id, v_id2); end if;
  perform public.jarvis_heartbeat('test task');
  perform public.jarvis_mirror_approval('APR-999999', 'test_tool', 'Test approval', 'pending', 'hash');
  -- 6. the laptop's six statuses are accepted; anything else is refused
  foreach q in array c_statuses loop
    checks := checks + 1;
    begin
      perform public.jarvis_mirror_approval('APR-999998', 'test_tool', 'Status test', q, 'hash');
    exception when others then
      problems := problems || format('laptop status %s refused: %s', q, sqlerrm);
    end;
  end loop;
  foreach q in array array['running', 'expired', 'cancelled', 'Pending'] loop
    checks := checks + 1;
    begin
      perform public.jarvis_mirror_approval('APR-999998', 'test_tool', 'Status test', q, 'hash');
      problems := problems || ('status accepted but not a laptop value: ' || q);
    exception when check_violation then null;
    end;
  end loop;
  -- 7. the CFO's freshness view, as this login reads it
  select to_jsonb(f) - 'as_of' into fresh from public.v_books_freshness f;
  foreach q in array array['select 1 from jarvis.outbox', 'select 1 from jarvis.state', 'select * from jarvis.read_cash()', 'select 1 from jarvis.v_status',
                           'insert into jarvis.audit (source, event) values (''x'', ''x'')'] || qs_dml loop
    checks := checks + 1;
    begin
      execute q;
      problems := problems || ('JARVIS login ALLOWED: ' || q);
    exception
      when insufficient_privilege then null;
      when others then problems := problems || format('JARVIS login %s (not a permission error): %s', sqlstate, q);
    end;
  end loop;
  reset role;

  -- 3. jarvis_cloud on its own tables.
  set local role jarvis_cloud;
  update jarvis.outbox set sent_at = now(), tg_message_id = 1, seen_at = now() where id = v_id;
  insert into jarvis.outbox (kind, title, urgent, dedupe_key) values ('approval_wait', 'APR-999999 waiting 2h+', true, 'test:wait:APR-999999');
  update jarvis.approvals_mirror set escalated_at = now() where apr_id = 'APR-999999';
  insert into jarvis.audit (source, event, detail) values ('test', 'test', '{"ok": true}');
  insert into jarvis.inbox (apr_id, decision) values ('APR-999999', 'approve');
  update jarvis.state set snooze_until = now() + interval '2 hours', updated_at = now();
  update jarvis.state set owner_chat_id = 111, paired_at = now() where owner_chat_id is null;
  checks := checks + 1;
  if (select owner_chat_id from jarvis.state) is null then problems := problems || 'pairing did not take'::text; end if;
  foreach q in array array[
    'update jarvis.outbox set title = ''x''',
    'update jarvis.outbox set urgent = false',
    'delete from jarvis.outbox',
    'update jarvis.approvals_mirror set status = ''approved''',
    'delete from jarvis.approvals_mirror',
    'insert into jarvis.approvals_mirror (apr_id, tool, description, status, args_hash) values (''APR-1'', ''t'', ''d'', ''pending'', ''h'')',
    'update jarvis.inbox set status = ''done''',
    'delete from jarvis.inbox',
    'update jarvis.state set last_seen_at = now()',
    'update jarvis.state set clean_shutdown = false',
    'update jarvis.state set owner_chat_id = owner_chat_id + 1',  -- second pairing: refused by the trigger
    'delete from jarvis.state',
    'insert into jarvis.state default values',
    'select 1 from jarvis.audit',
    'update jarvis.audit set event = ''x''',
    'delete from jarvis.audit',
    'select jarvis.require_assistant()'] loop
    checks := checks + 1;
    begin
      execute q;
      problems := problems || ('jarvis_cloud ALLOWED on its own tables: ' || q);
    exception
      when insufficient_privilege then null;
      when others then problems := problems || format('jarvis_cloud %s (not a permission error): %s', sqlstate, q);
    end;
  end loop;
  checks := checks + 1;
  begin
    insert into jarvis.inbox (apr_id, decision) values ('APR-999999', 'reject');
    problems := problems || 'a second decision for the same approval was accepted'::text;
  exception when unique_violation then null;
  end;
  reset role;

  -- 4b. The JARVIS login claims (new -> taken, once) and finishes (once), then shuts down cleanly.
  perform set_config('request.jwt.claims', c_jarvis, true);
  set local role authenticated;
  select jsonb_agg(to_jsonb(d)) into v_claim from public.jarvis_claim_decisions() d;
  checks := checks + 1;
  if not coalesce(v_claim @> '[{"apr_id": "APR-999999", "decision": "approve"}]', false) then
    problems := problems || format('claim did not return the decision: %s', v_claim);
  end if;
  select count(*) into n from public.jarvis_claim_decisions() d where d.apr_id = 'APR-999999';
  checks := checks + 1;
  if n <> 0 then problems := problems || 'a decision was claimed twice'::text; end if;
  perform public.jarvis_finish_decision((select (e->>'id')::bigint from jsonb_array_elements(v_claim) e where e->>'apr_id' = 'APR-999999'), true, 'done in test');
  checks := checks + 1;
  begin
    perform public.jarvis_finish_decision((select (e->>'id')::bigint from jsonb_array_elements(v_claim) e where e->>'apr_id' = 'APR-999999'), true, 'again');
    problems := problems || 'a decision was finished twice'::text;
  exception when no_data_found then null;
  end;
  perform public.jarvis_shutdown_clean();
  reset role;
  checks := checks + 1;
  if (select not clean_shutdown or running_task is not null from jarvis.state)
     or (select status <> 'done' or not ok from jarvis.inbox where apr_id = 'APR-999999') then
    problems := problems || 'heartbeat / shutdown / finish did not record'::text;
  end if;

  -- 7. Stale-books flags: CFO view = bot's v_status = a recount from the tables.
  set local role jarvis_cloud;
  select jsonb_build_object('newest_entry_on', v.newest_entry_on, 'newest_sale_on', v.newest_sale_on,
                            'sales_stale', v.sales_stale, 'books_stale', v.books_stale) into actual from jarvis.v_status v;
  reset role;
  expected := (select jsonb_build_object('newest_entry_on', x.e, 'newest_sale_on', x.s,
                 'sales_stale', coalesce(x.today - x.s > 5, true), 'books_stale', coalesce(x.today - x.e > 3, true))
                 from (select (now() at time zone 'Asia/Karachi')::date today,
                              (select max(occurred_on) from app.events) e, (select max(occurred_on) from app.sales) s) x);
  checks := checks + 1;
  if fresh is distinct from expected or actual is distinct from expected then
    problems := problems || format('freshness differs: recount %s, CFO view %s, v_status %s', expected, fresh, actual);
  end if;

  -- 5. Rao's login and anon may not call the six RPCs.
  perform set_config('request.jwt.claims', c_rao, true);
  set local role authenticated;
  foreach q in array c_six loop
    checks := checks + 1;
    begin
      execute q;
      problems := problems || ('Rao login ALLOWED: ' || q);
    exception
      when insufficient_privilege then null;
      when others then problems := problems || format('Rao login %s (not a permission error): %s', sqlstate, q);
    end;
  end loop;
  reset role;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  foreach q in array c_six loop
    checks := checks + 1;
    begin
      execute q;
      problems := problems || ('anon ALLOWED: ' || q);
    exception
      when insufficient_privilege then null;
      when others then problems := problems || format('anon %s (not a permission error): %s', sqlstate, q);
    end;
  end loop;
  reset role;

  if cardinality(problems) = 0 then
    raise exception 'JARVIS TEST PASS: % checks (% app/public statements refused to jarvis_cloud). Freshness: %. Figures: %',
      checks, cardinality(qs), expected, figures;
  end if;
  raise exception 'JARVIS TEST FAIL: % problem(s) in % checks: %', cardinality(problems), checks, to_jsonb(problems);
end $test$;
