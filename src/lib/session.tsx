import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { isSupabaseConfigured, supabase } from './supabase'
import { getAccess } from './api'
import { asAppError } from './errors'
import type { Access } from './types'

type Status = 'loading' | 'unconfigured' | 'signedOut' | 'noAccess' | 'error' | 'ready'

interface SessionValue {
  status: Status
  email: string
  access: Access | null
  /** Otras academias de la misma cuenta, si existen (la demo usa una por cuenta). */
  otherAccess: Access[]
  errorMessage: string
  signIn: (email: string, password: string) => Promise<string | null>
  signOut: () => Promise<void>
  reload: () => void
}

const Ctx = createContext<SessionValue | null>(null)

export function SessionProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<Status>(isSupabaseConfigured ? 'loading' : 'unconfigured')
  const [email, setEmail] = useState('')
  const [accessList, setAccessList] = useState<Access[]>([])
  const [errorMessage, setErrorMessage] = useState('')
  const [tick, setTick] = useState(0)

  useEffect(() => {
    if (!isSupabaseConfigured) return
    let alive = true

    async function load(userEmail: string | undefined) {
      if (!userEmail) {
        if (alive) {
          setAccessList([])
          setEmail('')
          setStatus('signedOut')
        }
        return
      }
      try {
        const list = await getAccess()
        if (!alive) return
        setEmail(userEmail)
        setAccessList(list)
        setStatus(list.length > 0 ? 'ready' : 'noAccess')
      } catch (e) {
        if (!alive) return
        setEmail(userEmail)
        setErrorMessage(asAppError(e).message)
        setStatus('error')
      }
    }

    supabase.auth.getSession().then(({ data }) => load(data.session?.user.email))
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      // Se difiere para no llamar a Supabase dentro del propio callback de Auth.
      setTimeout(() => load(session?.user.email), 0)
    })
    return () => {
      alive = false
      sub.subscription.unsubscribe()
    }
  }, [tick])

  const signIn = useCallback(async (mail: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email: mail.trim(), password })
    if (!error) return null
    if (/invalid login|invalid credentials/i.test(error.message)) return 'Correo o contraseña incorrectos.'
    if (/fetch|network|timeout|load failed/i.test(error.message))
      return 'No pudimos conectar. Revisa tu conexión y vuelve a intentar.'
    return 'No se pudo iniciar sesión. Vuelve a intentar.'
  }, [])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
  }, [])

  const reload = useCallback(() => setTick((t) => t + 1), [])

  const value = useMemo<SessionValue>(
    () => ({
      status,
      email,
      access: accessList[0] ?? null,
      otherAccess: accessList.slice(1),
      errorMessage,
      signIn,
      signOut,
      reload,
    }),
    [status, email, accessList, errorMessage, signIn, signOut, reload],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useSession(): SessionValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useSession fuera de SessionProvider')
  return v
}
