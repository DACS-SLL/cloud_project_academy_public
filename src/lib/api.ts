// Capa de datos: todas las pantallas leen y escriben aquí. Usa solo lo que publica el contrato
// (docs/B02_CONTRATO_OPERACIONES.md): tablas con RLS y las RPC create_enrollment_request,
// group_capacity, transfer_student, register_payment y void_payment.
// La academia sale de la sesión; la base de datos la valida (RLS), nunca se confía en el navegador.

import { supabase } from './supabase'
import { OperationError, toAppError } from './errors'
import type {
  AcademicDecision,
  Access,
  CycleCase,
  DecisionKind,
  EnrollmentTransfer,
  Followup,
  FollowupChannel,
  AttendanceRecord,
  AttendanceResult,
  ClassSession,
  Capacity,
  Charge,
  Cycle,
  Enrollment,
  Group,
  Guardian,
  Payment,
  PaymentResult,
  Shift,
  Student,
  Subject,
  TeacherAssignment,
  TeacherProfile,
  VoidResult,
} from './types'

function fail(error: unknown): never {
  throw new OperationError(toAppError(error))
}

async function rows<T>(p: PromiseLike<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const { data, error } = await p
  if (error) fail(error)
  return data ?? []
}

async function one<T>(p: PromiseLike<{ data: T | null; error: unknown }>): Promise<T> {
  const { data, error } = await p
  if (error) fail(error)
  if (data === null) fail({ code: 'PGRST116', message: 'sin resultado' })
  return data as T
}

// ---------- Sesión y acceso ----------

export async function getAccess(): Promise<Access[]> {
  return rows<Access>(supabase.rpc('my_access'))
}

// ---------- Ciclos (D02) ----------

export interface CycleInput {
  name: string
  start_date: string
  end_date: string
  grade: string
  warning_absences: number
  review_absences: number
  late_counts_as_absence: boolean
}

export const listCycles = () =>
  rows<Cycle>(supabase.from('cycles').select('*').order('start_date', { ascending: false }))

export async function saveCycle(academyId: string, input: CycleInput, id?: string): Promise<Cycle> {
  if (id) {
    return one<Cycle>(supabase.from('cycles').update(input).eq('id', id).select('*').single())
  }
  return one<Cycle>(
    supabase.from('cycles').insert({ academy_id: academyId, ...input }).select('*').single(),
  )
}

// ---------- Grupos, cupos, cursos y docentes (D03) ----------

export interface GroupInput {
  name: string
  cycle_id: string
  shift: Shift
  capacity: number
}

export const listGroups = () =>
  rows<Group>(supabase.from('groups').select('*').order('name', { ascending: true }))

export async function saveGroup(academyId: string, input: GroupInput, id?: string): Promise<Group> {
  if (id) {
    return one<Group>(supabase.from('groups').update(input).eq('id', id).select('*').single())
  }
  return one<Group>(
    supabase.from('groups').insert({ academy_id: academyId, ...input }).select('*').single(),
  )
}

/** Cupo calculado por el servidor: solo activas y excepcionales ocupan (contrato §1.2). */
export async function groupCapacity(groupId: string): Promise<Capacity | null> {
  const list = await rows<Capacity>(supabase.rpc('group_capacity', { p_group_id: groupId }))
  return list[0] ?? null
}

export async function capacities(groups: Group[]): Promise<Record<string, Capacity>> {
  const result = await Promise.all(
    groups.map(async (g) => {
      try {
        return [g.id, await groupCapacity(g.id)] as const
      } catch {
        return [g.id, null] as const
      }
    }),
  )
  const map: Record<string, Capacity> = {}
  for (const [id, cap] of result) if (cap) map[id] = cap
  return map
}

export const listSubjects = () =>
  rows<Subject>(supabase.from('subjects').select('*').order('name', { ascending: true }))

export const createSubject = (academyId: string, name: string) =>
  one<Subject>(
    supabase.from('subjects').insert({ academy_id: academyId, name: name.trim() }).select('*').single(),
  )

export const listAssignments = () => rows<TeacherAssignment>(supabase.from('teacher_assignments').select('*'))

export const createAssignment = (academyId: string, teacherId: string, groupId: string, subjectId: string) =>
  one<TeacherAssignment>(
    supabase
      .from('teacher_assignments')
      .insert({ academy_id: academyId, teacher_id: teacherId, group_id: groupId, subject_id: subjectId })
      .select('*')
      .single(),
  )

