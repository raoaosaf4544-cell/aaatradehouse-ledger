# AAA Trade House Ledger

Double-entry ledger for AAA General Trading (React + Vite, Supabase). See `docs/ARCHITECTURE.md`.

## Run locally

1. Copy `.env.example` to `.env` and fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
2. `bun install`
3. `bun run dev` — opens on http://127.0.0.1:3000, reachable from this computer only.

## Testing on your own phone (home only)

`bun run dev:phone` opens the dev app on your Wi-Fi (http://<this-computer's-IP>:3000).

**Warning:** this exposes the app to everyone on that Wi-Fi. Use it only on your home network, and stop it
(Ctrl+C) as soon as you finish testing. The family uses only the online (deployed) version, never this.
