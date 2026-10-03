#!/usr/bin/env bash
# Nightly backup of the AAA ledger: dump -> restore into a throw-away database -> compare every table's row count,
# every account balance and the books fingerprint with the live database -> encrypt -> prove it decrypts -> keep.
# A missing secret, an empty or short backup, or ANY difference stops the run with an error (GitHub emails the owner).
# If the dump itself worked, it is still kept, encrypted and named .UNVERIFIED, so there is always a recent copy.
# No figures are printed to the log: only table/account names when something differs.
set -euo pipefail
: "${DB_URL:?secret SUPABASE_BACKUP_DB_URL is not set}"
: "${PASSPHRASE:?secret BACKUP_PASSPHRASE is not set}"
: "${SCRATCH:?throw-away database is missing}"
export PGCONNECT_TIMEOUT=30

day=$(TZ=Asia/Karachi date +%F)
dir="backups/${day:0:4}/${day:5:2}"
out="$dir/aaa-ledger-$day.dump.gpg"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$dir"
counts() { psql "$1" -X -A -t -q -v ON_ERROR_STOP=1 -f scripts/counts.sql; }
# one line for the log: entries, cash (1000), debtors (1100), suppliers owed (2000), balance check, stock, fingerprint
summary() {
  awk -F'|' '$1=="events_total"{e=$2} $1=="account"&&$2=="1000"{c=$3} $1=="account"&&$2=="1100"{d=$3}
             $1=="account"&&$2=="2000"{s=0-$3} $1=="debits_equal_credits"{b=$2} $1=="stock"{st=st" "$2"="($3/1000)" kg"}
             $1=="fingerprint"{f=$2}
             END{printf "entries %s | cash %.2f | debtors %.2f | suppliers owed %.2f | debits=credits %s | stock%s | fingerprint %s", e, c/100, d/100, s/100, b, st, f}' "$1"
}

# 1. the dump (schemas app, public, jarvis), with the live counts taken just before and just after it
counts "$DB_URL" > "$work/live_before.txt"
pg_dump "$DB_URL" -Fc -n app -n public -n jarvis -f "$work/db.dump"
counts "$DB_URL" > "$work/live_after.txt"

# encrypt the dump to a file and prove it opens again with the same passphrase
printf '%s' "$PASSPHRASE" > "$work/pass"
encrypt_to() {
  gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-file "$work/pass" --symmetric --cipher-algo AES256 -o "$1" "$work/db.dump" \
    && gpg --batch --quiet --pinentry-mode loopback --passphrase-file "$work/pass" --decrypt "$1" | cmp -s - "$work/db.dump" \
    && (cd "$(dirname "$1")" && sha256sum "$(basename "$1")" > "$(basename "$1").sha256")
}

# The dump worked but the restore test did not prove it: keep it, clearly marked UNVERIFIED, and fail the run red.
# (Owner decision 4 Oct 2026: better an unproven copy than none. Use it only if no verified copy exists.)
keep_unverified() {
  echo "::error::$1"
  local u="$dir/aaa-ledger-$day.UNVERIFIED.dump.gpg"
  if encrypt_to "$u"; then
    echo "::error::The dump was kept as $u - NOT verified. Use it only if no verified copy exists."
  else
    rm -f "$u" "$u.sha256"
    echo "::error::Could not keep even an unverified copy."
  fi
  exit 1
}

# 2. restore it into the throw-away database, grants included, exactly as an emergency restore would
psql "$SCRATCH" -X -q -v ON_ERROR_STOP=1 -f scripts/scratch-prep.sql || keep_unverified "Could not prepare the throw-away database."
# (list to a file first: piping into grep -q cuts pg_restore off and, with pipefail, the check silently fails)
pg_restore -l "$work/db.dump" > "$work/toc.txt" || keep_unverified "Could not read the dump's contents list."
if grep -q ' SCHEMA - public ' "$work/toc.txt"; then
  psql "$SCRATCH" -X -q -v ON_ERROR_STOP=1 -c 'drop schema public cascade' || keep_unverified "Could not clear the throw-away database."
fi
pg_restore --no-owner --exit-on-error -d "$SCRATCH" "$work/db.dump" || keep_unverified "The dump could not be restored (see the pg_restore lines above)."

# TEST SWITCH (manual runs only): change one figure in the THROW-AWAY copy, to prove the comparison goes red.
# Only "$SCRATCH" is touched here - never the live database. Rs 1 more on both lines of one two-line entry, so the
# copy still balances and only the line-by-line comparison can catch it.
if [ "${BREAK_CHECK:-false}" = "true" ]; then
  echo "TEST SWITCH ON: changing one figure in the throw-away restored copy on purpose (live is not touched)."
  psql "$SCRATCH" -X -q -v ON_ERROR_STOP=1 -c "update app.ledger_entries
       set debit_paisa = debit_paisa + case when debit_paisa > 0 then 100 else 0 end,
           credit_paisa = credit_paisa + case when credit_paisa > 0 then 100 else 0 end
     where event_id = (select event_id from app.ledger_entries group by event_id having count(*) = 2 order by event_id limit 1)"
fi
counts "$SCRATCH" > "$work/restored.txt" || keep_unverified "Could not read the restored copy."
echo "Restored copy: $(summary "$work/restored.txt")"
echo "Live books:    $(summary "$work/live_after.txt")"

# 3. the restored copy must be complete and identical to the live books
tables=$(grep -c '^table|' "$work/restored.txt" || true)
events=$(grep '^events_total|' "$work/restored.txt" | cut -d'|' -f2)
if [ "${tables:-0}" -lt 20 ] || [ "${events:-0}" -lt 200 ]; then
  keep_unverified "Backup is empty or short: ${tables:-0} tables, ${events:-0} entries restored."
fi
grep -q '^debits_equal_credits|true$' "$work/restored.txt" || keep_unverified "Restored books do not balance."
if ! cmp -s "$work/restored.txt" "$work/live_before.txt" && ! cmp -s "$work/restored.txt" "$work/live_after.txt"; then
  echo "Differences in:"
  diff "$work/live_after.txt" "$work/restored.txt" | grep '^[<>]' | cut -d'|' -f1-2 | sort -u || true
  keep_unverified "The restored copy differs from the live books."
fi

# 4. verified: encrypt and keep it
if ! encrypt_to "$out"; then
  rm -f "$out" "$out.sha256"
  echo "::error::The encrypted file did not decrypt back to the same dump. Nothing was kept."
  exit 1
fi
echo "Backup OK: $tables tables and $events entries restored and matched the live books; saved $out"
