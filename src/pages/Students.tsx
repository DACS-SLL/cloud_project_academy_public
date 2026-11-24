import { useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Loading, Notice, Page, useAsync } from '../components/ui'
import type { Tone } from '../components/ui'
import { getStudentFile, listCycles, listEnrollments, listGroups, listStudents, listTransfers, signedVoucherUrl } from '../lib/api'
import {
  CHARGE_LABEL,
  CHARGE_TYPE_LABEL,
  chargeView,
  effectiveDueDate,
  ENROLLMENT_LABEL,
  formatDate,
  money,
  todayLima,
} from '../lib/domain'
import type { ChargeState } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate } from '../lib/router'
import { useSession } from '../lib/session'
import { TransferHistory } from './TransferHistory'
import type { EnrollmentStatus } from '../lib/types'

export const enrollmentTone: Record<EnrollmentStatus, Tone> = {
  pending: 'neutral',
  active: 'ok',
  exception: 'warn',
  cancelled: 'danger',
}

export const chargeTone: Record<ChargeState, Tone> = {
  pending: 'neutral',
  partial: 'info',
  overdue: 'danger',
  paid: 'ok',
}

/** C03 — Lista de alumnos con el estado de su matrícula. */
export function StudentList() {
  const data = useAsync(async () => {
    const [students, enrollments, groups, cycles] = await Promise.all([
      listStudents(),
      listEnrollments(),
      listGroups(),
      listCycles(),
    ])
    return { students, enrollments, groups, cycles }
  }, [])
  const [filter, setFilter] = useState('')
  const d = data.data

  const rows = (d?.students ?? []).filter((s) => {
    const q = filter.trim().toLowerCase()
    return !q || s.full_name.toLowerCase().includes(q) || (s.document_id ?? '').includes(q)
  })

  return (
    <Page title="Alumnos" subtitle="Estado de matrícula, grupo y acceso a la ficha con cargos y pagos.">
      <input
        className="search"
        placeholder="Buscar por nombre o DNI"
        aria-label="Buscar alumno"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      />
      {data.loading && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && rows.length === 0 && <Empty>{filter ? 'Ningún alumno coincide con la búsqueda.' : 'Aún no hay alumnos.'}</Empty>}
      {d && rows.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Alumno</th>
                <th>DNI</th>
                <th>Matrícula</th>
                <th>Grupo</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map((s) => {
                const en = d.enrollments.find((x) => x.student_id === s.id)
                const group = d.groups.find((g) => g.id === (en?.group_id ?? s.group_id))
                const cycle = d.cycles.find((c) => c.id === en?.cycle_id)
                return (
                  <tr key={s.id}>
                    <td><strong>{s.full_name}</strong></td>
                    <td>{s.document_id ?? '—'}</td>
                    <td>
                      {en ? (
                        <Badge tone={enrollmentTone[en.status]}>
                          {ENROLLMENT_LABEL[en.status]}
                          {en.status === 'exception' && en.exception_due_date ? ` hasta ${formatDate(en.exception_due_date)}` : ''}
                        </Badge>
                      ) : (
                        <span className="muted">Sin matrícula</span>
                      )}
                    </td>
                    <td>{group ? `${group.name}${cycle ? ` · ${cycle.name}` : ''}` : '—'}</td>
                    <td className="right">
                      <button type="button" className="btn btn-ghost" onClick={() => navigate(`/alumnos/${s.id}`)}>
                        Ver ficha
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </Page>
  )
}

/** C03 — Ficha del alumno: matrícula, apoderados, cargos con saldo y pagos con voucher. */
export function StudentFile({ studentId }: { studentId: string }) {
  const { access } = useSession()
  const file = useAsync(async () => {
    const [f, groups, cycles, transfers] = await Promise.all([getStudentFile(studentId), listGroups(), listCycles(), listTransfers(studentId)])
    return { ...f, groups, cycles, transfers }
  }, [studentId])
  const [voucherError, setVoucherError] = useState<AppError | null>(null)
  const today = todayLima()
  const f = file.data

  async function openVoucher(path: string) {
    setVoucherError(null)
    try {
      const url = await signedVoucherUrl(path)
      window.open(url, '_blank', 'noopener,noreferrer')
    } catch (e) {
      setVoucherError(asAppError(e))
    }
  }

  const back = (
    <button type="button" className="btn btn-ghost" onClick={() => navigate('/alumnos')}>
      ← Alumnos
    </button>
  )

  if (file.loading) return <Page title="Ficha del alumno" actions={back}><Loading /></Page>
  if (file.error || !f)
    return (
      <Page title="Ficha del alumno" actions={back}>
        {file.error && <ErrorBanner error={file.error} onRetry={file.reload} />}
      </Page>
    )

  const en = f.enrollments[0]
  // Cada cargo usa la matrícula a la que pertenece: la fecha excepcional solo rige para su inscripción.
  const views = f.charges.map((c) =>
    chargeView(c, f.payments, today, effectiveDueDate(c, f.enrollments.find((e) => e.id === c.enrollment_id))),
  )
  const overdue = views.filter((v) => v.state === 'overdue').reduce((s, v) => s + v.balance, 0)
  const group = f.groups.find((g) => g.id === (en?.group_id ?? f.student.group_id))
  const cycle = f.cycles.find((c) => c.id === en?.cycle_id)
  const chargeOf = (id: string) => f.charges.find((c) => c.id === id)

  return (
    <Page
      title={f.student.full_name}
      subtitle={`DNI ${f.student.document_id ?? '—'} · ${f.student.school ?? 'Colegio sin registrar'} · ${f.student.grade ?? ''}`}
      actions={back}
    >
      <div className="two-col">
        <Card title="Matrícula">
          {en ? (
            <>
              <p>
                <Badge tone={enrollmentTone[en.status]}>{ENROLLMENT_LABEL[en.status]}</Badge>
              </p>
              <ul className="list">
                <li><span>Ciclo</span><span>{cycle?.name ?? '—'}</span></li>
                <li><span>{en.status === 'pending' ? 'Grupo solicitado' : 'Grupo'}</span><span>{group?.name ?? '—'}</span></li>
                <li><span>Inscripción acordada</span><span>{money(Number(en.agreed_registration_price))}</span></li>
                <li><span>Mensualidad acordada</span><span>{money(Number(en.agreed_monthly_price))}</span></li>
                {en.status === 'exception' && (
                  <>
                    <li><span>Motivo de la excepción</span><span>{en.exception_reason}</span></li>
                    <li><span>Fecha límite de pago</span><span>{formatDate(en.exception_due_date)}</span></li>
                  </>
                )}
              </ul>
              {en.status === 'pending' && (
                <Notice tone="info">Solicitud pendiente: no ocupa cupo ni asigna grupo hasta confirmar la inscripción.</Notice>
              )}
              {access?.role === 'cashier' && (
                <button type="button" className="btn btn-primary" onClick={() => navigate(`/pagos/registrar?student=${f.student.id}`)}>
                  Registrar pago
                </button>
              )}
            </>
          ) : (
            <Empty>Este alumno aún no tiene una matrícula.</Empty>
          )}
        </Card>
        <Card title="Apoderados">
          {f.guardians.length === 0 ? (
            <Empty>Sin apoderados registrados.</Empty>
          ) : (
            <ul className="list">
              {f.guardians.map((g) => (
                <li key={g.id}>
                  <span>{g.full_name}</span>
                  <span>DNI {g.document_id ?? '—'} · Tel. {g.phone ?? '—'}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card title="Historial de traslados">
        <TransferHistory transfers={f.transfers} groups={f.groups} />
      </Card>

      <Card title="Cargos">
        {overdue > 0 && <Notice tone="warn">Importe vencido: {money(overdue)}</Notice>}
        {views.length === 0 ? (
          <Empty>Sin cargos.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Cargo</th><th>Vence</th><th>Monto</th><th>Pagado</th><th>Saldo</th><th>Estado</th></tr>
              </thead>
              <tbody>
                {views.map((v) => (
                  <tr key={v.charge.id}>
                    <td>{CHARGE_TYPE_LABEL[v.charge.type]}</td>
                    <td>
                      {formatDate(v.dueDate)}
                      {v.dueDate !== v.charge.due_date && <span className="muted"> · fecha de la excepción</span>}
                    </td>
                    <td>{money(Number(v.charge.amount))}</td>
                    <td>{money(v.paid)}</td>
                    <td><strong>{money(v.balance)}</strong></td>
                    <td>
                      <Badge tone={chargeTone[v.state]}>
                        {CHARGE_LABEL[v.state]}
                        {v.state === 'partial' ? ` · saldo ${money(v.balance)}` : ''}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title="Pagos">
        {voucherError && <ErrorBanner error={voucherError} />}
        {f.payments.length === 0 ? (
          <Empty>Aún no hay pagos registrados.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Fecha</th><th>Cargo</th><th>Monto</th><th>Referencia</th><th>Estado</th><th /></tr>
              </thead>
              <tbody>
                {f.payments.map((p) => {
                  const ch = chargeOf(p.charge_id)
                  const voided = p.status === 'voided'
                  return (
                    <tr key={p.id} className={voided ? 'voided' : ''}>
                      <td>{formatDate(p.paid_at ?? p.created_at)}</td>
                      <td>{ch ? CHARGE_TYPE_LABEL[ch.type] : '—'}</td>
                      <td>{money(Number(p.amount))}</td>
                      <td>{p.reference}</td>
                      <td>
                        <Badge tone={voided ? 'danger' : 'ok'}>{voided ? 'Anulado' : 'Confirmado'}</Badge>
                        {voided && p.void_reason && <div className="muted">Motivo: {p.void_reason}</div>}
                      </td>
                      <td className="right">
                        <button type="button" className="btn btn-ghost" onClick={() => openVoucher(p.voucher_path)}>
                          Ver voucher
                        </button>
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
