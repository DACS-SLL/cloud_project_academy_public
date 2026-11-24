// Reglas de presentación sin red: saldos, estados de cargo y cupo, fechas, validaciones de formulario.
// Las reglas de negocio finales las aplica Supabase; esto solo evita enviar datos evidentemente inválidos
// y muestra lo que la base ya guardó.

import type { Charge, EnrollmentStatus, Payment } from './types'

export const MONEY = new Intl.NumberFormat('es-PE', {
  style: 'currency',
  currency: 'PEN',
  minimumFractionDigits: 2,
})

export function money(value: number): string {
  return MONEY.format(value)
}

/** Fecha de hoy en Lima como YYYY-MM-DD (el contrato fija la zona horaria). */
export function todayLima(now: Date = new Date()): string {
  return now.toLocaleDateString('en-CA', { timeZone: 'America/Lima' })
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}

/** Suma `months` meses a una fecha YYYY-MM-DD conservando el día (ajusta fin de mes). */
export function addMonths(iso: string, months: number): string {
  const [y, m, d] = iso.split('-').map(Number)
  const base = new Date(Date.UTC(y, m - 1 + months, 1))
  const last = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth() + 1, 0)).getUTCDate()
  const day = Math.min(d, last)
  const out = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), day))
  return out.toISOString().slice(0, 10)
}

// ---------- Cargos y saldo ----------

export type ChargeState = 'pending' | 'partial' | 'overdue' | 'paid'

export interface ChargeView {
  charge: Charge
  paid: number
  balance: number
  state: ChargeState
  /** Vencimiento efectivo: en la inscripción excepcional es `exception_due_date`. */
  dueDate: string
}

const round2 = (n: number) => Math.round(n * 100) / 100

/**
 * Saldo mostrado = monto − pagos confirmados no anulados.
 * Es una lectura de lo guardado; la cifra definitiva tras un pago la devuelve `register_payment`.
 */
/** Fecha de vencimiento que rige para un cargo (B05): la inscripción excepcional usa `exception_due_date`. */
export function effectiveDueDate(
  charge: Charge,
  enrollment?: { status: EnrollmentStatus; exception_due_date: string | null } | null,
): string {
  if (enrollment?.status === 'exception' && charge.type === 'registration' && enrollment.exception_due_date) {
    return enrollment.exception_due_date
  }
  return charge.due_date
}

export function chargeView(charge: Charge, payments: Payment[], today: string, dueDate: string = charge.due_date): ChargeView {
  const paid = round2(
    payments
      .filter((p) => p.charge_id === charge.id && p.status === 'confirmed')
      .reduce((sum, p) => sum + Number(p.amount), 0),
  )
  const amount = Number(charge.amount)
  const balance = round2(Math.max(amount - paid, 0))
  let state: ChargeState
  if (balance === 0) state = 'paid'
  else if (dueDate < today) state = 'overdue'
  else if (paid > 0) state = 'partial'
  else state = 'pending'
  return { charge, paid, balance, state, dueDate }
}

export const CHARGE_LABEL: Record<ChargeState, string> = {
  pending: 'Pendiente',
  partial: 'Parcial',
  overdue: 'Vencido',
  paid: 'Pagado',
}

export const CHARGE_TYPE_LABEL: Record<Charge['type'], string> = {
  registration: 'Inscripción',
  monthly: 'Mensualidad',
}

// ---------- Matrícula ----------

export const ENROLLMENT_LABEL: Record<EnrollmentStatus, string> = {
  pending: 'Pendiente de pago',
  active: 'Activa',
  exception: 'Excepcional',
  cancelled: 'Cancelada',
}

/** Solo matrícula activa o excepcional ocupa cupo (contrato §2). */
export function occupiesSeat(status: EnrollmentStatus): boolean {
  return status === 'active' || status === 'exception'
}

// ---------- Cupo ----------

export type SeatState = 'available' | 'almost' | 'full'

