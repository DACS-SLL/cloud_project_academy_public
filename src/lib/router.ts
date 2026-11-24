import { useEffect, useState } from 'react'

// Enrutador por hash (#/ruta): no requiere reglas de reescritura en Cloudflare Pages.

function read(): string {
  const raw = window.location.hash.replace(/^#/, '')
  const path = raw.split('?')[0] || '/'
  return path.startsWith('/') ? path : `/${path}`
}

export function readQuery(): URLSearchParams {
  const raw = window.location.hash.replace(/^#/, '')
  const i = raw.indexOf('?')
  return new URLSearchParams(i >= 0 ? raw.slice(i + 1) : '')
}

export function usePath(): string {
  const [path, setPath] = useState(read)
  useEffect(() => {
    const onChange = () => setPath(read())
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])
  return path
}

export function navigate(path: string): void {
  window.location.hash = path
}

/** Coincide `/alumnos/:id` con `/alumnos/123` y devuelve los parámetros. */
export function matchRoute(pattern: string, path: string): Record<string, string> | null {
  const a = pattern.split('/').filter(Boolean)
  const b = path.split('/').filter(Boolean)
  if (a.length !== b.length) return null
  const params: Record<string, string> = {}
  for (let i = 0; i < a.length; i++) {
    if (a[i].startsWith(':')) params[a[i].slice(1)] = decodeURIComponent(b[i])
    else if (a[i] !== b[i]) return null
  }
  return params
}
