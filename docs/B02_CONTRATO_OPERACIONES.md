# Contrato de integración B02/B03/B05

**Estado:** B02 y B03 verificados en cloud. B04, B05 y B06 implementados y aplicados en el proyecto demo. B05 verificado en Supabase cloud el 2026-11-23 en la rama `feat/B05-alertas-decision`; B04 y B06 quedan pendientes de verificación.
**Base:** `main` con B01/B02/B03; B04, B06 y B05 se integran en ramas sobre esa base.
**Consumidores:** Juan (`F01`–`F03`), Yony (`B04`/`B06`), dirección y secretaría.

Este documento fija firmas, respuestas y códigos de error para que la interfaz no dependa de detalles internos.

## Convenciones

- Todas las operaciones usan la sesión de Supabase Auth y leen rol/academia desde `memberships`.
- Los ids son UUID; las fechas son `YYYY-MM-DD`; el dinero es `numeric(12,2)` y se envía como número.
- `academy_id` nunca se toma del navegador como prueba de autorización: la RPC valida la academia de la fila.
- Error PostgREST: `{ code, message, details, hint }`. `code` es el SQLSTATE; `hint` es el **código de negocio estable** que debe usar el frontend. `message` es solo presentación.
- B02, B03, B04, B05 y B06 ya devuelven `hint`; el frontend decide flujos por `error.hint`, no por texto.

## Parte 1 — B02 implementado

### 1.1 `create_enrollment_request`

```sql
public.create_enrollment_request(
  p_student_id uuid,
  p_group_id uuid,
  p_registration_price numeric,
  p_monthly_price numeric,
  p_registration_due_date date,
  p_monthly_due_dates date[]
) returns uuid
```

**Roles:** `admin` o `cashier` de la academia del grupo.
**Efecto:** crea una matrícula `pending` y cargos separados (`registration` + una fila `monthly` por fecha). No ocupa cupo ni asigna `students.group_id`.
**Retorno:** `id` de la matrícula.
**Idempotencia:** no. Un reintento con los mismos datos devuelve `ENROLLMENT_DUPLICATE`; el frontend debe bloquear doble envío.

Ejemplo:

```ts
const { data: enrollmentId, error } = await supabase.rpc('create_enrollment_request', {
  p_student_id: studentId,
  p_group_id: groupId,
  p_registration_price: 300,
  p_monthly_price: 200,
  p_registration_due_date: '2026-11-10',
  p_monthly_due_dates: ['2026-12-10', '2027-01-10', '2027-02-10'],
})
```

Errores B02:

| `code` | `hint` | HTTP | `message` estable | Cuándo |
|---|---|---|---|---|
| `28000` | `SESSION_REQUIRED` | 401 | `Sesión no autenticada` | Sin JWT |
| `42501` | `ACCESS_DENIED` | 403 | `Solo dirección o secretaría pueden registrar matrículas` | Rol incorrecto o grupo de otra academia |
| `P0002` | `GROUP_NOT_FOUND` | 404 | `Grupo no encontrado` | Grupo inexistente |
| `P0002` | `STUDENT_NOT_FOUND` | 404 | `Alumno no encontrado en la academia` | Alumno de otra academia o inexistente |
| `22023` | `INVALID_AMOUNT` | 400 | `Los precios deben ser positivos` | Precio nulo, cero o negativo |
| `22023` | `INVALID_DUE_DATE` | 400 | `La inscripción y al menos una mensualidad requieren vencimiento` | Falta fecha o arreglo vacío |
| `23505` | `ENROLLMENT_DUPLICATE` | 409 | `El alumno ya tiene una matrícula en este ciclo` | Segunda matrícula del mismo alumno/ciclo |

### 1.2 `group_capacity`

```sql
public.group_capacity(p_group_id uuid)
returns table (
  group_id uuid,
  capacity integer,
  occupied integer,
  available integer
)
```