/** «Casi lleno» = quedan 1–2 cupos (propuesta de presentación de F00). */
export function seatState(capacity: number, occupied: number): SeatState {
  const available = capacity - occupied
  if (available <= 0) return 'full'
  if (available <= 2) return 'almost'
  return 'available'
}

export const SEAT_LABEL: Record<SeatState, string> = {
  available: 'Disponible',
  almost: 'Casi lleno',
  full: 'Lleno',
}

export const SHIFT_LABEL = {
  morning: 'Mañana',
  afternoon: 'Tarde',
  night: 'Noche',
} as const

// ---------- Validaciones de formulario ----------

export const isDni = (v: string) => /^\d{8}$/.test(v.trim())
export const isPhone = (v: string) => /^\d{9}$/.test(v.trim())
export const isIsoDate = (v: string) => /^\d{4}-\d{2}-\d{2}$/.test(v)

export type FieldErrors = Record<string, string>

export interface CycleDraft {
  name: string
  start_date: string
  end_date: string
  grade: string
  warning_absences: number
  review_absences: number
}

export function validateCycle(d: CycleDraft): FieldErrors {
  const e: FieldErrors = {}
  if (!d.name.trim()) e.name = 'Escribe el nombre del ciclo.'
  if (!d.grade.trim()) e.grade = 'Indica el grado objetivo.'
  if (!isIsoDate(d.start_date)) e.start_date = 'Indica la fecha de inicio.'
  if (!isIsoDate(d.end_date)) e.end_date = 'Indica la fecha de fin.'
  if (isIsoDate(d.start_date) && isIsoDate(d.end_date) && d.end_date <= d.start_date)
    e.end_date = 'El fin debe ser posterior al inicio.'
  if (!(d.warning_absences > 0)) e.warning_absences = 'Debe ser mayor que 0.'
  if (!(d.review_absences > d.warning_absences))
    e.review_absences = 'El límite de revisión debe ser mayor que el aviso.'
  return e
}

export interface GroupDraft {
  name: string
  cycle_id: string
  capacity: number
}

export function validateGroup(d: GroupDraft): FieldErrors {
  const e: FieldErrors = {}
  if (!d.name.trim()) e.name = 'Escribe el identificador del grupo.'
  if (!d.cycle_id) e.cycle_id = 'Elige el ciclo.'
  if (!Number.isInteger(d.capacity) || d.capacity <= 0) e.capacity = 'La capacidad debe ser un entero mayor que 0.'
  return e
}

export interface PersonDraft {
  full_name: string
  document_id: string
  phone?: string
}

export interface EnrollmentDraft {
  student: { full_name: string; document_id: string; school: string; grade: string }
  guardian1: PersonDraft
  guardian2: PersonDraft
  group_id: string
  registration_price: number
  monthly_price: number
  registration_due_date: string
  monthly_due_dates: string[]
  existingStudentId: string | null
}

const blank = (p: PersonDraft) => !p.full_name.trim() && !p.document_id.trim() && !(p.phone ?? '').trim()

