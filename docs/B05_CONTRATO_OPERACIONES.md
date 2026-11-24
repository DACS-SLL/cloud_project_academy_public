# Contrato de operaciones B05 — Alertas, seguimiento y decisión académica

**Estado:** implementado y verificado en Supabase cloud el 2026-11-23 en la rama `feat/B05-alertas-decision`, integrada desde B06 con B04, sobre el proyecto demo `academia-manager-b01`.
**Despliegue:** las migraciones B04 `20261120100000` y `20261121100000` tienen timestamp anterior a B03 `20261122090000`. En un proyecto demo que ya tiene B03, aplicar con `supabase db push --include-all` o en un proyecto limpio; un `db push` normal no las incluirá.
**Base:** B01/B02, B03, B04 y B06.
**Consumidores:** Juan (`F03`), dirección y secretaría. Docente sin acceso.
**Convenciones:** ids UUID; fechas `YYYY-MM-DD`; importes `numeric(12,2)`. Los errores se exponen como `{ code, message, details, hint }`: `code` es el SQLSTATE y `hint` el código de negocio estable. El frontend decide por `code`/`hint`, nunca por `message`.

## 1. Alcance

B05 calcula los casos de deuda y faltas de un ciclo desde datos persistidos, registra contactos de secretaría y conserva las decisiones de dirección. No crea una tabla de casos ni usa tareas programadas: el tablero se calcula con `cycle_cases`.

Decisiones aprobadas para esta implementación:

- La deuda se agrega por matrícula e incluye matrículas `pending`, `active` y `exception`. `balance` es solo el importe vencido y `total_balance` el saldo total (vencido + futuro); `F03` debe usar `balance` como deuda vencida.
- Se permiten varias decisiones por alumno/ciclo para conservar correcciones e historial. La existencia de al menos una decisión mantiene el caso de faltas como `resolved`.
- No se registra seguimiento sobre casos resueltos: responde `CASE_NOT_CLOSABLE`. El historial queda consultable.
- La decisión académica no modifica asistencias ni desaprueba automáticamente.

## 2. `cycle_cases`

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

**Roles:** `admin`/`cashier` de la academia del ciclo. Docente recibe `ACCESS_DENIED`.

### 2.1 Deuda

- Se calcula por matrícula con `charges.amount - suma(payments.amount)`.
- Solo cuentan pagos `status = 'confirmed'`; los pagos `voided` no reducen saldo.
- `balance` suma **solo cargos vencidos con saldo pendiente** (`effective_due_date < hoy` en `America/Lima`). Es el importe que `F03` muestra como deuda vencida.
- `total_balance` suma todos los cargos con saldo positivo (vencido + futuro) en un campo separado.
- `due_date` es el vencimiento vencido más antiguo con saldo.
- `overdue` es `true` en las filas de deuda, porque solo se devuelven matrículas con importe vencido.
- Para una matrícula `exception`, el cargo `registration` usa `enrollments.exception_due_date`; los cargos `monthly` conservan su fecha. Una excepción con fecha futura no genera alerta de deuda hasta su vencimiento.
- Solo se devuelve un caso de deuda si `balance > 0`; un cargo futuro sin importe vencido no aparece.
- `status = 'open'` mientras haya deuda vencida. Una deuda pagada no se devuelve.
- `absences` es `null` en filas de deuda.

### 2.2 Faltas

- Solo se consideran matrículas `active` y `exception`.
- Se cuentan las asistencias de todas las sesiones del ciclo, incluidas las sesiones históricas de otro grupo después de un traslado.
- `absent` suma 1. `late` suma 1 solo si `cycles.late_counts_as_absence = true`.
- Solo se devuelven alumnos que alcanzaron `warning_absences`.
- `requires_decision` es verdadero cuando se alcanzó `review_absences` y no existe decisión.
- Estados:
  - `needs_decision`: alcanzó `review_absences` y no hay decisión.
  - `resolved`: existe al menos una decisión, o el ciclo terminó sin alcanzar `review_absences`.
  - `open`: alcanzó el aviso, sigue vigente y no alcanzó el límite.
- `balance`, `total_balance` y `due_date` son `null` en filas de faltas.

## 3. `register_followup`

```sql
public.register_followup(
  p_student_id uuid,
  p_cycle_id uuid,
  p_channel text,   -- call | whatsapp | email | in_person
  p_note text
) returns uuid
```

