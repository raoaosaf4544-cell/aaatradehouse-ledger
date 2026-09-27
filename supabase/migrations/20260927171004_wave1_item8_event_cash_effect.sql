-- Wave 1 item 8: each entry's real cash effect (Dr - Cr on 1000 Cash on Hand), so the Cash Ledger shows money
-- in / money out by what actually happened to cash, not by the entry type. Column appended at the end
-- (existing columns unchanged); grants are kept by create or replace.
create or replace view app.v_events_with_party with (security_invoker = true) as
select e.id,
       e.event_ref,
       e.event_type,
       e.occurred_on,
       e.description,
       e.party_type,
       e.party_name,
       e.source,
       e.source_ref,
       e.created_at,
       u.name as created_by_name,
       (select coalesce(sum(le.debit_paisa), 0::numeric) from app.ledger_entries le where le.event_id = e.id) as total_paisa,
       (select coalesce(sum(le.debit_paisa - le.credit_paisa), 0::numeric)
          from app.ledger_entries le join app.accounts a on a.id = le.account_id and a.code = '1000'
         where le.event_id = e.id) as cash_net_paisa
from app.events e
left join app.users u on u.id = e.created_by;

create or replace view public.v_events_with_party with (security_invoker = true) as
select id, event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref,
       created_at, created_by_name, total_paisa, cash_net_paisa
from app.v_events_with_party;
