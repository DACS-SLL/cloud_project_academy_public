import { useEffect, useRef, useState } from 'react'
import { Badge, Card, ErrorBanner, Field, Loading, Notice, Page, useAsync } from '../components/ui'
import {
  findPayment,
  listCharges,
  listEnrollments,
  listPayments,
  listStudents,
  registerPayment,
  uploadVoucher,
} from '../lib/api'
import type { RegisterPaymentInput } from '../lib/api'
import {
  CHARGE_LABEL,
  CHARGE_TYPE_LABEL,
  chargeView,
  effectiveDueDate,
  ENROLLMENT_LABEL,
  formatDate,
  money,
  todayLima,
  validatePayment,
  voucherPath,
} from '../lib/domain'
import type { FieldErrors } from '../lib/domain'
import { asAppError } from '../lib/errors'
import type { AppError } from '../lib/errors'
import { navigate, readQuery } from '../lib/router'
import { useSession } from '../lib/session'
import type { PaymentResult } from '../lib/types'
import { chargeTone, enrollmentTone } from './Students'

const ATTEMPT_KEY = 'f02.paymentAttempt'

/** UUID para `p_payment_id`: clave de idempotencia del intento (contrato B03 §2.2). */
function newId(): string {
  const c = globalThis.crypto as Crypto & { randomUUID?: () => string }
  if (typeof c.randomUUID === 'function') return c.randomUUID()
  const b = c.getRandomValues(new Uint8Array(16))
  b[6] = (b[6] & 0x0f) | 0x40
  b[8] = (b[8] & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

// El intento se guarda en la pestaña para poder consultarlo si se recarga tras perder la conexión.
function saveAttempt(a: RegisterPaymentInput | null) {
  try {
    if (a) sessionStorage.setItem(ATTEMPT_KEY, JSON.stringify(a))
    else sessionStorage.removeItem(ATTEMPT_KEY)
  } catch {
    /* el almacenamiento puede no estar disponible; el flujo sigue en memoria */
  }
}

function loadAttempt(): RegisterPaymentInput | null {
  try {
    const raw = sessionStorage.getItem(ATTEMPT_KEY)
    return raw ? (JSON.parse(raw) as RegisterPaymentInput) : null
  } catch {
    return null
  }
}

type Recovery =
  | { phase: 'none' }
  | { phase: 'checking' }
  | { phase: 'found'; result: PaymentResult }
  | { phase: 'missing' } // el servidor confirma que no tiene ese pago
  | { phase: 'unknown' } // la consulta tampoco respondió

/** C04 — Registrar pago con voucher (secretaría). Pago bancario, total o parcial. */
export default function RegisterPayment() {
  const { access } = useSession()
  const data = useAsync(async () => {
    const [students, enrollments, charges, payments] = await Promise.all([
      listStudents(),
      listEnrollments(),
      listCharges(),
      listPayments(),
    ])
    return { students, enrollments, charges, payments }
  }, [])

  const today = todayLima()
  const [studentId, setStudentId] = useState(readQuery().get('student') ?? '')
  const [chargeId, setChargeId] = useState('')
  const [amount, setAmount] = useState('')
  const [paidAt, setPaidAt] = useState(today)
  const [method, setMethod] = useState('bank_transfer')
  const [reference, setReference] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [verified, setVerified] = useState(false)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState<AppError | null>(null)
  const [result, setResult] = useState<PaymentResult | null>(null)
  const [recovery, setRecovery] = useState<Recovery>({ phase: 'none' })
  const [search, setSearch] = useState('')
  // El identificador vive durante todo el intento y se renueva solo tras un pago confirmado.
  const paymentId = useRef(newId())
  const pendingAttempt = useRef<RegisterPaymentInput | null>(loadAttempt())
  const [hasAttempt, setHasAttempt] = useState(pendingAttempt.current !== null)

  const d = data.data
  const student = d?.students.find((s) => s.id === studentId)
  const enrollment = d?.enrollments.find((e) => e.student_id === studentId && e.status !== 'cancelled')
  const views = (d?.charges ?? [])
    .filter((c) => enrollment && c.enrollment_id === enrollment.id)
    .map((c) => chargeView(c, d?.payments ?? [], today, effectiveDueDate(c, enrollment)))
  const open = views.filter((v) => v.balance > 0)
  const selected = views.find((v) => v.charge.id === chargeId)

  // Tras recargar con un intento sin confirmar, se consulta ese mismo p_payment_id apenas hay datos.
  const autoChecked = useRef(false)
  useEffect(() => {
    if (autoChecked.current || !d || !pendingAttempt.current) return
    autoChecked.current = true
    void verify(pendingAttempt.current.paymentId, pendingAttempt.current)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [d])

  useEffect(() => {
    setChargeId('')
    setAmount('')
  }, [studentId])

  /** Al corregir un campo se quita su error: no queda un aviso viejo junto a un dato ya corregido. */
  function clearError(key: string) {
    setErrors((prev) => {
      if (!(key in prev)) return prev
      const { [key]: _removed, ...rest } = prev
      return rest
    })
  }

  function pickCharge(id: string) {
    setChargeId(id)
    clearError('charge_id')
    clearError('amount')
    const v = views.find((x) => x.charge.id === id)
    setAmount(v ? String(v.balance) : '')
  }

  function afterSuccess(res: PaymentResult) {
    setResult(res)
    saveAttempt(null)
    pendingAttempt.current = null
    setHasAttempt(false)
    setRecovery({ phase: 'none' })
    paymentId.current = newId()
    data.reload()
  }

  /** E23b–E23e: tras perder la respuesta se consulta el pago por su identificador. */
  async function verify(id: string, attempt: RegisterPaymentInput | null) {
    setRecovery({ phase: 'checking' })
    try {
      const p = await findPayment(id)
      if (p) {
        const en = d?.enrollments.find((e) => e.id === (attempt ?? pendingAttempt.current)?.enrollmentId) ?? enrollment
        if (en) setStudentId(en.student_id)
        // El servidor confirma que el pago existe: se muestra lo guardado (idempotente).
        afterSuccess({
          payment_id: p.id,
          status: p.status,
          amount: Number(p.amount),
          charge_balance: NaN,
          enrollment_status: en?.status ?? 'pending',
          idempotent: true,
        })
        saveAttempt(null)
        return
      }
      pendingAttempt.current = attempt ?? pendingAttempt.current
      setRecovery({ phase: 'missing' })
    } catch {
      setRecovery({ phase: 'unknown' })
    }
  }

  async function submit() {
    // Un intento guardado sin resolver bloquea cualquier envío nuevo: no se reemplaza su p_payment_id.
    if (busy || pendingAttempt.current || !access || !enrollment || !selected || recovery.phase !== 'none') return
    const found = validatePayment(
      {
        charge_id: chargeId,
        amount: Number(amount),
        balance: selected.balance,
        paid_at: paidAt,
        method,
        reference,
        file: file ? { size: file.size, type: file.type } : null,
        verified,
      },
      today,
    )
    setErrors(found)
    if (Object.keys(found).length > 0 || !file) return

    const attempt: RegisterPaymentInput = {
      paymentId: paymentId.current,
      enrollmentId: enrollment.id,
      chargeId,
      amount: Number(amount),
      paidAt,
      method,
      reference,
      voucherPath: voucherPath(access.academy_id, paymentId.current, file.name),
    }
    saveAttempt(attempt)
    pendingAttempt.current = attempt
    setHasAttempt(true)
    setBusy(true)
    setFailure(null)
    try {
      await uploadVoucher(attempt.voucherPath, file)
      afterSuccess(await registerPayment(attempt))
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') {
        setFailure(err)
        await verify(attempt.paymentId, attempt)
      } else {
        // Rechazo explícito: no quedó pago confirmado. Se relee el saldo del servidor.
        setFailure(err)
        saveAttempt(null)
        pendingAttempt.current = null
        setHasAttempt(false)
        data.reload()
      }
    } finally {
      setBusy(false)
    }
  }

  async function retrySame() {
    const attempt = pendingAttempt.current
    if (!attempt || busy) return
    setBusy(true)
    setFailure(null)
    try {
      // Mismo p_payment_id: si ya existe con los mismos datos responde igual (idempotent = true).
      afterSuccess(await registerPayment(attempt))
    } catch (e) {
      const err = asAppError(e)
      if (err.kind === 'uncertain') {
        setFailure(err)
        await verify(attempt.paymentId, attempt)
      } else {
        setFailure(err)
        setRecovery({ phase: 'none' })
        saveAttempt(null)
        pendingAttempt.current = null
        setHasAttempt(false)
        data.reload()
      }
    } finally {
      setBusy(false)
    }
  }

  function startOver() {
    saveAttempt(null)
    pendingAttempt.current = null
    setHasAttempt(false)
    paymentId.current = newId()
    setRecovery({ phase: 'none' })
    setResult(null)
    setFailure(null)
    setChargeId('')
    setAmount('')
    setReference('')
    setFile(null)
    setVerified(false)
    setErrors({})
  }

  if (data.loading && !d) return <Page title="Registrar pago"><Loading /></Page>
  if (data.error && !d) return <Page title="Registrar pago"><ErrorBanner error={data.error} onRetry={data.reload} /></Page>

  // Pago anterior sin confirmar (por ejemplo, tras recargar la página).
  const recoveryBox = (
    <>
      {hasAttempt && recovery.phase === 'none' && !result && !busy && (
        <Notice
          tone="warn"
          title="Hay un pago sin confirmar"
          action={
            <button
              type="button"
              className="btn btn-ghost"
              onClick={() => pendingAttempt.current && verify(pendingAttempt.current.paymentId, pendingAttempt.current)}
            >
              Consultar estado
            </button>
          }
        >
          Un envío anterior no llegó a confirmarse
          {pendingAttempt.current && ` (${money(pendingAttempt.current.amount)}, referencia ${pendingAttempt.current.reference})`}. No
          puedes registrar otro pago hasta resolverlo.
        </Notice>
      )}
      {recovery.phase === 'checking' && <Notice tone="info" title="Verificando pago…">Consultando al servidor. No registres otro pago todavía.</Notice>}
      {recovery.phase === 'missing' && (
        <Notice
          tone="warn"
          title="El servidor aún no muestra este pago"
          action={
            <button type="button" className="btn btn-primary" onClick={retrySame} disabled={busy}>
              Reintentar con el mismo identificador
            </button>
          }
        >
          Que la consulta no lo encuentre no prueba que no se guardó: puede estar en proceso. Reintenta con el mismo identificador;
          si ya existe no se duplica. No se genera otro identificador hasta que el servidor responda con un resultado definitivo.
        </Notice>
      )}
      {recovery.phase === 'unknown' && (
        <Notice
          tone="warn"
          title="Todavía no podemos confirmar el resultado"
          action={
            <button
              type="button"
              className="btn btn-ghost"
              onClick={() => pendingAttempt.current && verify(pendingAttempt.current.paymentId, pendingAttempt.current)}
            >
              Consultar de nuevo
            </button>
          }
        >
          No reintentes ni cierres el formulario hasta saberlo.
        </Notice>
      )}
    </>
  )

  if (result) {
    const known = Number.isFinite(result.charge_balance)
    return (
      <Page title="Registrar pago">
        <Notice tone="ok" title={result.idempotent ? 'Este pago ya quedó registrado' : 'Pago confirmado'}>
          {money(result.amount)} aplicados.
          {known && ` Saldo del cargo: ${money(result.charge_balance)}.`}
          {result.enrollment_status === 'active' && ' La matrícula está activa y ocupa cupo.'}
          {result.enrollment_status === 'exception' && ' La matrícula sigue como excepcional.'}
        </Notice>
        <div className="actions">
          <button type="button" className="btn btn-primary" onClick={() => navigate(`/alumnos/${studentId}`)}>
            Ver ficha
          </button>
          <button type="button" className="btn btn-ghost" onClick={startOver}>
            Registrar otro pago
          </button>
        </div>
      </Page>
    )
  }

  const candidates = (d?.students ?? []).filter((s) => {
    const en = d?.enrollments.some((e) => e.student_id === s.id && e.status !== 'cancelled')
    const q = search.trim().toLowerCase()
    return en && (!q || s.full_name.toLowerCase().includes(q) || (s.document_id ?? '').includes(q))
  })
  const blocked = recovery.phase !== 'none' || hasAttempt

  return (
    <Page title="Registrar pago" subtitle="Solo pagos bancarios. Cada pago exige su voucher y su verificación en el medio externo.">
      {recoveryBox}
      <Card title="1. Alumno y cargo">
        <div className="form-grid">
          <Field label="Buscar alumno">
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Nombre o DNI" />
          </Field>
          <Field label="Alumno">
            <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
              <option value="">Elige un alumno</option>
              {candidates.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.full_name} · {s.document_id ?? 'sin DNI'}
                </option>
              ))}
            </select>
          </Field>
        </div>
        {student && enrollment && (
          <p>
            <Badge tone={enrollmentTone[enrollment.status]}>{ENROLLMENT_LABEL[enrollment.status]}</Badge>
          </p>
        )}
        {student && !enrollment && <Notice tone="warn">Este alumno no tiene una matrícula registrada.</Notice>}
        {enrollment && views.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th /><th>Cargo</th><th>Vence</th><th>Saldo</th><th>Estado</th></tr>
              </thead>
              <tbody>
                {views.map((v) => (
                  <tr key={v.charge.id}>
                    <td>
                      <input
                        type="radio"
                        name="charge"
                        aria-label={`Elegir ${CHARGE_TYPE_LABEL[v.charge.type]} del ${formatDate(v.dueDate)}`}
                        checked={chargeId === v.charge.id}
                        disabled={v.balance === 0 || blocked}
                        onChange={() => pickCharge(v.charge.id)}
                      />
                    </td>
                    <td>{CHARGE_TYPE_LABEL[v.charge.type]}</td>
                    <td>
                      {formatDate(v.dueDate)}
                      {v.dueDate !== v.charge.due_date && <span className="muted"> · excepción</span>}
                    </td>
                    <td><strong>{money(v.balance)}</strong></td>
                    <td><Badge tone={chargeTone[v.state]}>{CHARGE_LABEL[v.state]}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {enrollment && open.length === 0 && views.length > 0 && <Notice tone="ok">Todos los cargos de este alumno están pagados.</Notice>}
        {errors.charge_id && <Notice tone="error">{errors.charge_id}</Notice>}
      </Card>

      {selected && (
        <Card title="2. Datos del pago">
          <div className="form-grid">
            <Field label="Monto (S/)" error={errors.amount} hint={`Saldo pendiente: ${money(selected.balance)}`}>
              <input type="number" min={0} step="0.01" value={amount} onChange={(e) => {
                  setAmount(e.target.value)
                  clearError('amount')
                }} disabled={blocked} />
            </Field>
            <Field label="Fecha del pago" error={errors.paid_at}>
              <input type="date" max={today} value={paidAt} onChange={(e) => {
                  setPaidAt(e.target.value)
                  clearError('paid_at')
                }} disabled={blocked} />
            </Field>
            <Field label="Medio" error={errors.method} hint="No se registra efectivo">
              <select value={method} onChange={(e) => {
                  setMethod(e.target.value)
                  clearError('method')
                }} disabled={blocked}>
                <option value="bank_transfer">Transferencia bancaria</option>
                <option value="bank_deposit">Depósito bancario</option>
              </select>
            </Field>
            <Field label="Referencia bancaria" error={errors.reference}>
              <input value={reference} onChange={(e) => {
                  setReference(e.target.value)
                  clearError('reference')
                }} disabled={blocked} />
            </Field>
            <Field label="Voucher (PNG, JPG, WEBP o PDF, máx. 5 MB)" error={errors.file}>
              <input
                type="file"
                accept="image/png,image/jpeg,image/webp,application/pdf"
                onChange={(e) => {
                  setFile(e.target.files?.[0] ?? null)
                  clearError('file')
                }}
                disabled={blocked}
              />
            </Field>
            <div className="wide">
              <label className="check">
                <input type="checkbox" checked={verified} onChange={(e) => {
                    setVerified(e.target.checked)
                    clearError('verified')
                  }} disabled={blocked} />
                <span>Verifiqué el pago en el medio externo</span>
              </label>
              {errors.verified && <span className="field-error" role="alert">{errors.verified}</span>}
            </div>
          </div>

          {failure && failure.kind !== 'uncertain' && <ErrorBanner error={failure} />}
          {failure?.hint === 'PAYMENT_OVERPAY' && selected && (
            <Notice tone="info">Saldo actual del cargo según el servidor: {money(selected.balance)}.</Notice>
          )}
          {failure?.kind === 'uncertain' && <Notice tone="warn">{failure.message}</Notice>}

          <div className="actions">
            <button type="button" className="btn btn-primary" onClick={submit} disabled={busy || blocked}>
              {busy ? 'Confirmando…' : 'Confirmar pago'}
            </button>
          </div>
        </Card>
      )}
    </Page>
  )
}