**Roles:** `admin`, `cashier` o docente asignado al grupo.
**Cálculo:** solo cuentan matrículas `active` y `exception`.
**Respuesta:** arreglo con una fila.

```ts
const { data: capacity } = await supabase.rpc('group_capacity', {
  p_group_id: groupId,
})
// [{ group_id, capacity, occupied, available }]
```

Errores:

| `code` | `hint` | HTTP | `message` |
|---|---|---|---|
| `28000` | `SESSION_REQUIRED` | 401 | `Sesión no autenticada` |
| `42501` | `ACCESS_DENIED` | 403 | `Sin acceso al grupo` |
| `P0002` | `GROUP_NOT_FOUND` | 404 | `Grupo no encontrado` |

### 1.3 Operaciones directas B02

| Recurso | Admin | Cashier | Docente | Restricciones |
|---|---|---|---|---|
| `cycles` | Leer/crear/editar/borrar | Leer | Leer | `review_absences > warning_absences`; fechas válidas; nombre único por academia |
| `groups` | Leer/crear/editar/borrar | Leer | Solo asignados | `cycle_id` obligatorio; capacidad > 0; no bajar capacidad bajo ocupados; no cambiar ciclo/academia con matrículas |
| `subjects` | CRUD | Leer | Solo asignados | Nombre único por academia |
| `teacher_assignments` | CRUD | Sin acceso | Solo propias | Docente, grupo y curso de la misma academia |
| `students` | Crear sin grupo/editar datos | Crear sin grupo/editar datos | Solo lectura de sus grupos | No `group_id` al crear; no borrar; no editar `academy_id`/`group_id` |
| `guardians` | CRUD | CRUD | Sin acceso | Alumno de la misma academia |
| `enrollments` | Leer | Leer | Sin acceso | Sin escritura directa |
| `charges` | Leer | Leer | Sin acceso | Sin `INSERT`/`UPDATE`/`DELETE` directo; nacen en la RPC de matrícula |

Campos de lectura principales:

```text
cycles: id, academy_id, name, start_date, end_date, grade,
        warning_absences, review_absences, late_counts_as_absence, created_at
groups: id, academy_id, cycle_id, name, shift, capacity, created_at
enrollments: id, academy_id, student_id, cycle_id, group_id, status,
             agreed_registration_price, agreed_monthly_price,
             exception_reason, exception_due_date, authorized_by, authorized_at, created_at
charges: id, academy_id, student_id, enrollment_id, type, amount, due_date, created_at
students: id, academy_id, group_id, full_name, document_id, school, grade, created_at
```

Estados de matrícula:

- `pending`: solicitud registrada; no ocupa cupo; no asigna grupo.
- `active`: inscripción confirmada; ocupa cupo; estudiante visible al docente del grupo.
- `exception`: autorizada por dirección; ocupa cupo; requiere motivo y fecha límite.
- `cancelled`: reservado para B03/B06; todavía sin flujo.

### 1.4 Grupo lleno y matrícula duplicada

- **Matrícula duplicada:** `code=23505`, `hint=ENROLLMENT_DUPLICATE`, HTTP 409.
- **Grupo lleno:** se emite al activar, autorizar excepción o trasladar; no al crear la solicitud. El trigger responde `code=23514`, `hint=GROUP_FULL` (o `TRANSFER_GROUP_FULL` en traslado).
- **Solicitud pendiente en grupo lleno:** permitida por contrato; no ocupa cupo. La interfaz debe mostrar advertencia con `group_capacity` y saber que la activación puede fallar.
- **Capacidad inválida:** bajar la capacidad por debajo de los ocupados devuelve `hint=GROUP_CAPACITY_BELOW_OCCUPIED`.
- **Ciclo/academia inválidos:** cambiar el ciclo o academia de un grupo con matrículas devuelve `hint=GROUP_CYCLE_HAS_ENROLLMENTS` o `GROUP_ACADEMY_HAS_ENROLLMENTS`.

### 1.5 `transfer_student` B01 corregido

