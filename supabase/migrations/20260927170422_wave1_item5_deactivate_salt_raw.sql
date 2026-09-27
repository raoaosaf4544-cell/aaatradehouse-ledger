-- Wave 1 item 5: SALT_RAW "Raw Rock Salt (uncrushed)" was never used (no batches, movements or sale lines);
-- the real rock salt is SALT_ROCK. Switch it off so it no longer appears in any form. The row stays (history).
update app.products p set is_active = false
where p.code = 'SALT_RAW'
  and not exists (select 1 from app.batches b where b.product_id = p.id)
  and not exists (select 1 from app.movements m where m.product_id = p.id)
  and not exists (select 1 from app.sale_lines sl where sl.product_id = p.id);