export async function deleteAssignment(id: string): Promise<void> {
  const { error } = await supabase.from('teacher_assignments').delete().eq('id', id)
  if (error) fail(error)
}

/** Docentes de la academia con su nombre (membresías visibles para dirección + perfiles). */
export async function listTeachers(): Promise<TeacherProfile[]> {
  const memberships = await rows<{ user_id: string; role: string }>(
    supabase.from('memberships').select('user_id, role').eq('role', 'teacher'),
  )
  if (memberships.length === 0) return []
  const profiles = await rows<{ id: string; full_name: string }>(
    supabase.from('profiles').select('id, full_name').in('id', memberships.map((m) => m.user_id)),
  )
  const names = new Map(profiles.map((p) => [p.id, p.full_name]))
  return memberships.map((m) => ({ user_id: m.user_id, full_name: names.get(m.user_id) || 'Docente' }))
}

// ---------- Alumnos y apoderados ----------

export const listStudents = () =>
  rows<Student>(supabase.from('students').select('*').order('full_name', { ascending: true }))

/** Lista mínima para el docente: solo nombre e identificador (F00: sin datos de contacto ni finanzas). */
export const listStudentsMinimal = () =>
  rows<Pick<Student, 'id' | 'full_name' | 'group_id'>>(
    supabase.from('students').select('id, full_name, group_id').order('full_name', { ascending: true }),
  )

export async function findStudentByDni(dni: string): Promise<Student | null> {
  const { data, error } = await supabase
    .from('students')
    .select('*')
    .eq('document_id', dni.trim())
    .limit(1)
  if (error) fail(error)
  return (data?.[0] as Student | undefined) ?? null
}

export interface StudentInput {
  full_name: string
  document_id: string
  school: string
  grade: string
}

// El alumno nace sin grupo: el grupo se asigna al activar la matrícula (contrato §1.3).
export const createStudent = (academyId: string, input: StudentInput) =>
  one<Student>(
    supabase
      .from('students')
      .insert({
        academy_id: academyId,
        full_name: input.full_name.trim(),
        document_id: input.document_id.trim(),
        school: input.school.trim(),
        grade: input.grade.trim(),
      })
      .select('*')
      .single(),
  )

export interface GuardianInput {
  full_name: string
  document_id: string
  phone: string
}

export const createGuardian = (academyId: string, studentId: string, input: GuardianInput) =>
  one<Guardian>(
    supabase
      .from('guardians')
      .insert({
        academy_id: academyId,
        student_id: studentId,
        full_name: input.full_name.trim(),
        document_id: input.document_id.trim(),
        phone: input.phone.trim(),
      })
      .select('*')
      .single(),
  )

export const listGuardians = (studentId: string) =>
  rows<Guardian>(supabase.from('guardians').select('*').eq('student_id', studentId))

// ---------- Matrícula y cargos (C02, C03) ----------

export interface EnrollmentRequestInput {
  studentId: string
  groupId: string
  registrationPrice: number
  monthlyPrice: number
  registrationDueDate: string
  monthlyDueDates: string[]
}

/** Solicitud `pending` + cargos en una transacción. No ocupa cupo (contrato §1.1). */
export async function createEnrollmentRequest(input: EnrollmentRequestInput): Promise<string> {
  const { data, error } = await supabase.rpc('create_enrollment_request', {
    p_student_id: input.studentId,
    p_group_id: input.groupId,
    p_registration_price: input.registrationPrice,
    p_monthly_price: input.monthlyPrice,
    p_registration_due_date: input.registrationDueDate,
    p_monthly_due_dates: input.monthlyDueDates,
  })
  if (error) fail(error)
  return data as string
}

export const listEnrollments = () =>
  rows<Enrollment>(supabase.from('enrollments').select('*').order('created_at', { ascending: false }))

export async function findEnrollment(studentId: string, cycleId: string): Promise<Enrollment | null> {
  const { data, error } = await supabase
    .from('enrollments')
    .select('*')
    .eq('student_id', studentId)
    .eq('cycle_id', cycleId)
    .limit(1)
  if (error) fail(error)
  return (data?.[0] as Enrollment | undefined) ?? null
}

export const listCharges = () =>
  rows<Charge>(supabase.from('charges').select('*').order('due_date', { ascending: true }))

export const listPayments = () =>
  rows<Payment>(supabase.from('payments').select('*').order('created_at', { ascending: false }))

