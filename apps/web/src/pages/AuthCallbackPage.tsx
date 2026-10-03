import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { takeReturnTo } from '../lib/returnTo'
import { Button, ErrorState, Skeleton } from '../components/ui'

/** One in-flight exchange per code: the PKCE code is single-use and React StrictMode runs effects twice in development. */
const inflight = new Map<string, Promise<{ error: Error | null }>>()
export function exchangeOnce(code: string): Promise<{ error: Error | null }> {
  let p = inflight.get(code)
  if (!p) {
    p = supabase ? supabase.auth.exchangeCodeForSession(code).then(({ error }) => ({ error })) : Promise.resolve({ error: new Error('Supabase is not configured') })
    inflight.set(code, p)
  }
  return p
}

function readCallback(): { code: string | null; error: string | null } {
  const q = new URL(window.location.href).searchParams
  const providerError = q.get('error_description') ?? q.get('error')
  const code = q.get('code')
  if (providerError) return { code: null, error: providerError }
  if (!code) return { code: null, error: 'The sign-in response did not include an authorisation code. Please try signing in again.' }
  return { code, error: null }
}

export function AuthCallbackPage() {
  const navigate = useNavigate()
  const [{ code, error: initialError }] = useState(readCallback)
  const [exchangeError, setExchangeError] = useState<string | null>(null)
  const started = useRef(false)
  const error = initialError ?? exchangeError

  useEffect(() => {
    if (!code || started.current) return
    started.current = true
    void exchangeOnce(code).then(({ error: e }) => {
      if (e) { setExchangeError(e.message); return }
      navigate(takeReturnTo(), { replace: true })   // clears ?code from the URL; AuthProvider then loads my_access()
    })
  }, [code, navigate])

  if (error) {
    return (
      <div className="grid h-full place-items-center p-4">
        <div className="w-full max-w-md space-y-3">
          <ErrorState title="Sign-in could not be completed" message={error} />
          <Link to="/login"><Button variant="secondary">Back to sign in</Button></Link>
        </div>
      </div>
    )
  }
  return <div className="grid h-full place-items-center p-4"><div className="w-48"><p className="mb-2 text-sm text-muted">Signing you in…</p><Skeleton rows={2} /></div></div>
}
