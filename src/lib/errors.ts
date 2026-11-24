// Errores: la interfaz decide por `error.hint` (código de negocio estable, contrato B02/B03).
// Nunca interpreta el texto libre de `message`. Los valores (saldo, cupo) se leen
// de la respuesta de la operación o de una nueva consulta, no del mensaje.

export type ErrorKind =
  | 'business' // el servidor respondió con un código de negocio (hint)
  | 'rejected' // el servidor respondió y rechazó (SQLSTATE / PostgREST), sin hint
  | 'uncertain' // no hubo respuesta fiable: puede haberse guardado (E23b)

export interface AppError {
  kind: ErrorKind
  hint: string
  code: string
  message: string
}

/** Catálogo hint → mensaje claro. Texto propuesto en F00 §4 y F01/F02. */
const CATALOG: Record<string, string> = {
  // Comunes
  SESSION_REQUIRED: 'Tu sesión terminó. Inicia sesión de nuevo; lo que escribiste en el formulario no se perdió.',
  ACCESS_DENIED: 'Tu rol no tiene acceso a esta acción.',
  // B02
  GROUP_NOT_FOUND: 'Ese grupo no está disponible para tu academia.',
  STUDENT_NOT_FOUND: 'No se encontró al alumno en tu academia.',
  INVALID_AMOUNT: 'Los precios deben ser mayores que S/ 0.',
  INVALID_DUE_DATE: 'La inscripción y al menos una mensualidad necesitan fecha de vencimiento.',
  ENROLLMENT_DUPLICATE: 'Este alumno ya tiene una matrícula en este ciclo.',
  GROUP_FULL: 'El grupo no tiene cupo. La solicitud puede quedar pendiente, pero no se puede activar hasta que haya vacante.',
  GROUP_CAPACITY_BELOW_OCCUPIED: 'La capacidad no puede ser menor que los cupos ya ocupados.',
  GROUP_CYCLE_HAS_ENROLLMENTS: 'No se puede cambiar el ciclo de un grupo que ya tiene matrículas.',
  GROUP_ACADEMY_HAS_ENROLLMENTS: 'No se puede cambiar la academia de un grupo que ya tiene matrículas.',
  TRANSFER_NO_ACTIVE_ENROLLMENT: 'El alumno no tiene una matrícula activa o excepcional en el ciclo del grupo destino.',
  TRANSFER_GROUP_FULL: 'El grupo destino está lleno. No se hicieron cambios.',
  // B03
  PAYMENT_ENROLLMENT_NOT_FOUND: 'No se encontró la matrícula.',
  PAYMENT_CHARGE_NOT_FOUND: 'No se encontró el cargo.',
  PAYMENT_CHARGE_MISMATCH: 'El cargo no pertenece a esa matrícula.',
  PAYMENT_INVALID_AMOUNT: 'El monto debe ser mayor que S/ 0.',
  PAYMENT_INVALID_DATE: 'Indica la fecha del pago.',
  PAYMENT_METHOD_INVALID: 'Solo se aceptan pagos bancarios. El efectivo no se registra.',
  PAYMENT_REFERENCE_REQUIRED: 'Escribe la referencia bancaria.',
  PAYMENT_VOUCHER_REQUIRED: 'Adjunta la imagen del voucher para confirmar el pago.',
  PAYMENT_VOUCHER_PATH_INVALID: 'El voucher no corresponde a este pago. Vuelve a elegirlo.',
  PAYMENT_VOUCHER_OBJECT_NOT_FOUND: 'El voucher no se subió. Vuelve a elegirlo y confirma otra vez.',
  PAYMENT_DUPLICATE_REFERENCE: 'Esa referencia bancaria ya está registrada.',
  PAYMENT_IDEMPOTENCY_CONFLICT: 'Este pago ya se había enviado con otros datos. Empieza un registro nuevo.',
  PAYMENT_OVERPAY: 'El monto supera el saldo pendiente del cargo.',
  PAYMENT_GROUP_FULL: 'El pago es válido, pero el grupo está lleno: la matrícula no se activó y el pago no se registró. Consulta con dirección.',
  PAYMENT_VOID_FORBIDDEN: 'Solo dirección puede anular pagos.',
  PAYMENT_VOID_REASON_REQUIRED: 'Escribe el motivo de la anulación.',
  PAYMENT_ALREADY_VOIDED: 'Este pago ya estaba anulado.',
  PAYMENT_NOT_FOUND: 'No se encontró el pago.',
  // B05
  CYCLE_NOT_FOUND: 'No se encontró el ciclo.',
  CASE_NOT_FOUND: 'El alumno no tiene un caso abierto en este ciclo.',
  INVALID_FOLLOWUP: 'Elige el canal de contacto y escribe una nota.',
  INVALID_DECISION: 'Elige la decisión y escribe el motivo.',
  CASE_NOT_CLOSABLE: 'Este caso ya está resuelto, o el alumno aún no alcanzó el límite de faltas para decidir.',
  // B06
  ENROLLMENT_NOT_FOUND: 'No se encontró la matrícula.',
  EXCEPTION_REASON_REQUIRED: 'Escribe el motivo de la excepción.',
  EXCEPTION_DUE_DATE_REQUIRED: 'Indica la fecha límite de pago.',
  EXCEPTION_STATUS_INVALID: 'Esta matrícula ya no está pendiente: la excepción solo se autoriza sobre una solicitud pendiente.',
  ENROLLMENT_CYCLE_MISMATCH: 'El grupo de la matrícula no coincide con su ciclo.',
  TRANSFER_CROSS_CYCLE: 'El grupo destino es de otro ciclo. Un traslado solo mueve al alumno dentro de su ciclo.',
  TRANSFER_SYNC_FAILED: 'No se pudo sincronizar el grupo del alumno. No se hicieron cambios.',
  // B04
  SESSION_DUPLICATE: 'Ya existe una sesión con ese grupo, curso y hora.',
  SESSION_OUTSIDE_CYCLE: 'La fecha de la sesión está fuera del ciclo del grupo.',
  INVALID_START_TIME: 'La fecha y hora de la sesión no son válidas.',
  ATTENDANCE_DUPLICATE: 'La asistencia de esta sesión ya estaba registrada.',
  INVALID_ATTENDANCE_BATCH: 'La lista de asistencia no es válida. Revisa que cada alumno tenga un estado.',
  ENROLLMENT_NOT_ACTIVE: 'Un alumno de la lista no tiene matrícula activa o excepcional. No se guardó ninguna asistencia.',
}

