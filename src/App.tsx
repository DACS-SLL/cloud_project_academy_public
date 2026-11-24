import { useState } from 'react'
import type { FormEvent, ReactNode } from 'react'
import { Card, Field, Loading, Notice } from './components/ui'
import { matchRoute, navigate, usePath } from './lib/router'
import { SessionProvider, useSession } from './lib/session'
import type { Role } from './lib/types'
import { SessionAttendance, SessionList } from './pages/Attendance'
import Cycles from './pages/Cycles'
import Dashboard from './pages/Dashboard'
import Finance from './pages/Finance'
import Groups from './pages/Groups'
import NewEnrollment from './pages/NewEnrollment'
import Cases from './pages/Cases'
import Exceptions from './pages/Exceptions'
import RegisterPayment from './pages/RegisterPayment'
import { StudentFile, StudentList } from './pages/Students'
import TeacherHome from './pages/TeacherHome'
import Transfers from './pages/Transfers'

interface RouteDef {
  path: string
  roles: Role[]
  nav?: string
  render: (p: Record<string, string>) => ReactNode
}

/**
 * Mapa de pantallas por rol (F00). La interfaz solo oculta lo que el rol no usa;
 * la autorización real la aplican las políticas RLS y las RPC en Supabase.
 * C02 y C04 se ofrecen solo a secretaría por decisión de diseño (el backend permite también a dirección).
 */
const ROUTES: RouteDef[] = [
  { path: '/tablero', roles: ['admin', 'cashier'], nav: 'Tablero', render: () => <Dashboard /> },
  { path: '/ciclos', roles: ['admin'], nav: 'Ciclos y reglas', render: () => <Cycles /> },
  { path: '/grupos', roles: ['admin'], nav: 'Grupos y cupos', render: () => <Groups /> },
  { path: '/matricula/nueva', roles: ['cashier'], nav: 'Nueva matrícula', render: () => <NewEnrollment /> },
  { path: '/alumnos', roles: ['admin', 'cashier'], nav: 'Alumnos', render: () => <StudentList /> },
  { path: '/alumnos/:id', roles: ['admin', 'cashier'], render: (p) => <StudentFile studentId={p.id} /> },
  { path: '/pagos/registrar', roles: ['cashier'], nav: 'Registrar pago', render: () => <RegisterPayment /> },
  { path: '/finanzas', roles: ['admin'], nav: 'Finanzas', render: () => <Finance /> },
  { path: '/excepciones', roles: ['admin'], nav: 'Excepciones', render: () => <Exceptions /> },
  { path: '/casos', roles: ['admin', 'cashier'], nav: 'Casos', render: () => <Cases /> },
  { path: '/traslados', roles: ['admin'], nav: 'Traslados', render: () => <Transfers /> },
  { path: '/mis-grupos', roles: ['teacher'], nav: 'Mis grupos', render: () => <TeacherHome /> },
  { path: '/asistencia', roles: ['teacher'], nav: 'Sesiones y asistencia', render: () => <SessionList /> },
  { path: '/asistencia/:id', roles: ['teacher'], render: (p) => <SessionAttendance sessionId={p.id} /> },
]

const HOME: Record<Role, string> = { admin: '/tablero', cashier: '/tablero', teacher: '/mis-grupos' }
const ROLE_LABEL: Record<Role, string> = { admin: 'Dirección', cashier: 'Secretaría', teacher: 'Docente' }

function Login() {
  const { signIn } = useSession()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    setBusy(true)
    setError('')
    const message = await signIn(email, password)
    if (message) setError(message)
    setBusy(false)
  }

  return (
    <main className="auth">
      <form className="card auth-card" onSubmit={submit} noValidate>
        <div className="brand-mark" aria-hidden="true">A</div>
        <h1>Iniciar sesión</h1>
        <Field label="Correo">
          <input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} />
        </Field>
        <Field label="Contraseña">
          <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </Field>
        {error && <Notice tone="error">{error}</Notice>}
        <button type="submit" className="btn btn-primary" disabled={busy || !email || !password}>
          {busy ? 'Entrando…' : 'Entrar'}
        </button>
        <p className="footnote">Datos de demostración. El acceso lo crea dirección; no hay registro público.</p>
      </form>
    </main>
  )
}

