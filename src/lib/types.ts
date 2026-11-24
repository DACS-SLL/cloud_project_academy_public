// Tipos de las filas que lee la interfaz. Siguen las migraciones B01–B03
// y docs/B02_CONTRATO_OPERACIONES.md. No se agregan columnas inventadas.

export type Role = 'admin' | 'cashier' | 'teacher'
export type Shift = 'morning' | 'afternoon' | 'night'
export type EnrollmentStatus = 'pending' | 'active' | 'exception' | 'cancelled'
export type PaymentMethod = 'bank_transfer' | 'bank_deposit'

export interface Access {
  academy_id: string
  academy_name: string
  role: Role
}

export interface Cycle {
  id: string
  academy_id: string
  name: string
  start_date: string
  end_date: string
  grade: string
  warning_absences: number
  review_absences: number
  late_counts_as_absence: boolean
}

export interface Group {
  id: string
  academy_id: string
  cycle_id: string
  name: string
  shift: Shift
  capacity: number
}

export interface Subject {
  id: string
  academy_id: string
  name: string
}

export interface TeacherAssignment {
  id: string
  academy_id: string
  teacher_id: string
  group_id: string
  subject_id: string
}

export interface Student {
  id: string
  academy_id: string
  group_id: string | null
  full_name: string
  document_id: string | null
  school: string | null
  grade: string | null
}

export interface Guardian {
  id: string
  academy_id: string
  student_id: string
  full_name: string
  document_id: string | null
  phone: string | null
}

export interface Enrollment {
  id: string
  academy_id: string
  student_id: string
  cycle_id: string
  group_id: string
  status: EnrollmentStatus
  agreed_registration_price: number
  agreed_monthly_price: number
  exception_reason: string | null
  exception_due_date: string | null
  authorized_by?: string | null
  authorized_at?: string | null
  created_at: string
}

export interface Charge {
  id: string
  academy_id: string
  student_id: string
  enrollment_id: string
  type: 'registration' | 'monthly'
  amount: number
  due_date: string
}

export interface Payment {
  id: string
  academy_id: string
  charge_id: string
  amount: number
  method: PaymentMethod
  reference: string
  voucher_path: string
  status: 'confirmed' | 'voided'
  void_reason: string | null
  paid_at: string | null
  voided_at: string | null
  created_at: string
}

export interface Capacity {
  group_id: string
  capacity: number
  occupied: number
  available: number
}

export interface TeacherProfile {
  user_id: string
  full_name: string
}

export interface PaymentResult {
  payment_id: string
  status: string
  amount: number
  charge_balance: number
  enrollment_status: EnrollmentStatus
  idempotent: boolean
}

export interface VoidResult {
  payment_id: string
  status: string
  charge_balance: number
  enrollment_status: EnrollmentStatus
}

export type AttendanceStatus = 'present' | 'absent' | 'late'

export interface ClassSession {
  id: string
  academy_id: string
  group_id: string
  subject_id: string
  teacher_id: string
  starts_at: string
  created_at: string
}

export interface AttendanceRecord {
  student_id: string
  status: AttendanceStatus
}

/** Fila que devuelve record_attendance (B04): una por alumno. */
export interface AttendanceResult {
  student_id: string
  status: AttendanceStatus
  absences_counted: number
  warning_active: boolean
  review_active: boolean
}

// ---------- B05 / B06 ----------
export type CaseType = 'debt' | 'attendance'
export type CaseStatus = 'open' | 'resolved' | 'needs_decision'
export type FollowupChannel = 'call' | 'whatsapp' | 'email' | 'in_person'
export type DecisionKind = 'continue' | 'close_case' | 'other'

/** Fila de `cycle_cases(p_cycle_id)`. `balance` es solo deuda VENCIDA; `total_balance` incluye lo futuro. */
export interface CycleCase {
  case_type: CaseType
  student_id: string
  full_name: string
  enrollment_id: string | null
  balance: number | null
  total_balance: number | null
  due_date: string | null
  overdue: boolean | null
  absences: number | null
  warning_threshold: number | null
  review_threshold: number | null
  requires_decision: boolean | null
  status: CaseStatus
}

export interface Followup {
  id: string
  student_id: string
  cycle_id: string
  channel: FollowupChannel
  note: string
  created_by: string
  created_at: string
  /** Nombre leído de `students` (no de `cycle_cases`), para que el historial lo conserve tras resolverse el caso. */
  student_name?: string | null
}

export interface AcademicDecision {
  id: string
  student_id: string
  cycle_id: string
  decision: DecisionKind
  reason: string
  created_by: string
  created_at: string
}

export interface EnrollmentTransfer {
  id: string
  enrollment_id: string
  student_id: string
  cycle_id: string
  from_group_id: string
  to_group_id: string
  transferred_by: string
  transferred_at: string
}