export function validateEnrollment(d: EnrollmentDraft, cycleStart?: string, cycleEnd?: string): FieldErrors {
  const e: FieldErrors = {}
  if (!d.existingStudentId) {
    if (!d.student.full_name.trim()) e['student.full_name'] = 'Escribe el nombre del alumno.'
    if (!isDni(d.student.document_id)) e['student.document_id'] = 'El DNI debe tener 8 dígitos.'
    if (!d.student.school.trim()) e['student.school'] = 'Escribe el colegio de procedencia.'
    if (!d.student.grade.trim()) e['student.grade'] = 'Escribe el grado.'
    if (!d.guardian1.full_name.trim()) e['guardian1.full_name'] = 'Escribe el nombre del apoderado.'
    if (!isDni(d.guardian1.document_id)) e['guardian1.document_id'] = 'El DNI debe tener 8 dígitos.'
    if (!isPhone(d.guardian1.phone ?? '')) e['guardian1.phone'] = 'El teléfono debe tener 9 dígitos.'
    if (!blank(d.guardian2)) {
      if (!d.guardian2.full_name.trim()) e['guardian2.full_name'] = 'Completa el nombre o borra el segundo apoderado.'
      if (!isDni(d.guardian2.document_id)) e['guardian2.document_id'] = 'El DNI debe tener 8 dígitos.'
      if (!isPhone(d.guardian2.phone ?? '')) e['guardian2.phone'] = 'El teléfono debe tener 9 dígitos.'
    }
  }
  if (!d.group_id) e.group_id = 'Elige el grupo.'
  if (!(d.registration_price > 0)) e.registration_price = 'La inscripción debe ser mayor que S/ 0.'
  if (!(d.monthly_price > 0)) e.monthly_price = 'La mensualidad debe ser mayor que S/ 0.'
  if (!isIsoDate(d.registration_due_date)) e.registration_due_date = 'Indica el vencimiento de la inscripción.'
  if (d.monthly_due_dates.length === 0) e.monthly_due_dates = 'Agrega al menos una mensualidad.'
  d.monthly_due_dates.forEach((date, i) => {
    if (!isIsoDate(date)) e[`monthly.${i}`] = 'Indica el vencimiento.'
    else if (cycleStart && cycleEnd && (date < cycleStart || date > cycleEnd))
      e[`monthly.${i}`] = 'Debe caer dentro del ciclo.'
  })
  const dup = new Set(d.monthly_due_dates)
  if (dup.size !== d.monthly_due_dates.length) e.monthly_due_dates = 'Hay fechas de mensualidad repetidas.'
  return e
}

export interface PaymentDraft {
  charge_id: string
  amount: number
  balance: number
  paid_at: string
  method: string
  reference: string
  file: { size: number; type: string } | null
  verified: boolean
}

export const VOUCHER_TYPES = ['image/png', 'image/jpeg', 'image/webp', 'application/pdf']
export const VOUCHER_MAX_BYTES = 5 * 1024 * 1024

export function validatePayment(d: PaymentDraft, today: string): FieldErrors {
  const e: FieldErrors = {}
  if (!d.charge_id) e.charge_id = 'Elige el cargo.'
  if (!(d.amount > 0)) e.amount = 'El monto debe ser mayor que S/ 0.'
  else if (d.amount > d.balance) e.amount = `El monto supera el saldo pendiente de ${money(d.balance)}.`
  if (!isIsoDate(d.paid_at)) e.paid_at = 'Indica la fecha del pago.'
  else if (d.paid_at > today) e.paid_at = 'La fecha no puede ser futura.'
  if (d.method !== 'bank_transfer' && d.method !== 'bank_deposit') e.method = 'Solo se aceptan pagos bancarios.'
  if (!d.reference.trim()) e.reference = 'Escribe la referencia bancaria.'
  if (!d.file) e.file = 'Adjunta la imagen del voucher.'
  else if (!VOUCHER_TYPES.includes(d.file.type)) e.file = 'El archivo debe ser PNG, JPG, WEBP o PDF.'
  else if (d.file.size > VOUCHER_MAX_BYTES) e.file = 'El archivo no puede pesar más de 5 MB.'
  if (!d.verified) e.verified = 'Confirma que verificaste el pago en el medio externo.'
  return e
}

/** Nombre de archivo seguro para la ruta {academy_id}/{payment_id}/{archivo}. */
export function safeFileName(name: string): string {
  const cleaned = name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9._-]+/g, '_')
    .replace(/^_+|_+$/g, '')
  return cleaned.slice(-80) || 'voucher'
}

export function voucherPath(academyId: string, paymentId: string, fileName: string): string {
  return `${academyId}/${paymentId}/${safeFileName(fileName)}`
}
