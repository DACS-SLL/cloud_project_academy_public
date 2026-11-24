import { useEffect, useState } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import type { Tone } from '../components/ui'
import { cycleCases, listCycles, listDecisions, listFollowups, registerAcademicDecision, registerFollowup } from '../lib/api'
import { formatDate, money } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { useSession } from '../lib/session'
import type { CaseStatus, CycleCase, DecisionKind, FollowupChannel } from '../lib/types'

const STATUS_LABEL: Record<CaseStatus, string> = { open: 'Abierto', resolved: 'Resuelto', needs_decision: 'Requiere decisión' }
const STATUS_TONE: Record<CaseStatus, Tone> = { open: 'warn', resolved: 'ok', needs_decision: 'danger' }
const CHANNEL_LABEL: Record<FollowupChannel, string> = { call: 'Llamada', whatsapp: 'WhatsApp', email: 'Correo', in_person: 'En persona' }
const DECISION_LABEL: Record<DecisionKind, string> = { continue: 'Continúa', close_case: 'Cerrar caso', other: 'Otra' }
const dateTime = (iso: string) =>
  new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(iso))

type Panel = { kind: 'followup' | 'decision'; row: CycleCase } | null

/**
 * C05–C07 / D07 — Casos de deuda y faltas del ciclo, contactos y decisión académica.
 * Todo viene de `cycle_cases` (B05): la interfaz no calcula deuda ni faltas.
 */