- Roles: `admin`/`cashier`.
- Valida canal permitido y nota no vacía.
- Exige que el alumno tenga al menos un caso en el ciclo y que al menos uno esté abierto.
- Inserta en `followups` con academia derivada del ciclo y autor de `auth.uid()`.
- No modifica saldo, conteo de faltas ni estado del caso.
- Devuelve `followups.id`.

## 4. `register_academic_decision`

```sql
public.register_academic_decision(
  p_student_id uuid,
  p_cycle_id uuid,
  p_decision text,  -- continue | close_case | other
  p_reason text
) returns uuid
```

- Solo `admin`.
- Valida decisión permitida y motivo no vacío.
- Exige un caso de faltas del alumno en el ciclo con `absences >= review_absences`.
- Permite más de una decisión para conservar historial. Cualquier decisión mantiene el caso `resolved`.
- No borra asistencias ni cambia el conteo.
- Devuelve `academic_decisions.id`.

## 5. Errores estables

| `business_code` (`hint`) | SQLSTATE (`code`) | HTTP | Uso |
|---|---:|---:|---|
| `SESSION_REQUIRED` | `28000` | 401 | No hay JWT autenticado. |
| `ACCESS_DENIED` | `42501` | 403 | Rol no permitido o ciclo de otra academia. |
| `CYCLE_NOT_FOUND` | `22023` | 400 | Ciclo inexistente. |
| `CASE_NOT_FOUND` | `22023` | 400 | Alumno sin caso en el ciclo, o sin caso de faltas para decidir. |
| `INVALID_FOLLOWUP` | `22023` | 400 | Canal inválido o nota vacía. |
| `INVALID_DECISION` | `22023` | 400 | Decisión inválida o motivo vacío. |
| `CASE_NOT_CLOSABLE` | `23514` | 400 | Caso resuelto para seguimiento, o decisión antes del límite. |

## 6. Modelo persistente

```sql
public.followups (
  id, academy_id, student_id, cycle_id,
  channel, note, created_by, created_at
)

public.academic_decisions (
  id, academy_id, student_id, cycle_id,
  decision, reason, created_by, created_at
)
```

- FKs compuestas por academia contra `students`, `cycles` y `academies`.
- RLS: lectura para `admin`/`cashier` de la academia; sin escritura directa.
- La escritura ocurre solo por las RPC `SECURITY DEFINER`.

## 7. Pruebas

Archivo: `supabase/tests/b05_alerts_decisions.sql`.

Cubre:

- A09: aviso al alcanzar el umbral, caso `needs_decision` al llegar al límite, decisión de dirección y ausencia de desaprobación automática.
- A13: deuda pagada fuera de activos, pago anulado que restaura saldo, contacto que no borra el caso y cierre de faltas al terminar el ciclo bajo el límite.
- Excepción B06 con `exception_due_date` futura y vencida.
- Traslado B06 que conserva faltas históricas del ciclo.
- `late_counts_as_absence` verdadero y falso.
- Roles, aislamiento entre academias, RLS de lectura y bloqueo de escritura directa.
- Errores `SESSION_REQUIRED`, `ACCESS_DENIED`, `CYCLE_NOT_FOUND`, `CASE_NOT_FOUND`, `INVALID_FOLLOWUP`, `INVALID_DECISION` y `CASE_NOT_CLOSABLE`.

Comando sugerido:

```bash
npx supabase db query --remote --file supabase/tests/b05_alerts_decisions.sql --yes
```

**Resultado local 2026-11-21:** las 17 migraciones B01–B06/B05 se aplicaron desde cero en PostgreSQL 18 con un esquema Supabase simulado (`auth`/`storage`); las pruebas B01, B02, B03, B04 (3), B06 (3) y B05 pasaron. La corrección `20261123100000` se añadió después (18 migraciones en total).

**Resultado cloud 2026-11-23:** se aplicaron las migraciones pendientes B04, B06 y B05 con `supabase db push --include-all` en `academia-manager-b01` (`ufrwqsgzfhjmwcworxlz`); los objetos `followups`, `academic_decisions`, `cycle_cases`, `register_followup` y `register_academic_decision` quedaron verificados. La corrección de deuda vencida se aplicó después con `20261123100000_b05_debt_overdue_only.sql`; `b05_alerts_decisions.sql` pasó con `balance = 120`, `total_balance = 320` y sin caso de deuda para la excepción con fecha futura.