```sql
public.transfer_student(p_student_id uuid, p_group_id uuid) returns void
```

**Rol:** solo `admin` de la academia.
**Regla:** exige matrícula `active` o `exception` del alumno en el ciclo del grupo destino. Actualiza `enrollments.group_id`; el trigger de B02 sincroniza `students.group_id` y valida cupo en la misma transacción.

| `hint` | SQLSTATE | HTTP | Cuándo |
|---|---|---|---|
| `ACCESS_DENIED` | `42501` | 403 | Rol incorrecto |
| `STUDENT_NOT_FOUND` | `22023` | 400 | Alumno inexistente |
| `GROUP_NOT_FOUND` | `22023` | 400 | Grupo inexistente o de otra academia |
| `TRANSFER_NO_ACTIVE_ENROLLMENT` | `23514` | 400 | Alumno sin matrícula activa/excepcional en el ciclo |
| `TRANSFER_GROUP_FULL` | `23514` | 400 | Grupo destino lleno |

Un grupo de otra academia se reporta como `GROUP_NOT_FOUND` para no revelar su existencia. No asigna grupo a alumnos sin matrícula. B06 conservará el historial de traslados sobre esta base.

## Parte 2 — B03 implementado

> Firmas vigentes para `F02`. B03 está aplicado en Supabase cloud y probado por API/SQL.

### 2.1 `register_payment`

```sql
public.register_payment(
  p_payment_id uuid,
  p_enrollment_id uuid,
  p_charge_id uuid,
  p_amount numeric,
  p_paid_at date,
  p_method text,          -- bank_transfer | bank_deposit
  p_reference text,
  p_voucher_path text
)
returns table (
  payment_id uuid,
  status text,            -- confirmed
  amount numeric,
  charge_balance numeric,
  enrollment_status text, -- pending | active | exception
  idempotent boolean
)
```

**Roles:** `admin`/`cashier`.
**Cambios de esquema implementados:** `payments.paid_at date`, `payments.voided_at`, `payments.voided_by` e índice único `(academy_id, reference)`.

**Reglas transaccionales:**

1. Cargo y matrícula deben pertenecer a la misma academia y el cargo a esa matrícula.
2. `amount > 0` y `amount <= saldo` del cargo.
3. `p_method` solo `bank_transfer` o `bank_deposit`; `reference` obligatoria.
4. `p_voucher_path` obligatorio, con formato `{academy_id}/{payment_id}/{archivo}`; el objeto debe existir en el bucket privado.
5. Se inserta el pago `confirmed`; si la inscripción queda pagada y la matrícula está `pending`, se activa y el trigger de B02 vuelve a validar cupo.
6. Todo ocurre en una transacción: si falla el cupo o el voucher, no queda pago confirmado.

Errores B03:

| `hint` | SQLSTATE | HTTP | Cuándo |
|---|---|---|---|
| `ACCESS_DENIED` | `42501` | 403 | Rol incorrecto o fila de otra academia |
| `PAYMENT_ENROLLMENT_NOT_FOUND` | `22023` | 400 | Matrícula inexistente |
| `PAYMENT_CHARGE_NOT_FOUND` | `22023` | 400 | Cargo inexistente |
| `PAYMENT_CHARGE_MISMATCH` | `23514` | 400 | Cargo de otra matrícula |
| `PAYMENT_INVALID_AMOUNT` | `22023` | 400 | Monto nulo, cero o negativo |
| `PAYMENT_INVALID_DATE` | `22023` | 400 | Fecha faltante |
| `PAYMENT_METHOD_INVALID` | `22023` | 400 | Efectivo, método nulo u otro método |
| `PAYMENT_REFERENCE_REQUIRED` | `22023` | 400 | Referencia vacía |
| `PAYMENT_VOUCHER_REQUIRED` | `22023` | 400 | Falta `voucher_path` |
| `PAYMENT_VOUCHER_PATH_INVALID` | `22023` | 400 | La ruta no corresponde a academia/pago |
| `PAYMENT_VOUCHER_OBJECT_NOT_FOUND` | `22023` | 400 | El objeto no existe |
| `PAYMENT_DUPLICATE_REFERENCE` | `23505` | 409 | Referencia bancaria ya registrada |
| `PAYMENT_IDEMPOTENCY_CONFLICT` | `23505` | 409 | Mismo `payment_id` con datos distintos |
| `PAYMENT_OVERPAY` | `23514` | 400 | `amount > saldo` |
| `PAYMENT_GROUP_FULL` | `23514` | 400 | La activación encontró el grupo lleno |
| `PAYMENT_VOID_FORBIDDEN` | `42501` | 403 | Intento de anular sin rol `admin` |
| `PAYMENT_VOID_REASON_REQUIRED` | `22023` | 400 | Anulación sin motivo |
| `PAYMENT_ALREADY_VOIDED` | `23514` | 400 | Pago ya anulado |
| `PAYMENT_NOT_FOUND` | `22023` | 400 | Pago inexistente |

