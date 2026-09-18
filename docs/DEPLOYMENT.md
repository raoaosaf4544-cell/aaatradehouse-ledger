# Deployment & Operations Runbook

**Stack:** React 18 + Vite (Vercel) · Supabase Postgres 17 · Sentry error tracking

## 1. Database (Supabase) — DONE

Project `lceijfagzgmroxridgua` is live and loaded. Everything in
`supabase/migrations/` has been executed and verified:

| Object | Status |
|---|---|
| `app` schema (events, ledger_entries, movements, review_queue, ref tables) | ✅ live |
| Chart of accounts (34 accounts) | ✅ seeded |
| Invariant triggers (balanced events, cash ≥ 0, stock ≥ 0) | ✅ proven via negative tests |
| `app.post_event` / `public.post_event` (only write path) | ✅ proven via HTTP tests |
| Excel import (100 cash rows → 101 events, 20 review items, BATCH-001) | ✅ verified |
| RLS (anon read-only; writes only through guarded RPCs) | ✅ enabled |

**Baseline verified to the paisa:** Cash **PKR 77,044.00** · Dr = Cr · Inventory
15,210 kg = **PKR 114,270.00** · 20 UNCLEAR lines in the review queue, nothing
auto-classified.

Re-running the migrations is safe (idempotent), but the import script
(`scripts/gen_phase1_import.py`) will fail loudly if the data no longer matches
the Excel — that is by design.

## 2. Vercel (hosting) — one-time manual setup

The Freebuff toolchain has no Vercel connector, so this step is yours
(~3 minutes):

1. Push/sync the repo (already on GitHub:
   `raoaosaf4544-cell/aaatradehouse-ledger`).
2. Go to **vercel.com → Add New → Project** and import
   `aaatradehouse-ledger`.
3. Vercel auto-detects **Vite**. Leave build settings as-is
   (`bun install` / `vite build`, output `dist`). `vercel.json` is included
   for the SPA rewrite.
4. Add **Environment Variables** (Production + Preview):
   - `VITE_SUPABASE_URL` = `https://lceijfagzgmroxridgua.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = the publishable key (find it in Supabase →
     Settings → API; it is the `sb_publishable_…` key or the legacy `anon` JWT —
     both are safe for browsers and already gated by RLS)
   - `VITE_APP_VERSION` = e.g. `phase1`
   - `VITE_SENTRY_DSN` = (optional, see below)
5. Deploy. Every future `git push` to `main` redeploys automatically.

> These keys are publishable by design: they can only read what RLS allows
> (read-only) and write only through the invariant-guarded RPCs.

## 3. Sentry (error tracking) — one-time manual step

The Sentry MCP connection is **read-only** (it can inspect orgs/issues but has
no project-creation tool), so create the project once in the dashboard:

1. **sentry.io → org `aaatradehouse` → Settings → Projects → Create Project**
   → Platform: **React**, name: `ledger-web`.
2. Copy the **DSN** (looks like `https://…@o….ingest.sentry.io/…`).
3. Add it to Vercel as `VITE_SENTRY_DSN` and redeploy.

Until a DSN is set, Sentry is initialized but **disabled** — the app runs fine
and the error boundary still shows a local crash screen.

Privacy rules already coded in `src/main.tsx`:
- console/fetch/XHR breadcrumbs are dropped (no financial data in breadcrumbs),
- the error boundary never displays amounts,
- only stack traces + release info leave the browser.

## 4. Verifying a deployment

After deploying, open the URL and check the Dashboard:

- Cash on Hand shows **PKR 77,044** with a green ✓ baseline note
- Inventory shows **PKR 114,270 / 15,210 kg** with ✓
- Recent events list is populated from the database
- Financials shows a balanced trial balance
- Review Queue lists 20 items

If any baseline check shows ✗ — stop and reconcile; do not enter new data.

## 5. Daily use

- **Cash Ledger** → Record money in / money out. The form shows the exact
  journal lines before you save; the DB rejects anything that would unbalance
  the books or overdraw cash.
- **Review Queue** → resolve an unclear line by writing a decision note
  (required — corrections are never silent).
- Everything else (balances, stock, trial balance) is derived automatically.
