import { useState } from 'react'
import { useAuth } from '../app/AuthProvider'
import { appEnv } from '../lib/supabase'
import { buildReport } from '../lib/diagnostics'
import { Button } from './ui'

/** Support panel. Shows identifiers and states only — never tokens, keys or secrets. */
export function AccessDiagnostics() {
  const { session, accessResult, errorMessage } = useAuth()
  const [copied, setCopied] = useState(false)
  const report = buildReport({
    build: __APP_VERSION__, env: appEnv, origin: window.location.origin, supabaseUrl: import.meta.env.VITE_SUPABASE_URL as string | undefined,
    accessResult, accessError: errorMessage, user: session?.user ?? null, accessToken: session?.access_token,
  })
  const text = JSON.stringify(report, null, 2)
  return (
    <details className="mt-4 rounded border border-line bg-canvas p-3 text-xs">
      <summary className="cursor-pointer font-medium text-ink">Diagnostics (safe to share — contains no tokens)</summary>
      <pre className="mt-2 overflow-auto whitespace-pre-wrap break-all text-muted" data-testid="diag">{text}</pre>
      <Button variant="secondary" className="mt-2" onClick={() => { void navigator.clipboard?.writeText(text).then(() => setCopied(true)) }}>{copied ? 'Copied' : 'Copy'}</Button>
    </details>
  )
}
