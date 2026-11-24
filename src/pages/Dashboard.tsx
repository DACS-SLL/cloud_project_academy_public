import { useEffect, useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, SeatBar, useAsync } from '../components/ui'
import { capacities, cycleCases, listCycles, listEnrollments, listGroups } from '../lib/api'
import { formatDate, money, SHIFT_LABEL, todayLima } from '../lib/domain'
import { navigate } from '../lib/router'

/**
 * D01 / C01 — Tablero (dirección y secretaría).
 * La deuda vencida y las faltas vienen de `cycle_cases` (B05): la base ya aplica la fecha
 * excepcional y los pagos anulados. La interfaz solo suma y presenta.
 */
export default function Dashboard() {
  const cycles = useAsync(listCycles, [])
  const [cycleId, setCycleId] = useState('')
  useEffect(() => {
    if (cycleId || !cycles.data || cycles.data.length === 0) return
    const today = todayLima()
    const current = cycles.data.find((c) => c.start_date <= today && today <= c.end_date)
    setCycleId((current ?? cycles.data[0]).id)
  }, [cycles.data, cycleId])

  const data = useAsync(
    async () => {
      if (!cycleId) return null
      const [cases, enrollments, groups] = await Promise.all([cycleCases(cycleId), listEnrollments(), listGroups()])
      const inCycle = groups.filter((g) => g.cycle_id === cycleId)
      return { cases, enrollments: enrollments.filter((e) => e.cycle_id === cycleId), groups: inCycle, caps: await capacities(inCycle) }
    },
    [cycleId],
  )
  const d = data.data

  const debt = (d?.cases ?? []).filter((c) => c.case_type === 'debt')
  const absences = (d?.cases ?? []).filter((c) => c.case_type === 'attendance')
  const overdueTotal = debt.reduce((s, c) => s + (c.balance ?? 0), 0)
  const needDecision = absences.filter((c) => c.status === 'needs_decision')
  const pending = (d?.enrollments ?? []).filter((e) => e.status === 'pending')
  const exceptions = (d?.enrollments ?? []).filter((e) => e.status === 'exception')

  return (
    <Page title="Tablero" subtitle="Datos del ciclo elegido. Deuda y faltas calculadas por la base de datos.">
      {cycles.error && <ErrorBanner error={cycles.error} onRetry={cycles.reload} />}
      {cycles.data && cycles.data.length === 0 && <Empty>Aún no hay ciclos. Dirección debe crear uno.</Empty>}
      {cycles.data && cycles.data.length > 0 && (
        <Field label="Ciclo">
          <select value={cycleId} onChange={(e) => setCycleId(e.target.value)}>
            {cycles.data.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </Field>
      )}
      {data.loading && !d && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}

      {d && (
        <>
          <div className="kpis">
            <div className="kpi">
              <span className="kpi-label">Deuda vencida</span>
              <strong>{money(overdueTotal)}</strong>
              <span className="muted">{debt.length} alumno{debt.length === 1 ? '' : 's'}</span>
            </div>
            <div className="kpi">
              <span className="kpi-label">Solicitudes pendientes</span>
              <strong>{pending.length}</strong>
              <span className="muted">no ocupan cupo</span>
            </div>
            <div className="kpi">
              <span className="kpi-label">Excepciones vigentes</span>
              <strong>{exceptions.length}</strong>
              <span className="muted">ocupan cupo</span>
            </div>
            <div className="kpi">
              <span className="kpi-label">Faltas por decidir</span>
              <strong>{needDecision.length}</strong>
              <span className="muted">{absences.length} con aviso</span>
            </div>
          </div>

          <Card title="Deuda vencida">
            {debt.length === 0 ? (
              <Empty>No hay deuda vencida en este ciclo.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr><th>Alumno</th><th>Vencida</th><th>Saldo total</th><th>Desde</th><th /></tr>
                  </thead>
                  <tbody>
                    {debt.map((c) => (
                      <tr key={c.student_id}>
                        <td><strong>{c.full_name}</strong></td>
                        <td><strong>{money(c.balance ?? 0)}</strong> <Badge tone="danger">Vencida</Badge></td>
                        <td>{money(c.total_balance ?? 0)}</td>
                        <td className="nowrap">{formatDate(c.due_date)}</td>
                        <td className="right">
                          <button type="button" className="btn btn-ghost" onClick={() => navigate(`/alumnos/${c.student_id}`)}>Ver ficha</button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <Notice tone="info">
              La excepción con fecha futura no aparece como vencida hasta su fecha límite. El seguimiento se registra en{' '}
              <button type="button" className="link" onClick={() => navigate('/casos')}>Casos</button>.
            </Notice>
          </Card>

          <Card title="Faltas">
            {absences.length === 0 ? (
              <Empty>Ningún alumno alcanzó el aviso de faltas.</Empty>
            ) : (
              <ul className="list">
                {absences.map((c) => (
                  <li key={c.student_id}>
                    <span><strong>{c.full_name}</strong> · {c.absences} falta{c.absences === 1 ? '' : 's'} (límite {c.review_threshold})</span>
                    <Badge tone={c.status === 'needs_decision' ? 'danger' : c.status === 'resolved' ? 'ok' : 'warn'}>
                      {c.status === 'needs_decision' ? 'Requiere decisión' : c.status === 'resolved' ? 'Resuelto' : 'Aviso'}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card title="Cupos por grupo">
            {d.groups.length === 0 ? (
              <Empty>Este ciclo aún no tiene grupos.</Empty>
            ) : (
              <ul className="list">
                {d.groups.map((g) => {
                  const cap = d.caps[g.id]
                  const pendingHere = d.enrollments.filter((e) => e.group_id === g.id && e.status === 'pending').length
                  return (
                    <li key={g.id}>
                      <span><strong>{g.name}</strong> · {SHIFT_LABEL[g.shift]}</span>
                      {cap ? <SeatBar capacity={cap.capacity} occupied={cap.occupied} pending={pendingHere} /> : <span className="muted">Cupo no disponible</span>}
                    </li>
                  )
                })}
              </ul>
            )}
          </Card>
        </>
      )}
    </Page>
  )
}
