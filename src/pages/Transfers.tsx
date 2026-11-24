import { useEffect, useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, SeatBar, useAsync } from '../components/ui'
import { capacities, listCycles, listEnrollments, listGroups, listStudents, listTransfers, transferStudent } from '../lib/api'
import { ENROLLMENT_LABEL, occupiesSeat, SHIFT_LABEL } from '../lib/domain'
import { TransferHistory } from './TransferHistory'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { enrollmentTone } from './Students'

/** D05a — Trasladar alumno (dirección). Usa `transfer_student` (B02); el historial llega con B06. */
export default function Transfers() {
  const data = useAsync(async () => {
    const [students, enrollments, groups, cycles, transfers] = await Promise.all([
      listStudents(),
      listEnrollments(),
      listGroups(),
      listCycles(),
      listTransfers(),
    ])
    return { students, enrollments, groups, cycles, transfers, caps: await capacities(groups) }
  }, [])
  const [studentId, setStudentId] = useState('')
  const [target, setTarget] = useState('')
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [okMessage, setOkMessage] = useState('')
  const d = data.data

  useEffect(() => {
    setTarget('')
  }, [studentId])

  // Solo se puede trasladar una matrícula activa o excepcional.
  const movable = (d?.students ?? []).filter((s) =>
    d?.enrollments.some((e) => e.student_id === s.id && occupiesSeat(e.status)),
  )
  const enrollment = d?.enrollments.find((e) => e.student_id === studentId && occupiesSeat(e.status))
  const current = d?.groups.find((g) => g.id === enrollment?.group_id)
  const destinations = (d?.groups ?? []).filter((g) => enrollment && g.cycle_id === enrollment.cycle_id && g.id !== enrollment.group_id)
  const student = d?.students.find((s) => s.id === studentId)
  const destination = destinations.find((g) => g.id === target)

  async function confirm() {
    if (busy || !studentId || !target) return
    setBusy(true)
    setFailure(null)
    setUncertain(false)
    setOkMessage('')
    try {
      await transferStudent(studentId, target)
      setOkMessage(`${student?.full_name ?? 'El alumno'} fue trasladado a ${destination?.name ?? 'el grupo destino'}.`)
      setTarget('')
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') setUncertain(true)
      else setFailure(err)
    } finally {
      setBusy(false)
      // Se relee grupo actual y cupos: tras un rechazo se ve que nada cambió.
      data.reload()
    }
  }

  return (
    <Page title="Traslados" subtitle="Cambia a un alumno de grupo dentro del mismo ciclo. Solo matrículas activas o excepcionales.">
      {okMessage && <Notice tone="ok" title="Traslado realizado">{okMessage}</Notice>}
      {failure && (
        <ErrorBanner error={failure} />
      )}
      {failure && (failure.hint === 'TRANSFER_GROUP_FULL' || failure.hint === 'GROUP_FULL') && (
        <Notice tone="info">Los cupos de abajo se volvieron a leer del servidor: el grupo de origen y el destino siguen igual.</Notice>
      )}
      {uncertain && (
        <Notice tone="warn" title="No podemos confirmar el resultado">
          Perdimos la conexión. Revisa el grupo actual del alumno en esta pantalla antes de repetir el traslado.
        </Notice>
      )}

      {data.loading && !d && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && movable.length === 0 && <Empty>No hay alumnos con matrícula activa o excepcional para trasladar.</Empty>}

      {d && movable.length > 0 && (
        <Card title="1. Alumno">
          <Field label="Alumno">
            <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
              <option value="">Elige un alumno</option>
              {movable.map((s) => (
                <option key={s.id} value={s.id}>{s.full_name}</option>
              ))}
            </select>
          </Field>
          {enrollment && (
            <>
              <p>
                <Badge tone={enrollmentTone[enrollment.status]}>{ENROLLMENT_LABEL[enrollment.status]}</Badge>{' '}
                Grupo actual: <strong>{current?.name ?? '—'}</strong>
                {current && ` · ${SHIFT_LABEL[current.shift]}`}
              </p>
              {current && d.caps[current.id] && (
                <SeatBar capacity={d.caps[current.id].capacity} occupied={d.caps[current.id].occupied} />
              )}
            </>
          )}
        </Card>
      )}

      {enrollment && (
        <Card title="2. Grupo destino">
          {destinations.length === 0 ? (
            <Empty>Este ciclo no tiene otro grupo al que trasladar.</Empty>
          ) : (
            <>
              <ul className="list">
                {destinations.map((g) => {
                  const cap = d!.caps[g.id]
                  return (
                    <li key={g.id}>
                      <label className="check">
                        <input type="radio" name="target" checked={target === g.id} onChange={() => setTarget(g.id)} disabled={busy} />
                        <span>{g.name} · {SHIFT_LABEL[g.shift]}</span>
                      </label>
                      {cap ? <SeatBar capacity={cap.capacity} occupied={cap.occupied} /> : <span className="muted">Cupo no disponible</span>}
                    </li>
                  )
                })}
              </ul>
              {destination && d!.caps[destination.id]?.available <= 0 && (
                <Notice tone="warn">Este grupo está lleno: el servidor rechazará el traslado y no cambiará nada.</Notice>
              )}
              <div className="actions">
                <button type="button" className="btn btn-primary" onClick={confirm} disabled={busy || !target}>
                  {busy ? 'Trasladando…' : 'Confirmar traslado'}
                </button>
              </div>
            </>
          )}
        </Card>
      )}

      {d && (
        <Card title="Historial de traslados">
          <TransferHistory transfers={d.transfers} groups={d.groups} students={d.students} showStudent />
        </Card>
      )}
    </Page>
  )
}
