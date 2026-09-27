-- Task 3D: the old 9-argument record_purchase made the Salt Purchase form's call ambiguous
-- ("function public.record_purchase(...) is not unique"). The 11-argument guarded wrapper
-- (optional p_idempotency_key, p_cost_components) now receives that call.
drop function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid);
