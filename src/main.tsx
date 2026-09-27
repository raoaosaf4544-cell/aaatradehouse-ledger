import * as Sentry from '@sentry/react'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'

const dsn = import.meta.env.VITE_SENTRY_DSN

Sentry.init({
  dsn: dsn || undefined,
  release: import.meta.env.VITE_APP_VERSION,
  environment: import.meta.env.MODE,
  enabled: Boolean(dsn),
  // Financial data must never leave the machine in error payloads.
  beforeBreadcrumb(breadcrumb) {
    if (breadcrumb.category === 'console' || breadcrumb.category === 'fetch' || breadcrumb.category === 'xhr') {
      return null
    }
    return breadcrumb
  },
})

// Global error boundary: a crash must never take the ledger UI down silently.
Sentry.withErrorBoundary(App, {
  fallback: ({ resetError }) => (
    <div style={{ fontFamily: 'system-ui', padding: 40, maxWidth: 640, margin: '10vh auto' }}>
      <h1 style={{ fontSize: 22, fontWeight: 700 }}>Something went wrong on this screen</h1>
      <p style={{ color: '#333', fontSize: 16 }}>
        Your saved entries are safe on the server. Anything not saved yet may need typing again.
        Tap Try again.
      </p>
      {dsn ? (
        <p style={{ color: '#888', fontSize: 12 }}>
          This error was reported automatically (release {import.meta.env.VITE_APP_VERSION || 'dev'}).
        </p>
      ) : (
        <p style={{ color: '#888', fontSize: 12 }}>Error reporting is not configured (no Sentry DSN).</p>
      )}
      <button
        onClick={resetError}
        style={{ marginTop: 12, minHeight: 48, padding: '12px 20px', borderRadius: 10, border: '2px solid #94a3b8', fontSize: 16, fontWeight: 600, cursor: 'pointer' }}
      >
        Try again
      </button>
    </div>
  ),
  showDialog: false,
})

// Installed-app support: opens without signal. Production only, so development never serves stale files.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {
      // app still works online without it
    })
  })
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
