import { Card, Empty, ErrorBanner, Loading, Page, useAsync } from '../components/ui'
import { listAssignments, listGroups, listStudentsMinimal, listSubjects } from '../lib/api'
import { SHIFT_LABEL } from '../lib/domain'

/**
 * T01 — Mis grupos y cursos (docente).
 * Pide solo id, nombre y grupo del alumno: lista mínima, sin pagos, apoderados ni estados de matrícula.
 */
export default function TeacherHome() {
  const data = useAsync(async () => {
    const [groups, subjects, assignments, students] = await Promise.all([
      listGroups(),
      listSubjects(),
      listAssignments(),
      listStudentsMinimal(),
    ])
    return { groups, subjects, assignments, students }
  }, [])
  const d = data.data

  return (
    <Page title="Mis grupos y cursos" subtitle="Solo ves los grupos y cursos que dirección te asignó.">
      {data.loading && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && d.groups.length === 0 && <Empty>Todavía no tienes grupos asignados.</Empty>}
      {d?.groups.map((g) => {
        const subjects = d.assignments
          .filter((a) => a.group_id === g.id)
          .map((a) => d.subjects.find((s) => s.id === a.subject_id)?.name)
          .filter(Boolean)
        const students = d.students.filter((s) => s.group_id === g.id)
        return (
          <Card key={g.id} title={`${g.name} · ${SHIFT_LABEL[g.shift]}`}>
            <p className="muted">Cursos: {subjects.length ? subjects.join(', ') : '—'}</p>
            {students.length === 0 ? (
              <Empty>Aún no hay alumnos con matrícula activa en este grupo.</Empty>
            ) : (
              <ul className="chips">
                {students.map((s) => (
                  <li key={s.id}>{s.full_name}</li>
                ))}
              </ul>
            )}
          </Card>
        )
      })}
    </Page>
  )
}