function Screen({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <main className="auth">
      <div className="card auth-card">
        <h1>{title}</h1>
        {children}
      </div>
    </main>
  )
}

function Shell() {
  const session = useSession()
  const path = usePath()

  if (session.status === 'unconfigured')
    return (
      <Screen title="Falta la configuración">
        <Notice tone="warn">
          Define VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY en .env.local. Usa solo la clave publicable; nunca una clave secreta.
        </Notice>
      </Screen>
    )
  if (session.status === 'loading') return <Screen title="Cargando"><Loading label="Cargando sesión…" /></Screen>
  if (session.status === 'signedOut') return <Login />
  if (session.status === 'error')
    return (
      <Screen title="No pudimos cargar tu acceso">
        <Notice tone="error">{session.errorMessage}</Notice>
        <div className="actions">
          <button type="button" className="btn btn-primary" onClick={session.reload}>Reintentar</button>
          <button type="button" className="btn btn-ghost" onClick={session.signOut}>Cerrar sesión</button>
        </div>
      </Screen>
    )
  if (session.status === 'noAccess' || !session.access)
    return (
      <Screen title="Sin acceso">
        <Notice tone="warn">Tu cuenta no pertenece a ninguna academia. Pide a dirección que te dé acceso.</Notice>
        <button type="button" className="btn btn-ghost" onClick={session.signOut}>Cerrar sesión</button>
      </Screen>
    )

  const { access } = session
  const role = access.role
  const mine = ROUTES.filter((r) => r.roles.includes(role))

  let content: ReactNode = null
  let known = false
  for (const r of ROUTES) {
    const params = matchRoute(r.path, path)
    if (!params) continue
    known = true
    content = r.roles.includes(role) ? r.render(params) : null
    break
  }
  if (path === '/' || path === '') {
    navigate(HOME[role])
    return null
  }

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">
          <div className="brand-mark small" aria-hidden="true">A</div>
          <div>
            <strong>{access.academy_name}</strong>
            <span className="muted"> · {ROLE_LABEL[role]}</span>
          </div>
        </div>
        <div className="topbar-right">
          <span className="muted">{session.email}</span>
          <button type="button" className="btn btn-ghost" onClick={session.signOut}>Cerrar sesión</button>
        </div>
      </header>
      <div className="layout">
        <nav className="sidenav" aria-label="Principal">
          {mine
            .filter((r) => r.nav)
            .map((r) => (
              <a
                key={r.path}
                href={`#${r.path}`}
                className={path === r.path || (r.path !== '/' && path.startsWith(`${r.path}/`)) ? 'is-active' : ''}
              >
                {r.nav}
              </a>
            ))}
        </nav>
        <main className="content">
          {content ??
            (known ? (
              // S01: sin permiso. No revela si el dato existe.
              <Card title="Sin permiso">
                <Notice tone="warn">Tu rol no tiene acceso a esta sección.</Notice>
                <button type="button" className="btn btn-primary" onClick={() => navigate(HOME[role])}>Ir al inicio</button>
              </Card>
            ) : (
              // S02: no encontrado.
              <Card title="No encontrado">
                <p>La página que buscas no existe.</p>
                <button type="button" className="btn btn-primary" onClick={() => navigate(HOME[role])}>Ir al inicio</button>
              </Card>
            ))}
          <p className="footnote">Datos de demostración.</p>
        </main>
      </div>
    </div>
  )
}

export default function App() {
  return (
    <SessionProvider>
      <Shell />
    </SessionProvider>
  )
}
