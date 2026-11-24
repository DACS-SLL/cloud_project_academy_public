import { useState } from 'react'
import type { FormEvent } from 'react'
import { Card, Empty, ErrorBanner, Field, Loading, Notice, Page, SeatBar, useAsync } from '../components/ui'
import {
  capacities,
  createAssignment,
  createSubject,
  deleteAssignment,
  listAssignments,
  listCycles,
  listEnrollments,
  listGroups,
  listSubjects,
  listTeachers,
  saveGroup,
} from '../lib/api'
import { SHIFT_LABEL, validateGroup } from '../lib/domain'
import type { FieldErrors } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { useSession } from '../lib/session'
import type { Group, Shift } from '../lib/types'

async function loadAll() {
  const [groups, cycles, enrollments, subjects, assignments, teachers] = await Promise.all([
    listGroups(),
    listCycles(),
    listEnrollments(),
    listSubjects(),
    listAssignments(),
    listTeachers(),
  ])
  const caps = await capacities(groups)
  return { groups, cycles, enrollments, subjects, assignments, teachers, caps }
}

interface Draft {
  name: string
  cycle_id: string
  shift: Shift
  capacity: string
}

/** D03 — Grupos, cupos, cursos y docentes (dirección). */
export default function Groups() {
  const { access } = useSession()
  const data = useAsync(loadAll, [])
  const [editing, setEditing] = useState<string | 'new' | null>(null)
  const [draft, setDraft] = useState<Draft>({ name: '', cycle_id: '', shift: 'morning', capacity: '30' })
  const [errors, setErrors] = useState<FieldErrors>({})
  const [failure, setFailure] = useState<AppError | null>(null)
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState('')

  // Cursos y asignaciones
  const [subjectName, setSubjectName] = useState('')
  const [assign, setAssign] = useState({ teacher: '', group: '', subject: '' })
  const [sideFailure, setSideFailure] = useState<AppError | null>(null)

  const d = data.data

  function open(g?: Group) {
    setEditing(g ? g.id : 'new')
    setDraft(
      g
        ? { name: g.name, cycle_id: g.cycle_id, shift: g.shift, capacity: String(g.capacity) }
        : { name: '', cycle_id: d?.cycles[0]?.id ?? '', shift: 'morning', capacity: '30' },
    )
    setErrors({})
    setFailure(null)
    setSaved('')
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (busy || !access) return
    const capacity = Number(draft.capacity)
    const found = validateGroup({ name: draft.name, cycle_id: draft.cycle_id, capacity })
    setErrors(found)
    if (Object.keys(found).length > 0) return
    setBusy(true)
    setFailure(null)
    try {
      const row = await saveGroup(
        access.academy_id,
        { name: draft.name.trim(), cycle_id: draft.cycle_id, shift: draft.shift, capacity },
        editing && editing !== 'new' ? editing : undefined,
      )
      setSaved(`Grupo «${row.name}» guardado.`)
      setEditing(null)
      data.reload()
    } catch (err) {
      // Tras un rechazo se vuelven a leer los cupos del servidor, no se muestra nada "optimista".
      setFailure(asAppError(err))
      data.reload()
    } finally {
      setBusy(false)
    }
  }

  async function addSubject(e: FormEvent) {
    e.preventDefault()
    if (!access || !subjectName.trim()) return
    setSideFailure(null)
    try {
      await createSubject(access.academy_id, subjectName)
      setSubjectName('')
      data.reload()
    } catch (err) {
      setSideFailure(asAppError(err))
    }
  }

  async function addAssignment(e: FormEvent) {
    e.preventDefault()
    if (!access || !assign.teacher || !assign.group || !assign.subject) return
    setSideFailure(null)
    try {
      await createAssignment(access.academy_id, assign.teacher, assign.group, assign.subject)
      setAssign({ teacher: '', group: '', subject: '' })
      data.reload()
    } catch (err) {
      setSideFailure(asAppError(err))
    }
  }

  async function removeAssignment(id: string) {
    setSideFailure(null)
    try {
      await deleteAssignment(id)
      data.reload()
    } catch (err) {
      setSideFailure(asAppError(err))
    }
  }

  const cycleName = (id: string) => d?.cycles.find((c) => c.id === id)?.name ?? '—'
  const subjectOf = (id: string) => d?.subjects.find((s) => s.id === id)?.name ?? '—'
  const groupOf = (id: string) => d?.groups.find((g) => g.id === id)?.name ?? '—'
  const teacherOf = (id: string) => d?.teachers.find((t) => t.user_id === id)?.full_name ?? 'Docente'

  return (
    <Page
      title="Grupos y cupos"
      subtitle="El cupo lo calcula el servidor: solo las matrículas activas o excepcionales lo ocupan."
      actions={
        editing === null && (
          <button type="button" className="btn btn-primary" onClick={() => open()} disabled={!d || d.cycles.length === 0}>
            Nuevo grupo
          </button>
        )
      }
    >
      {saved && <Notice tone="ok">{saved}</Notice>}
      {data.loading && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && d.cycles.length === 0 && (
        <Notice tone="warn">Primero crea un ciclo en «Ciclos y reglas»; cada grupo pertenece a un ciclo.</Notice>
      )}

      {editing !== null && d && (
        <Card title={editing === 'new' ? 'Nuevo grupo' : 'Editar grupo'}>
          <form onSubmit={submit} noValidate className="form-grid">
            <Field label="Identificador" error={errors.name}>
              <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="Grupo B" />
            </Field>
            <Field label="Ciclo" error={errors.cycle_id}>
              <select
                value={draft.cycle_id}
                onChange={(e) => setDraft({ ...draft, cycle_id: e.target.value })}
                disabled={editing !== 'new'}
              >
                <option value="">Elige un ciclo</option>
                {d.cycles.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Turno">
              <select value={draft.shift} onChange={(e) => setDraft({ ...draft, shift: e.target.value as Shift })}>
                {(Object.keys(SHIFT_LABEL) as Shift[]).map((s) => (
                  <option key={s} value={s}>
                    {SHIFT_LABEL[s]}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Capacidad" error={errors.capacity} hint="No puede ser menor que los cupos ocupados">
              <input
                type="number"
                min={1}
                value={draft.capacity}
                onChange={(e) => setDraft({ ...draft, capacity: e.target.value })}
              />
            </Field>
            {failure && (
              <div className="wide">
                <ErrorBanner error={failure} />
              </div>
            )}
            <div className="actions wide">
              <button type="button" className="btn btn-ghost" onClick={() => setEditing(null)} disabled={busy}>
                Cancelar
              </button>
              <button type="submit" className="btn btn-primary" disabled={busy}>
                {busy ? 'Guardando…' : 'Guardar grupo'}
              </button>
            </div>
          </form>
        </Card>
      )}

      {d && d.groups.length === 0 && d.cycles.length > 0 && <Empty>Aún no hay grupos. Crea el primero.</Empty>}
      {d && d.groups.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Grupo</th>
                <th>Ciclo</th>
                <th>Turno</th>
                <th>Cupo</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {d.groups.map((g) => {
                const cap = d.caps[g.id]
                const pending = d.enrollments.filter((en) => en.group_id === g.id && en.status === 'pending').length
                return (
                  <tr key={g.id}>
                    <td>
                      <strong>{g.name}</strong>
                    </td>
                    <td>{cycleName(g.cycle_id)}</td>
                    <td>{SHIFT_LABEL[g.shift]}</td>
                    <td>
                      {cap ? (
                        <SeatBar capacity={cap.capacity} occupied={cap.occupied} pending={pending} />
                      ) : (
                        <span className="muted">No se pudo leer el cupo</span>
                      )}
                    </td>
                    <td className="right">
                      <button type="button" className="btn btn-ghost" onClick={() => open(g)}>
                        Editar
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {d && (
        <div className="two-col">
          <Card title="Cursos">
            <form onSubmit={addSubject} className="inline-form">
              <input
                value={subjectName}
                onChange={(e) => setSubjectName(e.target.value)}
                placeholder="Nombre del curso"
                aria-label="Nombre del curso"
              />
              <button type="submit" className="btn btn-primary" disabled={!subjectName.trim()}>
                Agregar
              </button>
            </form>
            {d.subjects.length === 0 ? (
              <Empty>Aún no hay cursos.</Empty>
            ) : (
              <ul className="chips">
                {d.subjects.map((s) => (
                  <li key={s.id}>{s.name}</li>
                ))}
              </ul>
            )}
          </Card>

          <Card title="Docentes por grupo y curso">
            <form onSubmit={addAssignment} className="stack">
              <select value={assign.teacher} onChange={(e) => setAssign({ ...assign, teacher: e.target.value })} aria-label="Docente">
                <option value="">Docente</option>
                {d.teachers.map((t) => (
                  <option key={t.user_id} value={t.user_id}>
                    {t.full_name}
                  </option>
                ))}
              </select>
              <select value={assign.group} onChange={(e) => setAssign({ ...assign, group: e.target.value })} aria-label="Grupo">
                <option value="">Grupo</option>
                {d.groups.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.name}
                  </option>
                ))}
              </select>
              <select value={assign.subject} onChange={(e) => setAssign({ ...assign, subject: e.target.value })} aria-label="Curso">
                <option value="">Curso</option>
                {d.subjects.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
              <button
                type="submit"
                className="btn btn-primary"
                disabled={!assign.teacher || !assign.group || !assign.subject}
              >
                Asignar
              </button>
            </form>
            {d.assignments.length === 0 ? (
              <Empty>Aún no hay asignaciones.</Empty>
            ) : (
              <ul className="list">
                {d.assignments.map((a) => (
                  <li key={a.id}>
                    <span>
                      {teacherOf(a.teacher_id)} · {groupOf(a.group_id)} · {subjectOf(a.subject_id)}
                    </span>
                    <button type="button" className="btn btn-ghost" onClick={() => removeAssignment(a.id)}>
                      Quitar
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      )}
      {sideFailure && <ErrorBanner error={sideFailure} />}
    </Page>
  )
}
