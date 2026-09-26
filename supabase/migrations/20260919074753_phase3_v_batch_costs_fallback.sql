-- v_batch_costs: fall back to the opening movement value when landed components
-- were not split at purchase (e.g. BATCH-001 Excel import, or single-total purchases)
create or replace view app.v_batch_costs as
select b.id as batch_id, b.batch_code, p.code as product_code, p.name as product_name,
       l.code as location_code, l.name as location_name, b.status, b.opened_on, b.closed_on,
       coalesce(sum(case when c.component = 'purchase' then c.amount_paisa end), 0) as purchase_paisa,
       coalesce(sum(case when c.component = 'freight_inbound' then c.amount_paisa end), 0) as freight_inbound_paisa,
       coalesce(sum(case when c.component = 'loading' then c.amount_paisa end), 0) as loading_paisa,
       coalesce(sum(case when c.component = 'other' then c.amount_paisa end), 0) as other_paisa,
       case when coalesce(sum(c.amount_paisa), 0) > 0 then coalesce(sum(c.amount_paisa), 0)
            else coalesce(mv.opening_value, 0) end as landed_cost_paisa,
       mv.opening_grams as acquired_grams,
       case when mv.opening_grams > 0 then
         round((case when coalesce(sum(c.amount_paisa), 0) > 0 then coalesce(sum(c.amount_paisa), 0)
                     else coalesce(mv.opening_value, 0) end)::numeric / (mv.opening_grams / 1000.0))
       else 0 end as initial_cost_ppk
from app.batches b
join app.products p on p.id = b.product_id
join app.locations l on l.id = b.location_id
left join app.batch_cost_components c on c.batch_id = b.id
left join (select batch_id, sum(qty_grams) as opening_grams, sum(value_paisa) as opening_value
           from app.movements where direction = 'in' group by batch_id) mv on mv.batch_id = b.id
group by b.id, p.code, p.name, l.code, l.name, mv.opening_grams, mv.opening_value;