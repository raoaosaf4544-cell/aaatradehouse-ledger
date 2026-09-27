-- Task 4: two accounts were both named "Customer Advances". 2200 is the one every function and the
-- app use; 2050 has no entries and is referenced nowhere. Rename 2050 only (no balances moved, not deleted).
update app.accounts set name = 'Customer Advances (unused)' where code = '2050';