export default function Cases() {
  const { access } = useSession()
  const isAdmin = access?.role === 'admin'
  const cycles = useAsync(listCycles, [])
  const [cycleId, setCycleId] = useState('')
  useEffect(() => {
    if (!cycleId && cycles.data && cycles.data.length > 0) setCycleId(cycles.data[0].id)
  }, [cycles.data, cycleId])

  const data = useAsync(
    async () => {
      if (!cycleId) return null
      const [cases, followups, decisions] = await Promise.all([cycleCases(cycleId), listFollowups(cycleId), listDecisions(cycleId)])
      return { cases, followups, decisions }
    },
    [cycleId],
  )
  const [panel, setPanel] = useState<Panel>(null)
  const [channel, setChannel] = useState<FollowupChannel>('call')
  const [decision, setDecision] = useState<DecisionKind>('continue')
  const [text, setText] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [done, setDone] = useState('')
  const d = data.data

  function open(kind: 'followup' | 'decision', row: CycleCase) {
    setPanel({ kind, row })
    setText('')
    setError('')
    setFailure(null)
    setUncertain(false)
    setDone('')
  }

  async function submit() {
    if (busy || !panel) return
    if (!text.trim()) {
      setError(panel.kind === 'followup' ? 'Escribe una nota del contacto.' : 'Escribe el motivo de la decisión.')
      return
    }
    setBusy(true)
    setError('')
    setFailure(null)
    setUncertain(false)
    try {
      if (panel.kind === 'followup') await registerFollowup(panel.row.student_id, cycleId, channel, text.trim())
      else await registerAcademicDecision(panel.row.student_id, cycleId, decision, text.trim())
      setDone(panel.kind === 'followup' ? 'Contacto registrado.' : 'Decisión registrada.')
      setPanel(null)
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') setUncertain(true)
      else setFailure(err)
    } finally {
      setBusy(false)
      data.reload() // el historial se relee siempre: muestra si la escritura sí llegó
    }
  }

  const debt = (d?.cases ?? []).filter((c) => c.case_type === 'debt')
  const absences = (d?.cases ?? []).filter((c) => c.case_type === 'attendance')
  const history = (studentId: string) => (d?.followups ?? []).filter((f) => f.student_id === studentId)
  const decisionsOf = (studentId: string) => (d?.decisions ?? []).filter((x) => x.student_id === studentId)

  return (
    <Page title="Casos" subtitle="Deuda vencida y faltas del ciclo, con el seguimiento de secretaría y la decisión de dirección.">
      {cycles.error && <ErrorBanner error={cycles.error} onRetry={cycles.reload} />}
      {cycles.data && cycles.data.length === 0 && <Empty>Aún no hay ciclos.</Empty>}
      {cycles.data && cycles.data.length > 0 && (
        <Field label="Ciclo">
          <select value={cycleId} onChange={(e) => setCycleId(e.target.value)}>
            {cycles.data.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </Field>
      )}

      {done && <Notice tone="ok">{done}</Notice>}
      {failure && <ErrorBanner error={failure} />}
      {uncertain && (
        <Notice tone="warn" title="No podemos confirmar el resultado">
          Perdimos la conexión. El historial se volvió a leer: revisa si el registro ya aparece antes de repetirlo.
        </Notice>
      )}
      {data.loading && !d && <Loading />}
      {data.error && <ErrorBanner error={data.error} onRetry={data.reload} />}

      {d && (
        <>
          <Card title="Deuda vencida">
            {debt.length === 0 ? (
              <Empty>No hay alumnos con deuda vencida en este ciclo.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr><th>Alumno</th><th>Vencida</th><th>Saldo total</th><th>Desde</th><th>Contactos</th><th /></tr>
                  </thead>
                  <tbody>
                    {debt.map((c) => (
                      <tr key={`d-${c.student_id}`}>
                        <td><strong>{c.full_name}</strong></td>
                        <td><strong>{money(c.balance ?? 0)}</strong></td>
                        <td>{money(c.total_balance ?? 0)}</td>
                        <td className="nowrap">{formatDate(c.due_date)}</td>
                        <td>{history(c.student_id).length}</td>
                        <td className="right">
                          <button type="button" className="btn btn-ghost" onClick={() => open('followup', c)}>Registrar contacto</button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <Notice tone="info">
              «Vencida» es el importe calculado por la base con la fecha excepcional incluida. Una deuda sale de esta lista cuando se paga.
            </Notice>
          </Card>

          <Card title="Faltas">
            {absences.length === 0 ? (
              <Empty>Ningún alumno alcanzó el aviso de faltas en este ciclo.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr><th>Alumno</th><th>Faltas</th><th>Aviso / límite</th><th>Estado</th><th>Decisión</th><th /></tr>
                  </thead>
                  <tbody>
                    {absences.map((c) => {
                      const last = decisionsOf(c.student_id)[0]
                      return (
                        <tr key={`a-${c.student_id}`}>
                          <td><strong>{c.full_name}</strong></td>
                          <td><strong>{c.absences}</strong></td>
                          <td>{c.warning_threshold} / {c.review_threshold}</td>
                          <td><Badge tone={STATUS_TONE[c.status]}>{STATUS_LABEL[c.status]}</Badge></td>
                          <td>{last ? `${DECISION_LABEL[last.decision]} · ${dateTime(last.created_at)}` : '—'}</td>
                          <td className="right">
                            <div className="actions">
                              {c.status !== 'resolved' && (
                                <button type="button" className="btn btn-ghost" onClick={() => open('followup', c)}>Registrar contacto</button>
                              )}
                              {isAdmin && (c.requires_decision || (c.absences ?? 0) >= (c.review_threshold ?? Infinity)) && (
                                <button type="button" className="btn btn-primary" onClick={() => open('decision', c)}>
                                  {c.requires_decision ? 'Decidir' : 'Agregar decisión'}
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}
            <Notice tone="info">La decisión no modifica las asistencias ni desaprueba al alumno. Dirección puede registrar varias para conservar el historial.</Notice>
          </Card>

          {panel && (
            <Card title={panel.kind === 'followup' ? `Contacto con ${panel.row.full_name}` : `Decisión para ${panel.row.full_name}`}>
              {panel.kind === 'followup' ? (
                <Field label="Canal">
                  <select value={channel} onChange={(e) => setChannel(e.target.value as FollowupChannel)} disabled={busy}>
                    {(Object.keys(CHANNEL_LABEL) as FollowupChannel[]).map((k) => (
                      <option key={k} value={k}>{CHANNEL_LABEL[k]}</option>
                    ))}
                  </select>
                </Field>
              ) : (
                <Field label="Decisión">
                  <select value={decision} onChange={(e) => setDecision(e.target.value as DecisionKind)} disabled={busy}>
                    {(Object.keys(DECISION_LABEL) as DecisionKind[]).map((k) => (
                      <option key={k} value={k}>{DECISION_LABEL[k]}</option>
                    ))}
                  </select>
                </Field>
              )}
              <Field label={panel.kind === 'followup' ? 'Nota' : 'Motivo'} error={error}>
                <textarea rows={3} value={text} onChange={(e) => setText(e.target.value)} disabled={busy} />
              </Field>
              <div className="actions">
                <button type="button" className="btn btn-ghost" onClick={() => setPanel(null)} disabled={busy}>Cancelar</button>
                <button type="button" className="btn btn-primary" onClick={submit} disabled={busy}>
                  {busy ? 'Guardando…' : 'Guardar'}
                </button>
              </div>
            </Card>
          )}

          <Card title="Historial de contactos">
            {d.followups.length === 0 ? (
              <Empty>Todavía no hay contactos registrados.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Fecha</th><th>Alumno</th><th>Canal</th><th>Nota</th></tr></thead>
                  <tbody>
                    {d.followups.map((f) => (
                      <tr key={f.id}>
                        <td className="nowrap">{dateTime(f.created_at)}</td>
                        <td>{f.student_name ?? d.cases.find((c) => c.student_id === f.student_id)?.full_name ?? '—'}</td>
                        <td>{CHANNEL_LABEL[f.channel]}</td>
                        <td>{f.note}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </>
      )}
    </Page>
  )
}
