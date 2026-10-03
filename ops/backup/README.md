# AAA ledger — nightly backups

Every night at **02:00 Pakistan time** a GitHub Action copies the whole ledger database, checks the copy by restoring
it into a throw-away database, and keeps it here, encrypted:

```
backups/2026/10/aaa-ledger-2026-10-04.dump.gpg         ← the backup (encrypted)
backups/2026/10/aaa-ledger-2026-10-04.dump.gpg.sha256  ← its checksum
```

What the nightly check proves before a file is kept:

- the copy restores cleanly (tables, views, functions, grants, row-security rules);
- **every table has the same number of rows** as the live books;
- **every account balance** and the books fingerprint are identical;
- debits equal credits;
- it is not empty or short (at least 20 tables and 200 entries);
- the encrypted file decrypts back to exactly the same copy.

If any check fails, nothing is kept, the run turns red and GitHub emails the owner. **A red run means: tell Claude/Rao
the same day.** A missed night is not a disaster (the older files are still here), but it must not be ignored.

What is **not** in the backup: the two login accounts (Supabase Auth). After an emergency restore they are created
again (step 6 below). Everything in the books is in the backup.

---

## The passphrase — read this first

The files are encrypted. Without the passphrase **nobody can open them, not even GitHub or Supabase**.

- The passphrase is saved in GitHub as the secret `BACKUP_PASSPHRASE`. GitHub never shows a secret again, so that copy
  can only be *used* by the nightly job, never read.
- **The owner must keep it in their password manager**, as an entry named exactly:
  **`AAA ledger — BACKUP PASSPHRASE (opens the nightly backups)`**
  Put the passphrase in the password field and this note in the notes field:
  `GitHub repo raoaosaf4544-cell/aaatradehouse-backups — read README.md "Emergency restore".`
- Keep a second copy somewhere that is not the same phone or laptop (for example printed and kept with the shop's
  papers, or with Rao's father).
- If the passphrase is ever changed in GitHub, update the password manager the same day. Old files still need the
  **old** passphrase — keep it in the same entry under "previous passphrase (files before <date>)".

The database password for the backup login (`backup_reader`) is a separate entry:
**`AAA ledger — backup_reader database password`**. It is only needed to make new backups, not to restore.

---

## Emergency restore, step by step

Use this if the Supabase project is lost, damaged or wrongly changed. It takes about 30–60 minutes. Nothing here
touches the old project; you build a fresh one and switch the app to it.

### 1. Get the newest backup file
1. Open https://github.com/raoaosaf4544-cell/aaatradehouse-backups (signed in as the owner).
2. Open `backups/` → the newest year → newest month → the newest `aaa-ledger-YYYY-MM-DD.dump.gpg`.
3. Click **Download raw file**. Also download the matching `.sha256` file.

### 2. Get the tools (one time)
Easiest, nothing to install: on the repo page click **Code → Codespaces → Create codespace on main**. A Linux terminal
opens in the browser. In it run:
```bash
sudo apt-get update && sudo apt-get install -y gnupg postgresql-client
```
(Upload the downloaded file into the codespace by dragging it into the file list, or use the copy already in the repo:
it is in the `backups/` folder of the codespace.)

On a Windows PC instead: install **Gpg4win** (https://gpg4win.org) and **PostgreSQL 17** (https://www.postgresql.org/download/windows/ —
the "Command Line Tools" are enough).

### 3. Check and decrypt the file
```bash
cd backups/YYYY/MM                       # the folder of the file
sha256sum -c aaa-ledger-YYYY-MM-DD.dump.gpg.sha256      # must say: OK
gpg --decrypt aaa-ledger-YYYY-MM-DD.dump.gpg > ledger.dump
```
gpg asks for the passphrase: copy it from the password manager entry **AAA ledger — BACKUP PASSPHRASE**.
`ledger.dump` is the readable copy. **Do not commit or share `ledger.dump`** — it is the books in clear.

### 4. Make a fresh Supabase project
1. https://supabase.com/dashboard → **New project** (free plan is fine). Choose a strong database password and save it
   in the password manager as `AAA ledger — NEW project database password`.
2. When it is ready: **Connect** (top of the project page) → **Session pooler** → press the **copy** button next to the
   connection string (copy the whole string exactly as Supabase shows it; do not use any example from this page). Replace
   `[YOUR-PASSWORD]` with the password from step 1.

### 5. Restore into it
In the terminal (put the connection string in quotes):
```bash
export NEW_DB='PASTE-THE-WHOLE-SESSION-POOLER-STRING-HERE'   # copied from Supabase, never typed by hand
psql "$NEW_DB" -c "create role jarvis_cloud nologin; grant jarvis_cloud to postgres; create role backup_reader login bypassrls; grant pg_read_all_data to backup_reader;"
pg_restore --no-owner -d "$NEW_DB" ledger.dump
```
A few lines saying a schema "already exists" (for `public`) are harmless. Then check the books are complete:
```bash
psql "$NEW_DB" -c "select count(*) as entries from app.events"
psql "$NEW_DB" -c "select sum(debit_paisa) = sum(credit_paisa) as balanced from app.ledger_entries"
```
`entries` must be the number of entries you expect; `balanced` must be `t`.

### 6. Bring back the two logins
1. New project → **Authentication → Users → Add user** → create the shop login (same e-mail as before) with a new
   password; do the same for the JARVIS login if it is used.
2. Copy each new user's **UID**, then in **SQL Editor** run (one line per login, with its e-mail and new UID):
   ```sql
   update app.users set auth_user_id = 'NEW-UID-HERE' where id = '11111111-1111-1111-1111-111111111111';  -- shop login
   ```
   (The JARVIS row is the app.users row whose role is `assistant`.)

### 7. Point the app at the new project
1. New project → **Project Settings → API**: copy the **Project URL** and the **anon / publishable key**.
2. Vercel → project **aaatradehouse-ledger** → **Settings → Environment Variables**: replace `VITE_SUPABASE_URL` and
   `VITE_SUPABASE_ANON_KEY` with the new values → **Deployments → Redeploy** the latest.
3. Open the app, sign in, and check the Dashboard figures (cash, stock, debtors) against the last known figures.
4. In the backup repo, update the secret `SUPABASE_BACKUP_DB_URL` to the new project (with the `backup_reader` login
   and a new password — see "One-time setup") so the nightly backups continue.

---

## One-time setup (already done once; repeat only for a new project)

1. Supabase → **SQL Editor** → run (with a long random password from the password manager; letters and digits only):
   `alter role backup_reader with password 'PASTE-HERE';`
2. Supabase → **Connect → Session pooler** → press the **copy** button (the real address is only shown there; never type
   or copy an address from this README), then change the user part `postgres.<project-ref>` to
   `backup_reader.<project-ref>` and put the backup_reader password in place of `[YOUR-PASSWORD]`.
3. This repo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `SUPABASE_BACKUP_DB_URL` = the string from step 2
   - `BACKUP_PASSPHRASE` = a long passphrase from the password manager (entry **AAA ledger — BACKUP PASSPHRASE**)
4. **Actions → Nightly backup → Run workflow** once, and check it turns green.

## Practice
Once every three months, open the newest file with steps 1–3 (decrypt only). If that works, the passphrase is right
and the backups can be opened.
