import { Empty } from '../components/ui'
import type { EnrollmentTransfer, Group, Student } from '../lib/types'

const dateTime = (iso: string) =>
  new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(iso))

/** Historial de `enrollment_transfers` (B06): solo lectura, del más reciente al más antiguo. */
export function TransferHistory({
  transfers,
  groups,
  students,
  showStudent = false,
}: {
  transfers: EnrollmentTransfer[]
  groups: Group[]
  students?: Pick<Student, 'id' | 'full_name'>[]
  showStudent?: boolean
}) {
  if (transfers.length === 0) return <Empty>Todavía no hay traslados registrados.</Empty>
  const group = (id: string) => groups.find((g) => g.id === id)?.name ?? '—'
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>{showStudent && <th>Alumno</th>}<th>Fecha</th><th>De</th><th>A</th></tr>
        </thead>
        <tbody>
          {transfers.map((t) => (
            <tr key={t.id}>
              {showStudent && <td>{students?.find((s) => s.id === t.student_id)?.full_name ?? '—'}</td>}
              <td className="nowrap">{dateTime(t.transferred_at)}</td>
              <td>{group(t.from_group_id)}</td>
              <td>{group(t.to_group_id)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
