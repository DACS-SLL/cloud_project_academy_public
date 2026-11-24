import { useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import { authorizeEnrollmentException, capacities, listCharges, listCycles, listEnrollments, listGroups, listPayments, listStudents } from '../lib/api'
import { chargeView, formatDate, money, SHIFT_LABEL, todayLima } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate } from '../lib/router'

/** D04a — Autorizar matrícula excepcional (solo dirección, RPC B06). La inscripción impaga sigue como deuda. */
export default function Exceptions() {
  const data = useAsync(async () => {
    const [students, enrollments, groups, cycles, charges, payments] = await Promise.all([
      listStudents(),
      listEnrollments(),
      listGroups(),
      listCycles(),
      listCharges(),
      listPayments(),
    ])
    return { students, enrollments, groups, cycles, charges, payments, caps: await capacities(groups) }
  }, [])
  const [enrollmentId, setEnrollmentId] = useState('')
  const [reason, setReason] = useState('')
  const [dueDate, setDueDate] = useState('')
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [done, setDone] = useState('')
  const d = data.data
  const today = todayLima()

  if (data.loading && !d) return <Page title="Excepciones"><Loading /></Page>
  if (data.error && !d) return <Page title="Excepciones"><ErrorBanner error={data.error} onRetry={data.reload} /></Page>
  if (!d) return null

  const pending = d.enrollments.filter((e) => e.status === 'pending')
  const exceptions = d.enrollments.filter((e) => e.status === 'exception')
  const nameOf = (id: string) => d.students.find((s) => s.id === id)?.full_name ?? '—'
  const groupOf = (id: string) => d.groups.find((g) => g.id === id)
  const selected = pending.find((e) => e.id === enrollmentId)
  const cap = selected ? d.caps[selected.group_id] : undefined
  const registrationBalance = (enrollment: string) =>
    d.charges
      .filter((c) => c.enrollment_id === enrollment && c.type === 'registration')
      .map((c) => chargeView(c, d.payments, today))
      .reduce((s, v) => s + v.balance, 0)

  async function submit() {
    if (busy || !selected) return
    const found: Record<string, string> = {}
    if (!reason.trim()) found.reason = 'Escribe el motivo de la excepción.'
    if (!dueDate) found.dueDate = 'Indica la fecha límite de pago.'
    setErrors(found)
    if (Object.keys(found).length) return
    setBusy(true)
    setFailure(null)
    setUncertain(false)
    setDone('')
    try {
      await authorizeEnrollmentException(selected.id, reason.trim(), dueDate)
      setDone(`${nameOf(selected.student_id)} quedó con matrícula excepcional y ocupa cupo.`)
      setEnrollmentId('')
      setReason('')
      setDueDate('')
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') setUncertain(true)
      else setFailure(err)
    } finally {
      setBusy(false)
      data.reload() // se relee: tras un rechazo o una respuesta perdida se ve el estado real de la matrícula
    }
  }

  return (
    <Page title="Excepciones" subtitle="Permite que un alumno asista con la inscripción impaga hasta una fecha límite. Ocupa cupo y la deuda se conserva.">
      {done && <Notice tone="ok" title="Excepción autorizada">{done}</Notice>}
      {failure && <ErrorBanner error={failure} />}
      {failure?.hint === 'EXCEPTION_STATUS_INVALID' && (
        <Notice tone="info">Se actualizó la lista: revisa el estado actual de la matrícula.</Notice>
      )}
      {uncertain && (
        <Notice tone="warn" title="No podemos confirmar el resultado">
          Perdimos la conexión. La lista de abajo se volvió a leer: si la matrícula ya figura como excepcional, la autorización se guardó. No la repitas hasta comprobarlo.
        </Notice>
      )}

      <Card title="Autorizar excepción">
        {pending.length === 0 ? (
          <Empty>No hay solicitudes pendientes.</Empty>
        ) : (
          <>
            <Field label="Solicitud pendiente">
              <select value={enrollmentId} onChange={(e) => setEnrollmentId(e.target.value)} disabled={busy}>
                <option value="">Elige una solicitud</option>
                {pending.map((e) => (
                  <option key={e.id} value={e.id}>
                    {nameOf(e.student_id)} · {groupOf(e.group_id)?.name ?? '—'}
                  </option>
                ))}
              </select>
            </Field>
            {selected && (
              <>
                <p className="muted">
                  Grupo: {groupOf(selected.group_id)?.name} · {groupOf(selected.group_id) && SHIFT_LABEL[groupOf(selected.group_id)!.shift]}
                  {cap && ` · Cupos libres: ${cap.available}`}
                  {` · Inscripción pendiente: ${money(registrationBalance(selected.id))}`}
                </p>
                {cap && cap.available <= 0 && (
                  <Notice tone="warn">El grupo no tiene vacante: el servidor rechazará la excepción (GROUP_FULL) y no cambiará nada.</Notice>
                )}
                <div className="form-grid">
                  <Field label="Motivo" error={errors.reason}>
                    <textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} disabled={busy} />
                  </Field>
                  <Field label="Fecha límite de pago" error={errors.dueDate} hint="Pasada esta fecha la matrícula sigue activa y la inscripción se marca vencida.">
                    <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} disabled={busy} />
                  </Field>
                </div>
                {dueDate && dueDate < today && (
                  <Notice tone="warn">La fecha ya pasó: la inscripción aparecerá como vencida de inmediato.</Notice>
                )}
                <div className="actions">
                  <button type="button" className="btn btn-primary" onClick={submit} disabled={busy}>
                    {busy ? 'Autorizando…' : 'Autorizar excepción'}
                  </button>
                </div>
              </>
            )}
          </>
        )}
      </Card>

      <Card title="Excepciones vigentes">
        {exceptions.length === 0 ? (
          <Empty>No hay matrículas excepcionales.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Alumno</th><th>Grupo</th><th>Motivo</th><th>Fecha límite</th><th>Inscripción</th><th /></tr>
              </thead>
              <tbody>
                {exceptions.map((e) => {
                  const bal = registrationBalance(e.id)
                  const late = !!e.exception_due_date && e.exception_due_date < today && bal > 0
                  return (
                    <tr key={e.id}>
                      <td><strong>{nameOf(e.student_id)}</strong></td>
                      <td>{groupOf(e.group_id)?.name ?? '—'}</td>
                      <td>{e.exception_reason}</td>
                      <td className="nowrap">{formatDate(e.exception_due_date)}</td>
                      <td>
                        {bal === 0 ? <Badge tone="ok">Pagada</Badge> : late ? <Badge tone="danger">Vencida · {money(bal)}</Badge> : <Badge tone="warn">Pendiente · {money(bal)}</Badge>}
                      </td>
                      <td className="right">
                        <button type="button" className="btn btn-ghost" onClick={() => navigate(`/alumnos/${e.student_id}`)}>Ver ficha</button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </Page>
  )
}
