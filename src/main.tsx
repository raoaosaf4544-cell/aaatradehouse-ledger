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
  fallback: ({ error, resetError }) => (
    <div style={{ fontFamily: 'system-ui', padding: 40, maxWidth: 640, margin: '10vh auto' }}>
      <h1 style={{ fontSize: 20, fontWeight: 700 }}>Something went wrong</h1>
      <p style={{ color: '#555', fontSize: 14 }}>
        The ledger hit an unexpected error. Your data is safe on the server — nothing you entered
        has been lost.
      </p>
      {dsn ? (
        <p style={{ color: '#888', fontSize: 12 }}>
          This error was reported automatically (release {import.meta.env.VITE_APP_VERSION || 'dev'}).
        </p>
      ) : (
        <p style={{ color: '#888', fontSize: 12 }}>Error reporting is not configured (no Sentry DSN).</p>
      )}
      <pre style={{ background: '#f4f4f5', padding: 12, borderRadius: 8, fontSize: 12, overflow: 'auto' }}>
        {String(error)}
      </pre>
      <button
        onClick={resetError}
        style={{ marginTop: 12, padding: '8px 16px', borderRadius: 8, border: '1px solid #ccc', cursor: 'pointer' }}
      >
        Try again
      </button>
    </div>
  ),
  showDialog: false,
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