const DEFINITIVE_CODE = /^(22|23|28|42|P0|PGRST)/

interface RawError {
  message?: string
  hint?: string | null
  code?: string | null
  details?: string | null
}

export function toAppError(e: unknown): AppError {
  const raw = (e ?? {}) as RawError
  const hint = typeof raw.hint === 'string' ? raw.hint.trim() : ''
  const code = typeof raw.code === 'string' ? raw.code : ''
  if (hint) {
    return {
      kind: 'business',
      hint,
      code,
      message: CATALOG[hint] ?? `No se pudo completar la operación (código ${hint}).`,
    }
  }
  if (DEFINITIVE_CODE.test(code)) {
    return {
      kind: 'rejected',
      hint: '',
      code,
      message:
        code === '42501'
          ? 'Tu rol no tiene acceso a esta acción.'
          : `El servidor rechazó la operación (código ${code}).`,
    }
  }
  return {
    kind: 'uncertain',
    hint: '',
    code,
    message:
      'Perdimos la conexión y no podemos confirmar el resultado. No repitas la operación todavía.',
  }
}

/** Mensaje del catálogo para un código, útil en pruebas y en pantallas que ya conocen el hint. */
export function messageForHint(hint: string): string | undefined {
  return CATALOG[hint]
}

export function isKnownHint(hint: string): boolean {
  return hint in CATALOG
}

export function catalogHints(): string[] {
  return Object.keys(CATALOG)
}

/** Error lanzado por la capa de datos para que las pantallas no reciban objetos crudos. */
export class OperationError extends Error {
  readonly app: AppError
  constructor(app: AppError) {
    super(app.message)
    this.app = app
  }
}

export function asAppError(e: unknown): AppError {
  return e instanceof OperationError ? e.app : toAppError(e)
}
