import { useRef, useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import {
  createClassSession,
  findSession,
  getSession,
  listAssignments,
  listAttendance,
  listGroups,
  listSessions,
  listStudentsMinimal,
  listSubjects,
  recordAttendance,
} from '../lib/api'
import { SHIFT_LABEL } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate } from '../lib/router'
import type { AttendanceResult, AttendanceStatus } from '../lib/types'

const STATUS_LABEL: Record<AttendanceStatus, string> = { present: 'Presente', absent: 'Ausente', late: 'Tardanza' }
const STATUS_TONE = { present: 'ok', absent: 'danger', late: 'warn' } as const

function formatDateTime(iso: string) {
  return new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(iso))
}

/** `datetime-local` no trae zona: se interpreta como hora de Lima (UTC-5, sin horario de verano). */
function limaToIso(value: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return null
  const d = new Date(`${value}:00-05:00`)
  return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

/** T02 — Sesiones del docente: crear una y abrir las anteriores. */
export function SessionList() {
  const data = useAsync(async () => {
    const [assignments, groups, subjects, sessions] = await Promise.all([
      listAssignments(),
      listGroups(),
      listSubjects(),
      listSessions(),
    ])
    return { assignments, groups, subjects, sessions }
  }, [])
  const [assignmentId, setAssignmentId] = useState('')
  const [startsAt, setStartsAt] = useState('')
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const d = data.data

  const assignment = d?.assignments.find((a) => a.id === assignmentId)
  const groupName = (id: string) => d?.groups.find((g) => g.id === id)?.name ?? '—'
  const subjectName = (id: string) => d?.subjects.find((s) => s.id === id)?.name ?? '—'

  async function create() {
    if (busy || !assignment) return
    const iso = limaToIso(startsAt)
    if (!iso) {
      setFailure({ kind: 'rejected', hint: 'INVALID_START_TIME', code: '', message: 'Indica fecha y hora de la sesión.' })
      return
    }
    setBusy(true)
    setFailure(null)
    setUncertain(false)
    try {
      const id = await createClassSession(assignment.group_id, assignment.subject_id, iso)
      navigate(`/asistencia/${id}`)
    } catch (e) {
      const err = asAppError(e)
      try {
        // Duplicada o sin respuesta: se busca la misma sesión antes de pedir otra.
        if (err.hint === 'SESSION_DUPLICATE' || err.kind === 'uncertain') {
          const found = await findSession(assignment.group_id, assignment.subject_id, iso)
          if (found) {
            navigate(`/asistencia/${found.id}`)
            return
          }
        }
      } catch {
        /* la lectura también falló: se muestra el error original */
      }
      if (err.kind === 'uncertain') setUncertain(true)
      else setFailure(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Page title="Sesiones y asistencia" subtitle="Crea la sesión de clase y pasa lista. Solo ves tus grupos y cursos asignados.">
      {data.loading && !d && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && d.assignments.length === 0 && <Empty>Dirección aún no te asignó un grupo y curso.</Empty>}
      {d && d.assignments.length > 0 && (
        <Card title="Nueva sesión">
          <div className="form-grid">
            <Field label="Grupo y curso">
              <select value={assignmentId} onChange={(e) => setAssignmentId(e.target.value)} disabled={busy}>
                <option value="">Elige</option>
                {d.assignments.map((a) => (
                  <option key={a.id} value={a.id}>
                    {groupName(a.group_id)} · {subjectName(a.subject_id)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Fecha y hora (hora de Lima)">
              <input type="datetime-local" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} disabled={busy} />
            </Field>
          </div>
          {failure && <ErrorBanner error={failure} />}
          {uncertain && (
            <Notice tone="warn" title="No podemos confirmar el resultado">
              Perdimos la conexión y no encontramos la sesión. Revisa la lista de abajo antes de crearla otra vez.
            </Notice>
          )}
          <div className="actions">
            <button type="button" className="btn btn-primary" onClick={create} disabled={busy || !assignmentId || !startsAt}>
              {busy ? 'Creando…' : 'Crear y pasar lista'}
            </button>
          </div>
        </Card>
      )}
      {d && (
        <Card title="Mis sesiones">
          {d.sessions.length === 0 ? (
            <Empty>Todavía no creaste sesiones.</Empty>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>Fecha</th><th>Grupo</th><th>Curso</th><th /></tr>
                </thead>
                <tbody>
                  {d.sessions.map((s) => (
                    <tr key={s.id}>
                      <td className="nowrap">{formatDateTime(s.starts_at)}</td>
                      <td>{groupName(s.group_id)}</td>
                      <td>{subjectName(s.subject_id)}</td>
                      <td className="right">
                        <button type="button" className="btn btn-ghost" onClick={() => navigate(`/asistencia/${s.id}`)}>Abrir</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </Page>
  )
}

/** T03/T04 — Pasar lista de una sesión y ver faltas acumuladas del ciclo. */
export function SessionAttendance({ sessionId }: { sessionId: string }) {
  const data = useAsync(async () => {
    const session = await getSession(sessionId)
    if (!session) return null
    const [groups, subjects, students, saved] = await Promise.all([
      listGroups(),
      listSubjects(),
      listStudentsMinimal(),
      listAttendance(sessionId),
    ])
    return { session, groups, subjects, students: students.filter((s) => s.group_id === session.group_id), saved }
  }, [sessionId])
  const [marks, setMarks] = useState<Record<string, AttendanceStatus>>({})
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [result, setResult] = useState<AttendanceResult[] | null>(null)
  const sending = useRef(false)
  const d = data.data

  if (data.loading && !d) return <Page title="Asistencia"><Loading /></Page>
  if (data.error && !d) return <Page title="Asistencia"><ErrorBanner error={data.error} onRetry={data.reload} /></Page>
  if (!d) {
    return (
      <Page title="Sesión no encontrada">
        <Empty>La sesión no existe o no es tuya.</Empty>
        <button type="button" className="btn btn-ghost" onClick={() => navigate('/asistencia')}>Volver</button>
      </Page>
    )
  }

  const { session, students, saved } = d
  const group = d.groups.find((g) => g.id === session.group_id)
  const subject = d.subjects.find((s) => s.id === session.subject_id)
  const registered = saved.length > 0 || result !== null
  const name = (id: string) => students.find((s) => s.id === id)?.full_name ?? id
  const markOf = (id: string): AttendanceStatus => marks[id] ?? 'present'

  async function submit() {
    if (sending.current) return
    sending.current = true
    setBusy(true)
    setFailure(null)
    setUncertain(false)
    try {
      const rowsOut = await recordAttendance(
        session.id,
        students.map((s) => ({ student_id: s.id, status: markOf(s.id) })),
      )
      setResult(rowsOut)
    } catch (e) {
      const err = asAppError(e)
      if (err.hint === 'ATTENDANCE_DUPLICATE') {
        data.reload() // ya estaba registrada: se muestra lo guardado
      } else if (err.kind === 'uncertain') {
        setUncertain(true)
        data.reload() // si el servidor sí guardó, la lectura lo mostrará
      } else {
        setFailure(err) // todo o nada: el servidor rechazó y no guardó ninguna fila
      }
    } finally {
      sending.current = false
      setBusy(false)
    }
  }

  return (
    <Page
      title={`${group?.name ?? '—'} · ${subject?.name ?? '—'}`}
      subtitle={`${formatDateTime(session.starts_at)}${group ? ` · ${SHIFT_LABEL[group.shift]}` : ''}`}
    >
      <button type="button" className="btn btn-ghost" onClick={() => navigate('/asistencia')}>← Mis sesiones</button>

      {uncertain && !registered && (
        <Notice tone="warn" title="No podemos confirmar el resultado">
          Perdimos la conexión y la lectura no muestra asistencia guardada. Ya puedes volver a enviar: el servidor rechaza duplicados.
        </Notice>
      )}
      {failure && <ErrorBanner error={failure} />}

      {result && (
        <Card title="Asistencia registrada">
          <Notice tone="ok">Se guardó la asistencia de {result.length} alumnos.</Notice>
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Alumno</th><th>Estado</th><th>Faltas en el ciclo</th><th>Aviso</th></tr>
              </thead>
              <tbody>
                {result.map((r) => (
                  <tr key={r.student_id}>
                    <td>{name(r.student_id)}</td>
                    <td><Badge tone={STATUS_TONE[r.status]}>{STATUS_LABEL[r.status]}</Badge></td>
                    <td><strong>{r.absences_counted}</strong></td>
                    <td>
                      {r.review_active ? (
                        <Badge tone="danger">En revisión</Badge>
                      ) : r.warning_active ? (
                        <Badge tone="warn">Advertencia</Badge>
                      ) : (
                        <span className="muted">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Notice tone="info">
            La advertencia y la revisión son informativas. La decisión académica la toma dirección (pantalla pendiente de B05).
          </Notice>
        </Card>
      )}

      {!result && saved.length > 0 && (
        <Card title="Asistencia ya registrada">
          <div className="table-wrap">
            <table>
              <thead><tr><th>Alumno</th><th>Estado</th></tr></thead>
              <tbody>
                {saved.map((r) => (
                  <tr key={r.student_id}>
                    <td>{name(r.student_id)}</td>
                    <td><Badge tone={STATUS_TONE[r.status]}>{STATUS_LABEL[r.status]}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Notice tone="info">La asistencia de una sesión se registra una sola vez. Las faltas acumuladas se muestran al registrarla.</Notice>
        </Card>
      )}

      {!registered && (
        <Card title="Pasar lista">
          {students.length === 0 ? (
            <Empty>Este grupo aún no tiene alumnos con matrícula activa.</Empty>
          ) : (
            <>
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Alumno</th><th>Estado</th></tr></thead>
                  <tbody>
                    {students.map((s) => (
                      <tr key={s.id}>
                        <td>{s.full_name}</td>
                        <td>
                          <div className="filters" role="radiogroup" aria-label={`Estado de ${s.full_name}`}>
                            {(['present', 'absent', 'late'] as const).map((st) => (
                              <label key={st} className="check">
                                <input
                                  type="radio"
                                  name={`st-${s.id}`}
                                  checked={markOf(s.id) === st}
                                  onChange={() => setMarks((m) => ({ ...m, [s.id]: st }))}
                                  disabled={busy}
                                />
                                {STATUS_LABEL[st]}
                              </label>
                            ))}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="actions">
                <button type="button" className="btn btn-primary" onClick={submit} disabled={busy}>
                  {busy ? 'Guardando…' : 'Guardar asistencia'}
                </button>
              </div>
            </>
          )}
        </Card>
      )}
    </Page>
  )
}
