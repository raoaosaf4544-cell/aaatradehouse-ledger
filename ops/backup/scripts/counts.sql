-- Row counts per table and the balances. The nightly test runs this on the live books (before and after the dump)
-- and on the restored copy; the restored output must be identical to one of them.
-- The jarvis tables change every minute, so they are backed up and restored but not compared.
-- collate "C" keeps the order the same on Supabase and on the throw-away database.
select format('table|%s.%s|%s', n.nspname, c.relname,
              (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname in ('app', 'public') and c.relkind = 'r'
 order by n.nspname collate "C", c.relname collate "C";
select 'events_total|' || count(*) from app.events;
select format('account|%s|%s', a.code, coalesce(sum(le.debit_paisa - le.credit_paisa), 0))
  from app.accounts a left join app.ledger_entries le on le.account_id = a.id
 group by a.code order by a.code collate "C";
select format('stock|%s|%s', b.batch_code,
              sum(case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end))
  from app.movements m join app.batches b on b.id = m.batch_id
 group by b.batch_code
having sum(case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end) <> 0
 order by b.batch_code collate "C";
select 'debits_equal_credits|' || (coalesce(sum(debit_paisa), 0) = coalesce(sum(credit_paisa), 0)) from app.ledger_entries;
select 'fingerprint|' || md5(
  coalesce((select string_agg(e.event_ref || ':' || le.entry_seq || ':' || a.code || ':' || le.debit_paisa || ':' || le.credit_paisa, ','
                              order by e.event_ref collate "C", le.entry_seq)
              from app.ledger_entries le join app.events e on e.id = le.event_id join app.accounts a on a.id = le.account_id), '')
  || coalesce((select string_agg(m.event_id || ':' || m.movement_seq || ':' || m.batch_id || ':' || m.direction || ':' || m.qty_grams || ':' || m.value_paisa, ','
                                 order by m.event_id, m.movement_seq)
                 from app.movements m), ''));
