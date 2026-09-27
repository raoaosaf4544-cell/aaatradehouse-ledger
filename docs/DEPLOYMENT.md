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

## 2. Vercel (hosting) — LIVE since 2026-09-27

- **URL:** https://aaatradehouse-ledger.vercel.app (default Vercel address; no custom domain, no DNS).
- **Project:** `aaatradehouse-ledger` in team `raoaosaf4544-cell`, linked to GitHub
  `raoaosaf4544-cell/aaatradehouse-ledger`; every push to `main` redeploys production.
  Separate from the website project `aaatradehouse.com`, which is not touched.
- **Build** (`vercel.json`): `bun install --frozen-lockfile`, `bun run build`, output `dist`,
  SPA rewrite so refreshing any page works.
- **Environment variables** (Production + Preview): only `VITE_SUPABASE_URL` and
  `VITE_SUPABASE_ANON_KEY` (the `sb_publishable_…` key), plus `VITE_SENTRY_DSN` (public DSN).
  Never a service-role key, database password or Sentry auth token.
- **Supabase Auth → URL Configuration:** Site URL = the live URL; Redirect URLs =
  `https://aaatradehouse-ledger.vercel.app/**` and `http://127.0.0.1:3000/**`. Sign-ups OFF.
- **Sign-out** clears this device only (`scope: 'local'`): the owner and his father share one login.

## 3. Sentry (error tracking) — LIVE since 2026-09-27

- Project `aaatradehouse-ledger` (platform React) in org `aaatradehouse`, team `aaatradehouse`
  (separate from the org's `python` project).
- Its **public** DSN is set in Vercel as `VITE_SENTRY_DSN` (Production + Preview). A DSN only lets
  the app *send* error reports; no Sentry auth token is in the app or in Vercel.
- Local development has no DSN (`.env`), so nothing is reported from the laptop.

Privacy rules already coded in `src/main.tsx`:
- console/fetch/XHR breadcrumbs are dropped (no financial data in breadcrumbs),
- the error boundary never displays amounts or raw error text,
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
