import { useEffect, useRef, useState } from 'react'
import { Badge, Card, ErrorBanner, Field, Loading, Notice, Page, SeatBar, useAsync } from '../components/ui'
import {
  createEnrollmentRequest,
  createGuardian,
  createStudent,
  findEnrollment,
  findStudentByDni,
  groupCapacity,
  listCycles,
  listGroups,
  listGuardians,
} from '../lib/api'
import { addMonths, formatDate, money, SHIFT_LABEL, validateEnrollment } from '../lib/domain'
import type { EnrollmentDraft, FieldErrors } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate } from '../lib/router'
import { useSession } from '../lib/session'
import type { Capacity, Student } from '../lib/types'

const blankPerson = { full_name: '', document_id: '', phone: '' }

interface Form {
  student: { full_name: string; document_id: string; school: string; grade: string }
  guardian1: typeof blankPerson
  guardian2: typeof blankPerson
  cycle_id: string
  group_id: string
  registration_price: string
  monthly_price: string
  registration_due_date: string
  monthly_due_dates: string[]
}

const EMPTY: Form = {
  student: { full_name: '', document_id: '', school: '', grade: '' },
  guardian1: blankPerson,
  guardian2: blankPerson,
  cycle_id: '',
  group_id: '',
  registration_price: '',
  monthly_price: '',
  registration_due_date: '',
  monthly_due_dates: ['', '', ''],
}

const STEP_KEYS: Record<number, (k: string) => boolean> = {
  1: (k) => k.startsWith('student.') || k.startsWith('guardian'),
  2: (k) => k === 'group_id' || k.endsWith('_price'),
  3: (k) => k.startsWith('monthly') || k === 'registration_due_date',
}