export interface StudentFile {
  student: Student
  guardians: Guardian[]
  enrollments: Enrollment[]
  charges: Charge[]
  payments: Payment[]
}

export async function getStudentFile(studentId: string): Promise<StudentFile> {
  const [student, guardians, enrollments, charges] = await Promise.all([
    one<Student>(supabase.from('students').select('*').eq('id', studentId).single()),
    listGuardians(studentId),
    rows<Enrollment>(supabase.from('enrollments').select('*').eq('student_id', studentId)),
    rows<Charge>(supabase.from('charges').select('*').eq('student_id', studentId).order('due_date')),
  ])
  const chargeIds = charges.map((c) => c.id)
  const payments = chargeIds.length
    ? await rows<Payment>(
        supabase.from('payments').select('*').in('charge_id', chargeIds).order('created_at', { ascending: false }),
      )
    : []
  return { student, guardians, enrollments, charges, payments }
}

// ---------- Pagos y vouchers (C04, D06) ----------

export async function findPayment(paymentId: string): Promise<Payment | null> {
  const { data, error } = await supabase.from('payments').select('*').eq('id', paymentId).maybeSingle()
  if (error) fail(error)
  return (data as Payment | null) ?? null
}

/** Sube el voucher a la ruta {academy_id}/{payment_id}/{archivo}. Una subida repetida del mismo objeto no es un error. */
export async function uploadVoucher(path: string, file: File): Promise<void> {
  const { error } = await supabase.storage.from('vouchers').upload(path, file, {
    upsert: false,
    contentType: file.type,
  })
  if (!error) return
  const raw = error as { message?: string; statusCode?: string | number }
  const duplicate =
    String(raw.statusCode) === '409' || /already exists|duplicate/i.test(raw.message ?? '')
  if (duplicate) return
  throw new OperationError({
    kind: /fetch|network|load failed|timeout/i.test(raw.message ?? '') ? 'uncertain' : 'rejected',
    hint: '',
    code: String(raw.statusCode ?? ''),
    message: 'No se pudo subir el voucher. Revisa el archivo y tu conexión, y vuelve a intentar.',
  })
}

export interface RegisterPaymentInput {
  paymentId: string
  enrollmentId: string
  chargeId: string
  amount: number
  paidAt: string
  method: string
  reference: string
  voucherPath: string
}

/** El mismo `paymentId` identifica el intento completo: consultar o reintentar nunca duplica (contrato §2.2). */
export async function registerPayment(input: RegisterPaymentInput): Promise<PaymentResult> {
  const { data, error } = await supabase.rpc('register_payment', {
    p_payment_id: input.paymentId,
    p_enrollment_id: input.enrollmentId,
    p_charge_id: input.chargeId,
    p_amount: input.amount,
    p_paid_at: input.paidAt,
    p_method: input.method,
    p_reference: input.reference.trim(),
    p_voucher_path: input.voucherPath,
  })
  if (error) fail(error)
  const row = (Array.isArray(data) ? data[0] : data) as PaymentResult | undefined
  if (!row) fail({ code: 'PGRST116', message: 'sin resultado' })
  return row as PaymentResult
}

export async function voidPayment(paymentId: string, reason: string): Promise<VoidResult> {
  const { data, error } = await supabase.rpc('void_payment', {
    p_payment_id: paymentId,
    p_reason: reason.trim(),
  })
  if (error) fail(error)
  const row = (Array.isArray(data) ? data[0] : data) as VoidResult | undefined
  if (!row) fail({ code: 'PGRST116', message: 'sin resultado' })
  return row as VoidResult
}

/** URL firmada de corta duración; nunca se guarda una URL permanente. */
export async function signedVoucherUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from('vouchers').createSignedUrl(path, 60)
  if (error || !data) fail(error ?? { code: 'PGRST116' })
  return (data as { signedUrl: string }).signedUrl
}

// ---------- Traslado (D05a) ----------

export async function transferStudent(studentId: string, groupId: string): Promise<void> {
  const { error } = await supabase.rpc('transfer_student', {
    p_student_id: studentId,
    p_group_id: groupId,
  })
  if (error) fail(error)
}


// ---------- B04: sesiones y asistencia (solo por RPC; sin escrituras directas) ----------

export const listSessions = () =>
  rows<ClassSession>(supabase.from('class_sessions').select('*').order('starts_at', { ascending: false }).limit(100))

