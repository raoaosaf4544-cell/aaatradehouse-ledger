import React from 'react'
import { paisaToPkr, gramsToKg } from '../lib/types'
import { InvariantError } from '../lib/engine'

export function Money({ paisa, className = '' }: { paisa: number; className?: string }) {
  const negative = paisa < 0
  return (
    <span className={`font-mono tabular-nums ${negative ? 'text-rose-600' : ''} ${className}`}>
      {negative ? '−' : ''}PKR {paisaToPkr(Math.abs(paisa))}
    </span>
  )
}

export function Kg({ grams, className = '' }: { grams: number; className?: string }) {
  return <span className={`font-mono tabular-nums ${className}`}>{gramsToKg(grams)} kg</span>
}

export function Card({
  children,
  className = '',
}: {
  children: React.ReactNode
  className?: string
}) {
  return (
    <div className={`bg-white rounded-xl border border-slate-200 shadow-sm p-5 ${className}`}>
      {children}
    </div>
  )
}

export function StatCard({
  label,
  sub,
  children,
  tone = 'slate',
}: {
  label: string
  sub?: string
  children: React.ReactNode
  tone?: 'slate' | 'emerald' | 'amber' | 'rose' | 'blue'
}) {
  const tones: Record<string, string> = {
    slate: 'text-slate-900',
    emerald: 'text-emerald-700',
    amber: 'text-amber-700',
    rose: 'text-rose-700',
    blue: 'text-blue-700',
  }
  return (
    <Card>
      <div className="text-xs uppercase tracking-wide text-slate-500 font-semibold">{label}</div>
      <div className={`mt-2 text-2xl font-bold ${tones[tone]}`}>{children}</div>
      {sub && <div className="mt-1 text-xs text-slate-500">{sub}</div>}
    </Card>
  )
}

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500 mb-3">
      {children}
    </h2>
  )
}

export function ErrorBanner({ error, onDismiss }: { error: unknown; onDismiss?: () => void }) {
  const message =
    error instanceof InvariantError
      ? error.message
      : error instanceof Error
        ? error.message
        : String(error)
  return (
    <div className="mb-4 flex items-start gap-3 rounded-xl border border-rose-200 bg-rose-50 p-4">
      <div className="mt-0.5 h-2 w-2 shrink-0 rounded-full bg-rose-500" />
      <div className="min-w-0 flex-1">
        <div className="text-sm font-semibold text-rose-800">
          {error instanceof InvariantError ? 'Blocked by data-integrity rule' : 'Something went wrong'}
        </div>
        <div className="mt-1 break-words text-sm text-rose-700">{message}</div>
      </div>
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="shrink-0 rounded-lg border border-rose-200 px-2 py-1 text-xs font-medium text-rose-700 hover:bg-rose-100"
        >
          Dismiss
        </button>
      )}
    </div>
  )
}

export function Spinner({ label = 'Loading from database…' }: { label?: string }) {
  return (
    <div className="flex items-center gap-3 text-slate-500">
      <span className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-slate-600" />
      <span className="text-sm">{label}</span>
    </div>
  )
}

export function EmptyState({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-500">
      {children}
    </div>
  )
}