### 2.2 Pérdida de conexión al confirmar un pago

Contrato para `F02`:

1. **El cliente genera `p_payment_id` antes de subir el voucher.** Ese UUID es la clave de idempotencia. La ruta del voucher usa ese mismo id.
2. Sube el voucher a `vouchers/{academy_id}/{p_payment_id}/...` y luego llama `register_payment` con ese `p_payment_id`.
3. Si se pierde la conexión **después de enviar**, no generar un pago nuevo. Reintentar con el mismo `p_payment_id`:
   - si el pago ya existe con los mismos datos, la RPC responde lo mismo con `idempotent = true`;
   - si existe con otros datos, responde `PAYMENT_IDEMPOTENCY_CONFLICT`.
4. Mientras no haya respuesta, la UI muestra “Verificando pago” y consulta `payments?id=eq.{p_payment_id}`. No habilita “Registrar otro pago”.
5. Si el pago no existe tras el timeout, se puede reintentar la misma llamada. Si el usuario abandona, el voucher queda huérfano y entra al flujo de limpieza.

### 2.3 Voucher subido y pago rechazado

- El rechazo de la RPC no deja pago confirmado ni muta saldo; el objeto puede quedar en el bucket privado.
- `F02` no borra directamente: B01 no concede `DELETE` de Storage a `authenticated`.
- **P0:** el descarte inmediato está deshabilitado para evitar la carrera entre comprobar el pago y borrar el objeto mientras `register_payment` podría confirmar ese mismo voucher.
- La Edge Function `discard-voucher` responde `501 DISCARD_DEFERRED` y no elimina objetos.
- Endpoint: `POST /functions/v1/discard-voucher`.
- El voucher rechazado queda huérfano en el bucket privado. La limpieza se hará administrativamente con `service_role` o con una tarea posterior coordinada de forma segura con el pago.
- `F02` no debe borrar vouchers desde el navegador.

### 2.4 Anulación implementada

```sql
public.void_payment(p_payment_id uuid, p_reason text)
returns table (
  payment_id uuid,
  status text,            -- voided
  charge_balance numeric,
  enrollment_status text
)
```

**Rol:** solo `admin`. Motivo obligatorio. Recalcula saldo y conserva auditoría en `void_reason`, `voided_at` y `voided_by`.

Regla confirmada: si se anula el pago que activó una inscripción y el saldo vuelve a positivo, la matrícula `active` vuelve a `pending` y libera `students.group_id`. Si conserva autorización excepcional (`exception_reason`), vuelve a `exception` y mantiene el cupo.

## Parte 3 — B05 implementado

> Contrato para `F03` implementado en [`docs/B05_CONTRATO_OPERACIONES.md`](B05_CONTRATO_OPERACIONES.md).

### 3.1 `cycle_cases`