/** C02 — Nueva matrícula (secretaría). Crea una solicitud pendiente; no ocupa cupo. */
export default function NewEnrollment() {
  const { access } = useSession()
  const base = useAsync(async () => ({ cycles: await listCycles(), groups: await listGroups() }), [])
  const [step, setStep] = useState(1)
  const [form, setForm] = useState<Form>(EMPTY)
  const [existing, setExisting] = useState<Student | null>(null)
  const [lookup, setLookup] = useState('')
  const [errors, setErrors] = useState<FieldErrors>({})
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [checkResult, setCheckResult] = useState('')
  const [cap, setCap] = useState<Capacity | null>(null)
  const [done, setDone] = useState<{ studentId: string; name: string } | null>(null)
  // Lo ya creado se conserva entre intentos para no duplicar alumno ni apoderados.
  const progress = useRef<{ studentId?: string }>({})

  const cycle = base.data?.cycles.find((c) => c.id === form.cycle_id)
  const groups = (base.data?.groups ?? []).filter((g) => g.cycle_id === form.cycle_id)
  const group = groups.find((g) => g.id === form.group_id)

  // Fechas por defecto al elegir el ciclo: inscripción al inicio y una mensualidad por mes.
  useEffect(() => {
    if (!cycle) return
    setForm((f) =>
      f.registration_due_date
        ? f
        : {
            ...f,
            registration_due_date: cycle.start_date,
            monthly_due_dates: [0, 1, 2].map((i) => addMonths(cycle.start_date, i + 1)),
          },
    )
  }, [cycle])

  // Cupo del grupo elegido, leído del servidor.
  useEffect(() => {
    setCap(null)
    if (!form.group_id) return
    let alive = true
    groupCapacity(form.group_id).then(
      (c) => alive && setCap(c),
      () => alive && setCap(null),
    )
    return () => {
      alive = false
    }
  }, [form.group_id])

  const setStudent = (k: keyof Form['student'], v: string) =>
    setForm((f) => ({ ...f, student: { ...f.student, [k]: v } }))
  const setPerson = (who: 'guardian1' | 'guardian2', k: keyof typeof blankPerson, v: string) =>
    setForm((f) => ({ ...f, [who]: { ...f[who], [k]: v } }))

  function draft(): EnrollmentDraft {
    return {
      student: form.student,
      guardian1: form.guardian1,
      guardian2: form.guardian2,
      group_id: form.group_id,
      registration_price: Number(form.registration_price),
      monthly_price: Number(form.monthly_price),
      registration_due_date: form.registration_due_date,
      monthly_due_dates: form.monthly_due_dates,
      existingStudentId: existing?.id ?? null,
    }
  }

  function check(forStep: number): boolean {
    const all = validateEnrollment(draft(), cycle?.start_date, cycle?.end_date)
    const mine = Object.fromEntries(Object.entries(all).filter(([k]) => STEP_KEYS[forStep](k)))
    setErrors(mine)
    return Object.keys(mine).length === 0
  }

  async function searchByDni() {
    setLookup('')
    const dni = form.student.document_id.trim()
    if (!/^\d{8}$/.test(dni)) {
      setErrors({ 'student.document_id': 'El DNI debe tener 8 dígitos.' })
      return
    }
    try {
      const found = await findStudentByDni(dni)
      if (found) {
        setExisting(found)
        setLookup(`Alumno existente: ${found.full_name}. Se usará su ficha; no se crea uno nuevo.`)
      } else {
        setExisting(null)
        setLookup('No hay un alumno con ese DNI. Completa los datos para crearlo.')
      }
    } catch (e) {
      setFailure(asAppError(e))
    }
  }

  async function verify() {
    // Consulta real al servidor: ¿quedó registrada la solicitud?
    setCheckResult('')
    try {
      const s = existing ?? (await findStudentByDni(form.student.document_id))
      const en = s && cycle ? await findEnrollment(s.id, cycle.id) : null
      if (s && en) {
        setUncertain(false)
        setDone({ studentId: s.id, name: s.full_name })
      } else {
        setCheckResult(
          'El servidor no tiene registrada esta solicitud. Tus datos siguen en el formulario; puedes confirmar de nuevo.',
        )
        setUncertain(false)
      }
    } catch {
      setCheckResult('Todavía no podemos confirmar el resultado. Pulsa «Actualizar» otra vez; no repitas la operación.')
    }
  }

  async function submit() {
    if (busy || !access || !cycle) return
    const all = validateEnrollment(draft(), cycle.start_date, cycle.end_date)
    setErrors(all)
    if (Object.keys(all).length > 0) {
      setStep(Object.keys(all).some(STEP_KEYS[1]) ? 1 : Object.keys(all).some(STEP_KEYS[2]) ? 2 : 3)
      return
    }
    setBusy(true)
    setFailure(null)
    setUncertain(false)
    setCheckResult('')
    try {
      let studentId = progress.current.studentId ?? existing?.id
      let studentName = existing?.full_name ?? form.student.full_name
      if (!studentId) {
        // Si el alumno ya se creó en un intento anterior (p. ej. se cortó la conexión), se reutiliza.
        const dup = await findStudentByDni(form.student.document_id)
        if (dup && dup.full_name.trim().toLowerCase() !== form.student.full_name.trim().toLowerCase()) {
          setErrors({ 'student.document_id': `Ya existe un alumno con ese DNI (${dup.full_name}). Usa «Buscar por DNI».` })
          setStep(1)
          return
        }
        const created =
          dup ??
          (await createStudent(access.academy_id, {
            full_name: form.student.full_name,
            document_id: form.student.document_id,
            school: form.student.school,
            grade: form.student.grade,
          }))
        studentId = created.id
        studentName = created.full_name
        progress.current.studentId = created.id
      }
      if (!existing) {
        const have = await listGuardians(studentId)
        for (const g of [form.guardian1, form.guardian2]) {
          if (!g.full_name.trim()) continue
          if (have.some((h) => h.document_id === g.document_id.trim())) continue
          await createGuardian(access.academy_id, studentId, {
            full_name: g.full_name,
            document_id: g.document_id,
            phone: g.phone,
          })
        }
      }
      await createEnrollmentRequest({
        studentId,
        groupId: form.group_id,
        registrationPrice: Number(form.registration_price),
        monthlyPrice: Number(form.monthly_price),
        registrationDueDate: form.registration_due_date,
        monthlyDueDates: form.monthly_due_dates,
      })
      setDone({ studentId, name: studentName })
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') setUncertain(true)
      else {
        setFailure(err)
        // Tras un rechazo se vuelve a leer el cupo del servidor.
        if (form.group_id) groupCapacity(form.group_id).then(setCap, () => undefined)
      }
    } finally {
      setBusy(false)
    }
  }

  function reset() {
    progress.current = {}
    setForm(EMPTY)
    setExisting(null)
    setLookup('')
    setErrors({})
    setFailure(null)
    setUncertain(false)
    setCheckResult('')
    setDone(null)
    setStep(1)
  }

  if (base.loading) return <Page title="Nueva matrícula"><Loading /></Page>
  if (base.error) return <Page title="Nueva matrícula"><ErrorBanner error={base.error} onRetry={base.reload} /></Page>
  if ((base.data?.cycles.length ?? 0) === 0 || (base.data?.groups.length ?? 0) === 0)
    return (
      <Page title="Nueva matrícula">
        <Notice tone="warn">Dirección todavía no creó ciclos y grupos. Sin ellos no se puede registrar una matrícula.</Notice>
      </Page>
    )

  if (done)
    return (
      <Page title="Nueva matrícula">
        <Notice tone="ok" title="Solicitud registrada">
          La matrícula de <strong>{done.name}</strong> quedó <strong>pendiente de pago</strong>. No ocupa cupo hasta que se
          confirme la inscripción.
        </Notice>
        <div className="actions">
          <button type="button" className="btn btn-primary" onClick={() => navigate(`/alumnos/${done.studentId}`)}>
            Ver ficha y cargos
          </button>
          <button type="button" className="btn btn-ghost" onClick={reset}>
            Registrar otra matrícula
          </button>
        </div>
      </Page>
    )

  const total =
    (Number(form.registration_price) || 0) + (Number(form.monthly_price) || 0) * form.monthly_due_dates.length

  return (
    <Page title="Nueva matrícula" subtitle={`Paso ${step} de 3 · crea una solicitud pendiente de pago`}>
      <ol className="steps" aria-label="Pasos">
        {['Alumno y apoderado', 'Grupo y precios', 'Cargos y confirmación'].map((t, i) => (
          <li key={t} className={step === i + 1 ? 'is-current' : step > i + 1 ? 'is-done' : ''}>
            {i + 1}. {t}
          </li>
        ))}
      </ol>

      {step === 1 && (
        <Card title="Alumno y apoderado">
          <div className="form-grid">
            <Field label="DNI del alumno (ficticio)" error={errors['student.document_id']}>
              <div className="inline-form">
                <input
                  inputMode="numeric"
                  maxLength={8}
                  value={form.student.document_id}
                  onChange={(e) => {
                    setStudent('document_id', e.target.value)
                    setExisting(null)
                    setLookup('')
                  }}
                />
                <button type="button" className="btn btn-ghost" onClick={searchByDni}>
                  Buscar por DNI
                </button>
              </div>
            </Field>
            {lookup && (
              <div className="wide">
                <Notice tone={existing ? 'info' : 'ok'}>{lookup}</Notice>
              </div>
            )}
            {!existing && (
              <>
                <Field label="Nombre completo" error={errors['student.full_name']}>
                  <input value={form.student.full_name} onChange={(e) => setStudent('full_name', e.target.value)} />
                </Field>
                <Field label="Colegio de procedencia" error={errors['student.school']}>
                  <input value={form.student.school} onChange={(e) => setStudent('school', e.target.value)} />
                </Field>
                <Field label="Grado" error={errors['student.grade']}>
                  <input value={form.student.grade} onChange={(e) => setStudent('grade', e.target.value)} />
                </Field>
                <h3 className="wide">Apoderado principal</h3>
                <Field label="Nombre completo" error={errors['guardian1.full_name']}>
                  <input value={form.guardian1.full_name} onChange={(e) => setPerson('guardian1', 'full_name', e.target.value)} />
                </Field>
                <Field label="DNI (ficticio)" error={errors['guardian1.document_id']}>
                  <input inputMode="numeric" maxLength={8} value={form.guardian1.document_id} onChange={(e) => setPerson('guardian1', 'document_id', e.target.value)} />
                </Field>
                <Field label="Teléfono (ficticio, 9 dígitos)" error={errors['guardian1.phone']}>
                  <input inputMode="numeric" maxLength={9} value={form.guardian1.phone} onChange={(e) => setPerson('guardian1', 'phone', e.target.value)} />
                </Field>
                <h3 className="wide">Segundo apoderado (opcional)</h3>
                <Field label="Nombre completo" error={errors['guardian2.full_name']}>
                  <input value={form.guardian2.full_name} onChange={(e) => setPerson('guardian2', 'full_name', e.target.value)} />
                </Field>
                <Field label="DNI (ficticio)" error={errors['guardian2.document_id']}>
                  <input inputMode="numeric" maxLength={8} value={form.guardian2.document_id} onChange={(e) => setPerson('guardian2', 'document_id', e.target.value)} />
                </Field>
                <Field label="Teléfono (ficticio)" error={errors['guardian2.phone']}>
                  <input inputMode="numeric" maxLength={9} value={form.guardian2.phone} onChange={(e) => setPerson('guardian2', 'phone', e.target.value)} />
                </Field>
              </>
            )}
          </div>
          <div className="actions">
            <button type="button" className="btn btn-primary" onClick={() => check(1) && setStep(2)}>
              Siguiente
            </button>
          </div>
        </Card>
      )}

      {step === 2 && (
        <Card title="Grupo y precios">
          <div className="form-grid">
            <Field label="Ciclo">
              <select
                value={form.cycle_id}
                onChange={(e) =>
                  setForm({ ...form, cycle_id: e.target.value, group_id: '', registration_due_date: '', monthly_due_dates: ['', '', ''] })
                }
              >
                <option value="">Elige un ciclo</option>
                {base.data!.cycles.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({formatDate(c.start_date)} – {formatDate(c.end_date)})
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Grupo" error={errors.group_id}>
              <select value={form.group_id} onChange={(e) => setForm({ ...form, group_id: e.target.value })} disabled={!form.cycle_id}>
                <option value="">Elige un grupo</option>
                {groups.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.name} · {SHIFT_LABEL[g.shift]}
                  </option>
                ))}
              </select>
            </Field>
            {group && (
              <div className="wide">
                {cap ? <SeatBar capacity={cap.capacity} occupied={cap.occupied} /> : <span className="muted">Leyendo el cupo…</span>}
                {cap && cap.available <= 0 && (
                  <Notice tone="warn">
                    El grupo está lleno. La solicitud se puede registrar como pendiente porque no ocupa cupo, pero no podrá
                    activarse hasta que haya vacante.
                  </Notice>
                )}
              </div>
            )}
            <Field label="Precio de inscripción (S/)" error={errors.registration_price} hint="Fijo para este ciclo">
              <input type="number" min={0} step="0.01" value={form.registration_price} onChange={(e) => setForm({ ...form, registration_price: e.target.value })} />
            </Field>
            <Field label="Precio de cada mensualidad (S/)" error={errors.monthly_price} hint="Fijo para este ciclo">
              <input type="number" min={0} step="0.01" value={form.monthly_price} onChange={(e) => setForm({ ...form, monthly_price: e.target.value })} />
            </Field>
          </div>
          <div className="actions">
            <button type="button" className="btn btn-ghost" onClick={() => setStep(1)}>Atrás</button>
            <button type="button" className="btn btn-primary" onClick={() => check(2) && setStep(3)}>Siguiente</button>
          </div>
        </Card>
      )}

      {step === 3 && (
        <Card title="Cargos y confirmación">
          <div className="form-grid">
            <Field label="Vence la inscripción" error={errors.registration_due_date}>
              <input type="date" value={form.registration_due_date} onChange={(e) => setForm({ ...form, registration_due_date: e.target.value })} />
            </Field>
            <div />
            {form.monthly_due_dates.map((d, i) => (
              <Field key={i} label={`Vence la mensualidad ${i + 1}`} error={errors[`monthly.${i}`]}>
                <div className="inline-form">
                  <input
                    type="date"
                    value={d}
                    onChange={(e) => setForm({ ...form, monthly_due_dates: form.monthly_due_dates.map((x, j) => (j === i ? e.target.value : x)) })}
                  />
                  {form.monthly_due_dates.length > 1 && (
                    <button type="button" className="btn btn-ghost" onClick={() => setForm({ ...form, monthly_due_dates: form.monthly_due_dates.filter((_, j) => j !== i) })}>
                      Quitar
                    </button>
                  )}
                </div>
              </Field>
            ))}
          </div>
          {errors.monthly_due_dates && <Notice tone="error">{errors.monthly_due_dates}</Notice>}
          <button type="button" className="btn btn-ghost" onClick={() => setForm({ ...form, monthly_due_dates: [...form.monthly_due_dates, ''] })}>
            Agregar mensualidad
          </button>

          <div className="summary">
            <h3>Resumen</h3>
            <p>
              <strong>{existing?.full_name ?? form.student.full_name}</strong> · {group?.name} ({cycle?.name})
            </p>
            <ul className="list">
              <li><span>Inscripción</span><span>{money(Number(form.registration_price) || 0)}</span></li>
              <li><span>{form.monthly_due_dates.length} mensualidades de {money(Number(form.monthly_price) || 0)}</span><span>{money((Number(form.monthly_price) || 0) * form.monthly_due_dates.length)}</span></li>
              <li><strong>Total del ciclo</strong><strong>{money(total)}</strong></li>
            </ul>
            <Badge tone="neutral">Pendiente de pago · no ocupa cupo</Badge>
          </div>

          {failure && <ErrorBanner error={failure} />}
          {uncertain && (
            <Notice
              tone="warn"
              title="No podemos confirmar el resultado"
              action={<button type="button" className="btn btn-ghost" onClick={verify}>Actualizar</button>}
            >
              Perdimos la conexión. Pulsa «Actualizar» para consultar al servidor si la solicitud quedó registrada; no
              repitas la operación todavía.
            </Notice>
          )}
          {checkResult && <Notice tone="warn">{checkResult}</Notice>}

          <div className="actions">
            <button type="button" className="btn btn-ghost" onClick={() => setStep(2)} disabled={busy}>Atrás</button>
            <button type="button" className="btn btn-primary" onClick={submit} disabled={busy || uncertain}>
              {busy ? 'Registrando…' : 'Registrar solicitud'}
            </button>
          </div>
        </Card>
      )}
    </Page>
  )
}
