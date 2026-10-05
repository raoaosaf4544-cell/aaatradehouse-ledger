-- Crush cost, Rao's rule (owner-approved 5 Oct 2026):
--   crushed salt cost per kg = (rock cost used + crushing cost) / GOOD kg out.
-- Normal crush loss (dust / wastage) is absorbed into the good salt's cost; it is no longer charged to 5250.
-- Fine and Daana from one run share the cost by weight, so both get the same Rs/kg (the last output takes the
-- rounding paisa, as before).
-- How: in app.crush_run_values the wastage share is now 0. Everything else follows from that unchanged:
--   * the cost pool (rock value + crushing cost) goes entirely to the outputs; no 5250 line;
--   * record_process_run_impl books the rock "out" movement at its full value and the wastage movement (kg kept
--     for reports) at 0 value; the rock batch still goes down by the full kg used;
--   * the guards stay: output + wastage must equal rock used, outputs > 0, rock kg <= what the batch holds.
-- There are no crush runs in the books (checked 5 Oct), so nothing old needs re-costing.

do $m$
declare
  v_def text := pg_get_functiondef('app.crush_run_values(text,bigint,jsonb,bigint,bigint,boolean)'::regprocedure);
  v_old constant text := '  v_wast  := round(v_pool::numeric * p_wastage_grams / p_input_qty_grams);';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'crush loss absorbed: wastage-share line not found in app.crush_run_values - function changed, migration stopped';
  end if;
  execute replace(v_def, v_old, '  v_wast  := 0; -- normal crush loss is absorbed into the good output (Rao, 5 Oct 2026)');
end $m$;