```sql
public.cycle_cases(p_cycle_id uuid)
returns table (
  case_type text,          -- debt | attendance
  student_id uuid,
  full_name text,
  enrollment_id uuid,
  balance numeric,         -- deuda vencida con saldo
  total_balance numeric,   -- saldo total (vencido + futuro)
  due_date date,
  overdue boolean,
  absences integer,
  warning_threshold integer,
  review_threshold integer,
  requires_decision boolean,
  status text              -- open | resolved | needs_decision
)
```

**Roles:** `admin`/`cashier`. Docente sin acceso.
**Cálculo:** deuda desde cargos menos pagos confirmados no anulados; faltas desde asistencias del ciclo y regla de tardanza. No se usan indicadores fijos.

- Los casos se calculan; no hay tabla `cycle_cases` ni tareas programadas.
- La deuda se agrega por matrícula e incluye `pending`, `active` y `exception`; pagos `voided` no reducen saldo. `balance` es solo lo vencido con saldo y `total_balance` el saldo total; un cargo futuro no genera alerta.
- Para una matrícula `exception`, el cargo `registration` usa `exception_due_date`.
- Las faltas se cuentan por ciclo; `late` suma solo si `late_counts_as_absence = true`; los umbrales salen de `cycles`.
- `register_followup` no cierra el caso y se bloquea sobre casos resueltos.
- `register_academic_decision` conserva historial de decisiones; cualquier decisión resuelve el caso y no altera asistencias.

### 3.2 `register_followup` y `register_academic_decision`

```sql
public.register_followup(
  p_student_id uuid,
  p_cycle_id uuid,
  p_channel text,   -- call | whatsapp | email | in_person
  p_note text
) returns uuid

public.register_academic_decision(
  p_student_id uuid,
  p_cycle_id uuid,
  p_decision text,  -- continue | close_case | other
  p_reason text
) returns uuid
```

- `register_followup`: `admin`/`cashier`; registra contacto, no cierra el caso.
- `register_academic_decision`: solo `admin`; exige motivo; no desaprueba automáticamente.
- Errores B05 (en `hint`): `SESSION_REQUIRED` (`28000`, 401), `ACCESS_DENIED` (`42501`, 403), `CYCLE_NOT_FOUND` (`22023`, 400), `CASE_NOT_FOUND` (`22023`, 400), `INVALID_FOLLOWUP` (`22023`, 400), `INVALID_DECISION` (`22023`, 400), `CASE_NOT_CLOSABLE` (`23514`, 400).

## Parte 4 — Coordinación con Yony (B04/B06)

### B04 — Asistencia

- Debe leer `cycles.warning_absences`, `cycles.review_absences`, `cycles.late_counts_as_absence`.
- `groups.cycle_id` es obligatorio; la sesión debe pertenecer al ciclo del grupo.
- `students.group_id` se sincroniza cuando la matrícula pasa a `active`/`exception`.
- **Confirmado con Yony:** `B04` usa `attendance.student_id`, validando que el alumno tenga matrícula `active`/`exception` en el ciclo del grupo. No se agrega `enrollment_id` a `attendance`.
- Errores definitivos: `SESSION_REQUIRED` (`28000`), `ACCESS_DENIED` (`42501`), `INVALID_START_TIME` (`22023`), `SESSION_DUPLICATE` (`23505`), `SESSION_OUTSIDE_CYCLE` (`23514`), `INVALID_ATTENDANCE_BATCH` (`22023`), `ATTENDANCE_DUPLICATE` (`23505`), `STUDENT_NOT_FOUND` (`P0002`) y `ENROLLMENT_NOT_ACTIVE` (`23514`). No se emiten `ATTENDANCE_NOT_ASSIGNED` ni `INVALID_ATTENDANCE_STATUS`. Contrato completo en [`docs/B04_CONTRATO_OPERACIONES.md`](B04_CONTRATO_OPERACIONES.md).

### B06 — Excepción y traslado

Reglas confirmadas con Yony:

- Autorizar excepciones **solo desde matrícula `pending`**; renovaciones quedan para después.
- Trasladar **solo matrículas `active` o `exception`**, dentro de la misma academia y ciclo.
- `enrollment_transfers` conserva historial y se escribe en la misma transacción que la sincronización de `enrollments.group_id` y `students.group_id`.
- La excepción escribe `status = 'exception'`, `exception_reason`, `exception_due_date`, `authorized_by`, `authorized_at`.
- El trigger de B02 bloquea el grupo y cuenta `active`/`exception`.
- `transfer_student` ya sincroniza matrícula y alumno; B06 agrega el historial.
- Un grupo de otra academia responde `GROUP_NOT_FOUND`, sin revelar su existencia.

Implementación B06:

- `authorize_enrollment_exception(p_enrollment_id uuid, p_reason text, p_due_date date)` solo `admin`; exige `pending`, guarda motivo/fecha/autor y deja que el trigger de B02 valide cupo.
- La excepción ocupa cupo; B03 la convierte a `active` al completar la inscripción.
- B06 inserta `enrollment_transfers` (`academy_id`, `enrollment_id`, `from_group_id`, `to_group_id`, `authorized_by`, `created_at`) en la misma transacción, sin historial si falla el cupo.
- RLS: historial de lectura para `admin`/`cashier`; escritura solo por RPC.
- Errores definitivos en [`docs/B06_CONTRATO_OPERACIONES.md`](B06_CONTRATO_OPERACIONES.md): `SESSION_REQUIRED`, `ACCESS_DENIED`, `ENROLLMENT_NOT_FOUND`, `EXCEPTION_REASON_REQUIRED`, `EXCEPTION_DUE_DATE_REQUIRED`, `EXCEPTION_STATUS_INVALID`, `GROUP_FULL`, `ENROLLMENT_CYCLE_MISMATCH`, `STUDENT_NOT_FOUND`, `GROUP_NOT_FOUND`, `TRANSFER_CROSS_CYCLE`, `TRANSFER_NO_ACTIVE_ENROLLMENT`, `TRANSFER_GROUP_FULL` y `TRANSFER_SYNC_FAILED`.

## Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `node scripts/verify-b01-isolation.mjs` | `40/40 comprobaciones OK` |
| `node scripts/verify-b02-enrollment.mjs` | `28/28 comprobaciones OK` |
| `node scripts/verify-b03-payments.mjs` | `27/27 comprobaciones OK` |
| `npx supabase db query --remote --file supabase/tests/b01_rls.sql --yes` | `B01 RLS: todas las comprobaciones pasaron` |
| `npx supabase db query --remote --file supabase/tests/b02_enrollment.sql --yes` | `B02 RLS: todas las comprobaciones pasaron` |
| `npx supabase db query --remote --file supabase/tests/b03_payments.sql --yes` | `B03 RLS: todas las comprobaciones pasaron` |
| `npx supabase db lint --linked` | `No schema errors found` |
| `npm run build` | OK |

B04, B05 y B06 incluyen pruebas SQL en sus ramas. B05 agrega `supabase/tests/b05_alerts_decisions.sql`. El 2026-11-21 se aplicaron las migraciones B01–B06/B05 desde cero en PostgreSQL 18 con esquema Supabase simulado y pasaron las pruebas B01, B02, B03, B04, B06 y B05. El 2026-11-23 se aplicaron las migraciones pendientes B04, B06 y B05 en `academia-manager-b01` y la prueba B05 pasó en cloud; las verificaciones B04/B06 de Yony siguen pendientes.

## Bloqueos concretos

1. **B05:** migraciones B04, B06 y B05 aplicadas y `supabase/tests/b05_alerts_decisions.sql` ejecutado en el proyecto demo el 2026-11-23; queda la revisión del PR #10.
2. **F01–F03:** Juan debe compartir los documentos de pantallas/estados para cerrar el contrato de integración y validar mensajes/errores.
