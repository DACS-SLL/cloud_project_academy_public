import { useCallback, useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'

// ---------- Carga de datos con estados de pantalla (F00 §4) ----------

export interface AsyncState<T> {
  data: T | null
  error: AppError | null
  loading: boolean
  reload: () => void
}

export function useAsync<T>(fn: () => Promise<T>, deps: unknown[] = []): AsyncState<T> {
  const [state, setState] = useState<{ data: T | null; error: AppError | null; loading: boolean }>({
    data: null,
    error: null,
    loading: true,
  })
  const [tick, setTick] = useState(0)
  const fnRef = useRef(fn)
  fnRef.current = fn

  useEffect(() => {
    let alive = true
    setState((s) => ({ ...s, loading: true, error: null }))
    fnRef.current().then(
      (data) => alive && setState({ data, error: null, loading: false }),
      (e) => alive && setState({ data: null, error: asAppError(e), loading: false }),
    )
    return () => {
      alive = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick])

  const reload = useCallback(() => setTick((t) => t + 1), [])
  return { ...state, reload }
}

// ---------- Presentación ----------

export function Loading({ label = 'Cargando…' }: { label?: string }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <div className="skeleton" />
      <div className="skeleton short" />
      <div className="skeleton" />
      <span className="sr-only">{label}</span>
    </div>
  )
}

export function Notice({
  tone = 'info',
  title,
  children,
  action,
}: {
  tone?: 'info' | 'ok' | 'warn' | 'error'
  title?: string
  children?: ReactNode
  action?: ReactNode
}) {
  const icon = { info: 'ℹ', ok: '✓', warn: '⚠', error: '✕' }[tone]
  return (
    <div className={`notice notice-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>
      <span className="notice-icon" aria-hidden="true">
        {icon}
      </span>
      <div className="notice-body">
        {title && <strong>{title}</strong>}
        {children && <div>{children}</div>}
      </div>
      {action}
    </div>
  )
}

export function ErrorBanner({ error, onRetry }: { error: AppError; onRetry?: () => void }) {
  const lost = error.kind === 'uncertain'
  return (
    <Notice
      tone={lost ? 'warn' : 'error'}
      action={
        onRetry && (
          <button type="button" className="btn btn-ghost" onClick={onRetry}>
            Reintentar
          </button>
        )
      }
    >
      {lost ? 'No pudimos conectar con el servidor. Revisa tu conexión y reintenta.' : error.message}
    </Notice>
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>
}

export type Tone = 'neutral' | 'ok' | 'warn' | 'danger' | 'info'

export function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  const icon = { neutral: '○', ok: '✓', warn: '◐', danger: '!', info: '●' }[tone]
  return (
    <span className={`badge badge-${tone}`}>
      <span aria-hidden="true">{icon}</span> {children}
    </span>
  )
}

export function Field({
  label,
  error,
  hint,
  children,
}: {
  label: string
  error?: string
  hint?: string
  children: ReactNode
}) {
  return (
    <label className={`field ${error ? 'has-error' : ''}`}>
      <span className="field-label">{label}</span>
      {children}
      {hint && !error && <span className="field-hint">{hint}</span>}
      {error && (
        <span className="field-error" role="alert">
          {error}
        </span>
      )}
    </label>
  )
}

export function Page({
  title,
  subtitle,
  actions,
  children,
}: {
  title: string
  subtitle?: string
  actions?: ReactNode
  children: ReactNode
}) {
  return (
    <section className="page">
      <header className="page-head">
        <div>
          <h1>{title}</h1>
          {subtitle && <p className="subtitle">{subtitle}</p>}
        </div>
        {actions && <div className="page-actions">{actions}</div>}
      </header>
      {children}
    </section>
  )
}

export function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="card">
      {title && <h2>{title}</h2>}
      {children}
    </div>
  )
}

/** Barra de cupo: texto + barra, el estado no depende solo del color. */
export function SeatBar({ capacity, occupied, pending }: { capacity: number; occupied: number; pending?: number }) {
  const pct = capacity > 0 ? Math.min(100, Math.round((occupied / capacity) * 100)) : 0
  const available = capacity - occupied
  const tone: Tone = available <= 0 ? 'danger' : available <= 2 ? 'warn' : 'ok'
  const label = available <= 0 ? 'lleno' : available <= 2 ? `queda${available === 1 ? '' : 'n'} ${available}` : 'disponible'
  return (
    <div className="seatbar">
      <div className="seatbar-track" aria-hidden="true">
        <div className={`seatbar-fill seatbar-${tone}`} style={{ width: `${pct}%` }} />
      </div>
      <span>
        {occupied} / {capacity} ocupados · {label}
        {pending !== undefined && ` · ${pending} pendiente${pending === 1 ? '' : 's'} (no ocupan cupo)`}
      </span>
    </div>
  )
}
