import { useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import { listCharges, listPayments, listStudents, signedVoucherUrl, voidPayment } from '../lib/api'
import { CHARGE_TYPE_LABEL, ENROLLMENT_LABEL, formatDate, money } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate } from '../lib/router'
import type { VoidResult } from '../lib/types'

/** D06 / D06a — Finanzas (dirección): pagos con voucher y anulación con motivo. */
export default function Finance() {
  const data = useAsync(async () => {
    const [payments, charges, students] = await Promise.all([listPayments(), listCharges(), listStudents()])
    return { payments, charges, students }
  }, [])
  const [voiding, setVoiding] = useState<string | null>(null)
  const [reason, setReason] = useState('')
  const [reasonError, setReasonError] = useState('')
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [done, setDone] = useState<VoidResult | null>(null)
  const [filter, setFilter] = useState<'all' | 'confirmed' | 'voided'>('all')
  const d = data.data

  async function openVoucher(path: string) {
    setFailure(null)
    try {
      window.open(await signedVoucherUrl(path), '_blank', 'noopener,noreferrer')
    } catch (e) {
      setFailure(asAppError(e))
    }
  }

  async function confirmVoid(paymentId: string) {
    if (busy) return
    if (!reason.trim()) {
      setReasonError('Escribe el motivo de la anulación.')
      return
    }
    setReasonError('')
    setBusy(true)
    setFailure(null)
    try {
      const res = await voidPayment(paymentId, reason)
      setDone(res)
      setVoiding(null)
      setReason('')
    } catch (e) {
      setFailure(asAppError(e))
    } finally {
      setBusy(false)
      // Siempre se relee del servidor: tras éxito, rechazo o conexión perdida.
      data.reload()
    }
  }

  const rows = (d?.payments ?? []).filter((p) => filter === 'all' || p.status === filter)
  const studentOfCharge = (chargeId: string) => {
    const c = d?.charges.find((x) => x.id === chargeId)
    return { charge: c, student: d?.students.find((s) => s.id === c?.student_id) }
  }

  return (
    <Page title="Finanzas" subtitle="Pagos registrados con su voucher. Solo dirección puede anular, siempre con motivo.">
      {done && (
        <Notice tone="ok" title="Pago anulado">
          Saldo del cargo restaurado: {money(Number(done.charge_balance))}. Estado de la matrícula:{' '}
          {ENROLLMENT_LABEL[done.enrollment_status]}.
        </Notice>
      )}
      {failure && failure.kind === 'uncertain' && (
        <Notice tone="warn" title="No podemos confirmar el resultado">
          Perdimos la conexión. Revisa abajo si el pago figura como anulado antes de repetir la operación.
        </Notice>
      )}
      {failure && failure.kind !== 'uncertain' && <ErrorBanner error={failure} />}

      <div className="filters" role="group" aria-label="Filtrar pagos">
        {(['all', 'confirmed', 'voided'] as const).map((f) => (
          <button key={f} type="button" className={`btn ${filter === f ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setFilter(f)}>
            {{ all: 'Todos', confirmed: 'Confirmados', voided: 'Anulados' }[f]}
          </button>
        ))}
      </div>

      {data.loading && !d && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}
      {d && rows.length === 0 && <Empty>No hay pagos {filter === 'all' ? 'registrados' : 'con ese estado'}.</Empty>}
      {d && rows.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>Fecha</th><th>Alumno</th><th>Cargo</th><th>Monto</th><th>Referencia</th><th>Estado</th><th /></tr>
            </thead>
            <tbody>
              {rows.map((p) => {
                const { charge, student } = studentOfCharge(p.charge_id)
                const voided = p.status === 'voided'
                return (
                  <tr key={p.id} className={voided ? 'voided' : ''}>
                    <td>{formatDate(p.paid_at ?? p.created_at)}</td>
                    <td>
                      {student ? (
                        <button type="button" className="link" onClick={() => navigate(`/alumnos/${student.id}`)}>
                          {student.full_name}
                        </button>
                      ) : '—'}
                    </td>
                    <td>{charge ? CHARGE_TYPE_LABEL[charge.type] : '—'}</td>
                    <td>{money(Number(p.amount))}</td>
                    <td>{p.reference}</td>
                    <td>
                      <Badge tone={voided ? 'danger' : 'ok'}>{voided ? 'Anulado' : 'Confirmado'}</Badge>
                      {voided && (
                        <div className="muted">
                          {p.void_reason ? `Motivo: ${p.void_reason}` : ''}
                          {p.voided_at ? ` · ${formatDate(p.voided_at)}` : ''}
                        </div>
                      )}
                    </td>
                    <td className="right nowrap">
                      <button type="button" className="btn btn-ghost" onClick={() => openVoucher(p.voucher_path)}>
                        Ver voucher
                      </button>
                      {!voided && (
                        <button
                          type="button"
                          className="btn btn-ghost danger"
                          onClick={() => {
                            setVoiding(voiding === p.id ? null : p.id)
                            setReason('')
                            setReasonError('')
                            setDone(null)
                            setFailure(null)
                          }}
                        >
                          Anular
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {voiding && d && (
        <Card title="Anular pago">
          <Notice tone="warn">
            Al anular, el saldo del cargo se restablece. Si este pago había activado la inscripción, la matrícula puede
            volver a «Pendiente de pago» y liberar el cupo.
          </Notice>
          <Field label="Motivo de la anulación (obligatorio)" error={reasonError}>
            <textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          <div className="actions">
            <button type="button" className="btn btn-ghost" onClick={() => setVoiding(null)} disabled={busy}>
              Cancelar
            </button>
            <button type="button" className="btn btn-danger" onClick={() => confirmVoid(voiding)} disabled={busy}>
              {busy ? 'Anulando…' : 'Confirmar anulación'}
            </button>
          </div>
        </Card>
      )}
    </Page>
  )
}
