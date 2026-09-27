import { useState } from 'react'
import { FileSpreadsheet } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { Field, inputCls } from './ui'

/** Email + password sign-in. No sign-up: accounts are created by the owner in Supabase. */
export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    setBusy(false)
    if (!error) return
    if (error.message === 'Invalid login credentials') setError('Wrong email or password.')
    else if (!navigator.onLine || /fetch|network/i.test(error.message)) setError('No signal — signing in needs signal.')
    else setError('Could not sign in. Check signal and try again.')
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
      <form onSubmit={submit} className="w-full max-w-sm space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-slate-900 text-white">
            <FileSpreadsheet className="h-5 w-5" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-slate-800">AAA Trade House</h1>
            <p className="text-sm text-slate-500">Sign in to the ledger</p>
          </div>
        </div>
        <Field label="Email">
          <input
            type="email"
            autoComplete="username"
            inputMode="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="Password">
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={inputCls}
          />
        </Field>
        {error && <p className="rounded-xl bg-red-50 p-3 text-base font-medium text-red-700">{error}</p>}
        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-xl bg-slate-900 py-3.5 text-lg font-semibold text-white disabled:opacity-60"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  )
}
