-- Task 3c: rock salt (SALT_ROCK, BATCH-001) was bought into 1200 Inventory - Raw Salt, but the product was
-- set up as 'bulk_processed', so stock-outs, crush runs and sales would credit 1210 instead. Master data
-- only: no entries change. Nothing has ever been posted to 1210 from SALT_ROCK.
update app.products set form = 'raw' where code = 'SALT_ROCK' and form = 'bulk_processed';