export async function findSession(groupId: string, subjectId: string, startsAt: string): Promise<ClassSession | null> {
  const { data, error } = await supabase
    .from('class_sessions')
    .select('*')
    .eq('group_id', groupId)
    .eq('subject_id', subjectId)
    .eq('starts_at', startsAt)
    .maybeSingle()
  if (error) fail(error)
  return (data as ClassSession | null) ?? null
}

export async function getSession(id: string): Promise<ClassSession | null> {
  const { data, error } = await supabase.from('class_sessions').select('*').eq('id', id).maybeSingle()
  if (error) fail(error)
  return (data as ClassSession | null) ?? null
}

export const listAttendance = (sessionId: string) =>
  rows<{ student_id: string; status: AttendanceRecord['status'] }>(
    supabase.from('attendance').select('student_id, status').eq('session_id', sessionId),
  )

export async function createClassSession(groupId: string, subjectId: string, startsAt: string): Promise<string> {
  const { data, error } = await supabase.rpc('create_class_session', {
    p_group_id: groupId,
    p_subject_id: subjectId,
    p_starts_at: startsAt,
  })
  if (error) fail(error)
  return data as string
}

export async function recordAttendance(sessionId: string, records: AttendanceRecord[]): Promise<AttendanceResult[]> {
  const { data, error } = await supabase.rpc('record_attendance', { p_session_id: sessionId, p_records: records })
  if (error) fail(error)
  return (data ?? []) as AttendanceResult[]
}


// ---------- B05: casos, seguimiento y decisión · B06: excepciones e historial ----------

/** Casos de deuda y faltas de un ciclo, calculados por la base (`balance` = solo deuda vencida). */
export async function cycleCases(cycleId: string): Promise<CycleCase[]> {
  const { data, error } = await supabase.rpc('cycle_cases', { p_cycle_id: cycleId })
  if (error) fail(error)
  return ((data ?? []) as CycleCase[]).map((c) => ({
    ...c,
    balance: c.balance === null ? null : Number(c.balance),
    total_balance: c.total_balance === null ? null : Number(c.total_balance),
  }))
}

export async function registerFollowup(studentId: string, cycleId: string, channel: FollowupChannel, note: string) {
  const { data, error } = await supabase.rpc('register_followup', {
    p_student_id: studentId,
    p_cycle_id: cycleId,
    p_channel: channel,
    p_note: note,
  })
  if (error) fail(error)
  return data as string
}

export async function registerAcademicDecision(studentId: string, cycleId: string, decision: DecisionKind, reason: string) {
  const { data, error } = await supabase.rpc('register_academic_decision', {
    p_student_id: studentId,
    p_cycle_id: cycleId,
    p_decision: decision,
    p_reason: reason,
  })
  if (error) fail(error)
  return data as string
}

/**
 * Contactos del ciclo con el nombre del alumno leído de `students`.
 * No se toma de `cycle_cases`: al resolverse la deuda el caso desaparece y el historial debe conservar el nombre.
 */
export async function listFollowups(cycleId: string): Promise<Followup[]> {
  const list = await rows<Followup>(
    supabase.from('followups').select('*').eq('cycle_id', cycleId).order('created_at', { ascending: false }),
  )
  const ids = [...new Set(list.map((f) => f.student_id))]
  if (ids.length === 0) return list
  const names = await rows<{ id: string; full_name: string }>(supabase.from('students').select('id, full_name').in('id', ids))
  const byId = new Map(names.map((s) => [s.id, s.full_name]))
  return list.map((f) => ({ ...f, student_name: byId.get(f.student_id) ?? null }))
}

export const listDecisions = (cycleId: string) =>
  rows<AcademicDecision>(
    supabase.from('academic_decisions').select('*').eq('cycle_id', cycleId).order('created_at', { ascending: false }),
  )

/** Solo dirección. Devuelve el id de la matrícula actualizada. */
export async function authorizeEnrollmentException(enrollmentId: string, reason: string, dueDate: string) {
  const { data, error } = await supabase.rpc('authorize_enrollment_exception', {
    p_enrollment_id: enrollmentId,
    p_reason: reason,
    p_due_date: dueDate,
  })
  if (error) fail(error)
  return data as string
}

export const listTransfers = (studentId?: string) => {
  let q = supabase.from('enrollment_transfers').select('*').order('transferred_at', { ascending: false }).limit(200)
  if (studentId) q = q.eq('student_id', studentId)
  return rows<EnrollmentTransfer>(q)
}
