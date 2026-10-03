-- Read-only login for the nightly backup (GitHub Action, pg_dump).
-- It reads every row of every table (pg_read_all_data + BYPASSRLS, so row-level security cannot hide rows from the
-- backup) and can write nothing and run no function. Created WITHOUT a password: the owner sets it in the Supabase
-- SQL editor (alter role backup_reader with password '...'), so it never passes through anyone else.
-- No ledger table or policy is changed.
create role backup_reader login bypassrls;
grant pg_read_all_data to backup_reader;
