-- Ledger fix C (owner decision): only three products are offered. Display names change, codes stay (history intact).
--   SALT_ROCK        -> Rock Salt (whole / dalay)   (crush input)
--   SALT_BULK        -> Fine Powder Salt            (all of BATCH-075 is fine powder)
--   SALT_ROCK_COARSE -> Coarse Salt (daana)
-- Every other product is hidden (is_active = false). The guard refuses if any of them holds stock, a batch,
-- a movement or an undispatched sale line.

do $$
begin
  if exists (
    select 1 from app.products p
     where p.code not in ('SALT_ROCK', 'SALT_BULK', 'SALT_ROCK_COARSE')
       and (exists (select 1 from app.batches b where b.product_id = p.id)
            or exists (select 1 from app.movements m where m.product_id = p.id)
            or exists (select 1 from app.sale_lines sl where sl.product_id = p.id and sl.dispatched_grams < sl.qty_grams))) then
    raise exception 'A product to hide still has stock, batches or open sales - nothing changed';
  end if;
end $$;

update app.products set name = 'Rock Salt (whole / dalay)', is_active = true where code = 'SALT_ROCK';
update app.products set name = 'Fine Powder Salt', is_active = true where code = 'SALT_BULK';
update app.products set name = 'Coarse Salt (daana)', is_active = true where code = 'SALT_ROCK_COARSE';
update app.products set is_active = false where code not in ('SALT_ROCK', 'SALT_BULK', 'SALT_ROCK_COARSE') and is_active;
