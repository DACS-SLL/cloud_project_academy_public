import { useState } from 'react'
import type { FormEvent } from 'react'
import { Badge, Card, Empty, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import { listCycles, saveCycle } from '../lib/api'
import { formatDate, validateCycle } from '../lib/domain'
import type { FieldErrors } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { useSession } from '../lib/session'
import type { Cycle } from '../lib/types'

interface Draft {
  name: string
  grade: string
  start_date: string
  end_date: string
  warning_absences: string
  review_absences: string
  late_counts_as_absence: boolean
}

const EMPTY: Draft = {
  name: '',
  grade: '',
  start_date: '',
  end_date: '',
  warning_absences: '10',
  review_absences: '15',
  late_counts_as_absence: true,
}

const toDraft = (c: Cycle): Draft => ({
  name: c.name,
  grade: c.grade,
  start_date: c.start_date,
  end_date: c.end_date,
  warning_absences: String(c.warning_absences),
  review_absences: String(c.review_absences),
  late_counts_as_absence: c.late_counts_as_absence,
})

/** D02 — Ciclos y reglas (dirección). */
export default function Cycles() {
  const { access } = useSession()
  const cycles = useAsync(listCycles, [])
  const [editing, setEditing] = useState<string | 'new' | null>(null)
  const [draft, setDraft] = useState<Draft>(EMPTY)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [saved, setSaved] = useState('')

  function open(c?: Cycle) {
    setEditing(c ? c.id : 'new')
    setDraft(c ? toDraft(c) : EMPTY)
    setErrors({})
    setFailure(null)
    setSaved('')
  }

  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setDraft((d) => ({ ...d, [k]: v }))

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (busy || !access) return
    const warning = Number(draft.warning_absences)
    const review = Number(draft.review_absences)
    const found = validateCycle({ ...draft, warning_absences: warning, review_absences: review })
    setErrors(found)
    if (Object.keys(found).length > 0) return
    setBusy(true)
    setFailure(null)
    try {
      const row = await saveCycle(
        access.academy_id,
        {
          name: draft.name.trim(),
          grade: draft.grade.trim(),
          start_date: draft.start_date,
          end_date: draft.end_date,
          warning_absences: warning,
          review_absences: review,
          late_counts_as_absence: draft.late_counts_as_absence,
        },
        editing && editing !== 'new' ? editing : undefined,
      )
      setSaved(`Ciclo «${row.name}» guardado.`)
      setEditing(null)
      cycles.reload()
    } catch (err) {
      setFailure(asAppError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Page
      title="Ciclos y reglas"
      subtitle="Define cuándo empieza el ciclo y cuántas faltas generan aviso y revisión."
      actions={
        editing === null && (
          <button type="button" className="btn btn-primary" onClick={() => open()}>
            Nuevo ciclo
          </button>
        )
      }
    >
      {saved && <Notice tone="ok">{saved}</Notice>}

      {editing !== null && (
        <Card title={editing === 'new' ? 'Nuevo ciclo' : 'Editar ciclo'}>
          <form onSubmit={submit} noValidate className="form-grid">
            <Field label="Nombre" error={errors.name}>
              <input value={draft.name} onChange={(e) => set('name', e.target.value)} placeholder="Ciclo 2026-II" />
            </Field>
            <Field label="Grado objetivo" error={errors.grade}>
              <input value={draft.grade} onChange={(e) => set('grade', e.target.value)} placeholder="5.º de secundaria" />
            </Field>
            <Field label="Inicio" error={errors.start_date}>
              <input type="date" value={draft.start_date} onChange={(e) => set('start_date', e.target.value)} />
            </Field>
            <Field label="Fin" error={errors.end_date}>
              <input type="date" value={draft.end_date} onChange={(e) => set('end_date', e.target.value)} />
            </Field>
            <Field label="Faltas para aviso" error={errors.warning_absences} hint="Demo: 10">
              <input
                type="number"
                min={1}
                value={draft.warning_absences}
                onChange={(e) => set('warning_absences', e.target.value)}
              />
            </Field>
            <Field label="Faltas para revisión" error={errors.review_absences} hint="Demo: 15; debe ser mayor que el aviso">
              <input
                type="number"
                min={2}
                value={draft.review_absences}
                onChange={(e) => set('review_absences', e.target.value)}
              />
            </Field>
            <label className="check wide">
              <input
                type="checkbox"
                checked={draft.late_counts_as_absence}
                onChange={(e) => set('late_counts_as_absence', e.target.checked)}
              />
              <span>La tardanza suma una falta</span>
            </label>
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
                {busy ? 'Guardando…' : 'Guardar ciclo'}
              </button>
            </div>
          </form>
        </Card>
      )}

      {cycles.loading && <Loading />}
      {cycles.error && <ErrorBanner error={cycles.error} onRetry={cycles.reload} />}
      {!cycles.loading && !cycles.error && (cycles.data?.length ?? 0) === 0 && (
        <Empty>Aún no hay ciclos. Crea el primero para poder abrir grupos.</Empty>
      )}
      {(cycles.data?.length ?? 0) > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Ciclo</th>
                <th>Grado</th>
                <th>Fechas</th>
                <th>Aviso / revisión</th>
                <th>Tardanza</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {cycles.data!.map((c) => (
                <tr key={c.id}>
                  <td>
                    <strong>{c.name}</strong>
                  </td>
                  <td>{c.grade}</td>
                  <td>
                    {formatDate(c.start_date)} – {formatDate(c.end_date)}
                  </td>
                  <td>
                    {c.warning_absences} / {c.review_absences} faltas
                  </td>
                  <td>
                    <Badge tone={c.late_counts_as_absence ? 'info' : 'neutral'}>
                      {c.late_counts_as_absence ? 'Suma falta' : 'No suma'}
                    </Badge>
                  </td>
                  <td className="right">
                    <button type="button" className="btn btn-ghost" onClick={() => open(c)}>
                      Editar
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Page>
  )
}
