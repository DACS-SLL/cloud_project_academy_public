# Contrato de operaciones B06 — Excepciones y traslados

**Estado real:** las 13 migraciones se aplicaron correctamente desde cero en Supabase local B06. `authorize_enrollment_exception`, `transfer_student` y `enrollment_transfers` están implementados y sus pruebas A03/A04 e integración B03+B06 pasaron localmente. No se registra validación remota ni despliegue de B06.
**Base:** esquema y permisos B01/B02, más `docs/B02_CONTRATO_OPERACIONES.md`.
**Criterios oficiales:** A03 y A04 se transcriben de la definición aprobada para esta actividad.
**Convenciones:** ids UUID; fechas límite `date` (`YYYY-MM-DD`); errores PostgREST `{ code, message, details, hint }`. El rol y la academia se derivan en la base de datos; nunca se confía en `academy_id` enviado por el cliente.

## 1. Estado del modelo existente

| Implementado en B01/B02 | Límite que B06 debe resolver |
|---|---|
| B01 revoca el `UPDATE` directo de `students.group_id`; su `transfer_student` original es `SECURITY DEFINER`, valida rol `admin` y tiene `EXECUTE` para `authenticated`. | B06 reemplaza esa lógica: ahora requiere matrícula vigente, sincroniza matrícula/alumno y conserva historial. |
| B02 define `enrollments.status` como `pending`, `active`, `exception`, `cancelled`; existe `unique (student_id, cycle_id)`. | El estado `exception` solo exige motivo y fecha por un `CHECK`; no impone por sí solo quién lo autoriza ni registra `authorized_by/authorized_at`. |
| B02 niega escrituras directas de `authenticated` en `enrollments`; RLS permite lectura a dirección y secretaría. | La mutación debe quedar detrás de RPC con autorización explícita de dirección (`admin`). |
| `b02_enrollment_guard()` verifica academia/ciclo y, al entrar en `active`/`exception` o cambiar grupo, bloquea el grupo, cuenta matrículas ocupantes y sincroniza `students.group_id`. | La función B01 no usa este conteo: bloquea el destino, cuenta `students.group_id` y no valida que el alumno tenga matrícula vigente en el ciclo destino. |
| `group_capacity()` calcula ocupación desde matrículas `active` y `exception`; `pending` no ocupa cupo. | La capacidad debe seguir calculándose desde `enrollments`, no mantener un segundo criterio basado en alumnos. |
| `create_enrollment_request()` crea cargos `registration`/`monthly` ligados a `enrollment_id`; una matrícula por alumno/ciclo. | Autorizar una excepción no debe borrar, reducir ni cancelar el cargo de inscripción impago. |

Los campos existentes para una excepción son `exception_reason`, `exception_due_date`, `authorized_by` y `authorized_at`. El cargo de inscripción sigue asociado a la matrícula y el saldo continúa disponible para seguimiento financiero. No hace falta cambiar cargos para cumplir A03.

## 2. A03 — autorización de excepción

**Criterio:** dirección autoriza una excepción con motivo y fecha límite; la excepción ocupa cupo, el alumno sigue asistiendo después del vencimiento y la inscripción impaga permanece identificable para seguimiento.

**Decisión aprobada por Fernando:** la excepción solo puede autorizarse desde una matrícula `pending`. El traslado solo moverá matrículas `active` o `exception`, dentro de la misma academia y ciclo. B06 añadirá `enrollment_transfers` y sincronizará `enrollments.group_id` con `students.group_id`.

### RPC implementada: `authorize_enrollment_exception`

```sql
public.authorize_enrollment_exception(
  p_enrollment_id uuid,
  p_reason text,
  p_due_date date
) returns uuid
```

- **Permiso:** `EXECUTE` solo para `authenticated`; exclusivamente `admin` de la academia de la matrícula puede completar la operación. `cashier` y docente reciben `ACCESS_DENIED`; un admin de otra academia y una matrícula inexistente reciben el mismo `ENROLLMENT_NOT_FOUND`. `anon` no tiene permiso de ejecución. `academy_id`, autorizador y fecha de autorización no son parámetros confiables: se derivan de la matrícula, `auth.uid()` y el reloj de la base.
- **Validación:** matrícula accesible para un admin de su misma academia y con `status = 'pending'`; motivo no nulo y no vacío tras `trim`; fecha límite obligatoria. No crear otra fila de matrícula.
- **Efecto:** escribir `status = 'exception'`, `exception_reason`, `exception_due_date`, `authorized_by = auth.uid()` y `authorized_at = now()` en una transacción. El trigger B02 valida el grupo y el cupo, e incrementa la ocupación una sola vez al pasar de `pending` a `exception`.
- **Deuda:** conservar sin cambios los cargos y pagos. La inscripción continúa identificable por el cargo `type = 'registration'` ligado a `enrollment_id`; la excepción no equivale a pago ni condonación.
- **Vencimiento:** `exception_due_date` no produce cancelación automática. La matrícula conserva `status = 'exception'`, ocupa cupo y sigue siendo elegible para asistencia después de esa fecha. B04 no debe exigir que `exception_due_date >= current_date` para registrar asistencia.
- **Retorno:** UUID de la matrícula actualizada. Llamar nuevamente sobre una matrícula `exception` devuelve `EXCEPTION_STATUS_INVALID`; no se crea una matrícula duplicada.

### Errores estables implementados

| `business_code` (`hint`) | SQLSTATE (`code`) | HTTP | Uso |
|---|---:|---:|---|
| `SESSION_REQUIRED` | `28000` | 401 | No hay sesión autenticada. |
| `ACCESS_DENIED` | `42501` | 403 | El usuario no tiene rol `admin` en ninguna academia. |
| `ENROLLMENT_NOT_FOUND` | `P0002` | 404 | Matrícula inexistente o no accesible. |
| `EXCEPTION_REASON_REQUIRED` | `22023` | 400 | Motivo vacío o nulo. |
| `EXCEPTION_DUE_DATE_REQUIRED` | `22023` | 400 | Fecha límite nula. |
| `EXCEPTION_STATUS_INVALID` | `23514` | 400 | La matrícula no está en estado `pending`. |
| `GROUP_FULL` | `23514` | 400 | El grupo no tiene vacante; conservar como referencia el rechazo de cupo del trigger B02 (`Grupo sin cupo`). |
| `ENROLLMENT_CYCLE_MISMATCH` | `23514` | 400 | El grupo asociado no coincide con el ciclo/academia de la matrícula (protección del trigger B02). |

## 3. A04 — traslado con vacante e historial

**Criterio:** el traslado a un grupo con vacante funciona y conserva historial. Si el destino está lleno, se rechaza sin cambiar ocupación ni perder datos.

### RPC implementada: reemplaza B01 y conserva la firma

```sql
public.transfer_student(
  p_student_id uuid,
  p_group_id uuid
) returns void
```

Se conserva la firma pública de B01 para no cambiar la llamada del frontend. El grupo destino identifica el ciclo; la RPC encuentra y bloquea la matrícula `active` o `exception` del alumno en ese ciclo. Si solo existe matrícula vigente en otro ciclo, devuelve `TRANSFER_CROSS_CYCLE`; si no existe una matrícula vigente, devuelve `TRANSFER_NO_ACTIVE_ENROLLMENT`. No mueve una solicitud `pending` ni crea otra matrícula. Una llamada al grupo actual es no-op sin cambiar datos ni añadir historial. La academia y el ciclo destino deben coincidir con los de la matrícula, según la aprobación de Fernando.

- **Permiso:** solo `admin` de la academia. `p_student_id` y `p_group_id` son UUID; no se acepta academia en parámetros.
- **Validación de academia/privacidad:** el alumno se resuelve solo en academias donde el actor es admin; el grupo destino se busca solo en la academia del alumno. Alumno ajeno/inexistente y grupo ajeno/inexistente producen sus respectivos errores genéricos `*_NOT_FOUND`, sin revelar recursos de otra academia.
- **Validación de ciclo:** la matrícula vigente y el grupo destino deben pertenecer al mismo ciclo. No se permite trasladar una matrícula entre ciclos; ese flujo requiere otra matrícula/operación.
- **Validación de matrícula:** localizar la única matrícula del alumno para el ciclo destino, garantizada por `unique (student_id, cycle_id)`, y exigir `active` o `exception`. Sin ella, emitir `TRANSFER_NO_ACTIVE_ENROLLMENT`.
- **Actualización atómica:** cambiar `enrollments.group_id`; el trigger B02 valida el destino y sincroniza `students.group_id` dentro de la misma transacción. El RPC verifica que ambos valores coincidan antes de terminar. Si falla la sincronización, se aborta con `TRANSFER_SYNC_FAILED`. No actualizar solo `students.group_id`.
- **Cupo:** usar el trigger B02, que bloquea la fila del grupo destino y cuenta `active`/`exception` excluyendo la matrícula trasladada. No volver a calcular con `students.group_id` ni modificar capacidad/ocupación manualmente.
- **Historial:** insertar la auditoría de traslado en la misma transacción. Si falla grupo lleno, autorización, validación o escritura del historial, PostgreSQL revierte tanto la matrícula como el grupo del alumno y no conserva un evento parcial.

### Tabla implementada: `enrollment_transfers`

Tabla append-only para conservar cada movimiento, no reemplaza el estado actual en `enrollments`.

| Columna | Propósito |
|---|---|
| `id uuid` PK | Identificador del movimiento. |
| `academy_id uuid` | Tenant del traslado. |
| `enrollment_id uuid` | Matrícula afectada. |
| `student_id uuid` | Alumno afectado, para auditoría/consulta. |
| `cycle_id uuid` | Ciclo inmutable del movimiento. |
| `from_group_id uuid` | Grupo antes del traslado. |
| `to_group_id uuid` | Grupo destino. |
| `transferred_by uuid` | Admin obtenido de `auth.uid()`. |
| `transferred_at timestamptz` | Hora de la base de datos. |

Las FK compuestas con `(id, academy_id)` de alumnos, grupos, ciclos y matrículas impiden cruces de academia. `ON DELETE RESTRICT` conserva referencias de auditoría. La tabla tiene RLS: `admin` y `cashier` pueden leer su academia, mientras `authenticated` no recibe permisos `INSERT`/`UPDATE`/`DELETE`; solo la RPC escribe como `SECURITY DEFINER`. No se agregó razón de traslado porque no está aprobada.

### Errores estables implementados

| `business_code` (`hint`) | SQLSTATE (`code`) | HTTP | Uso |
|---|---:|---:|---|
| `SESSION_REQUIRED` | `28000` | 401 | No hay sesión autenticada. |
| `ACCESS_DENIED` | `42501` | 403 | El usuario no tiene rol `admin` en ninguna academia. |
| `STUDENT_NOT_FOUND` | `22023` | 400 | Alumno inexistente/no accesible; conserva el SQLSTATE de B02. |
| `GROUP_NOT_FOUND` | `22023` | 400 | Grupo destino inexistente/no accesible; conserva el SQLSTATE de B02 y su prueba de grupo ajeno. |
| `TRANSFER_CROSS_CYCLE` | `23514` | 400 | El ciclo de la matrícula difiere del ciclo destino. |
| `TRANSFER_NO_ACTIVE_ENROLLMENT` | `23514` | 400 | No existe matrícula `active`/`exception` del alumno en el ciclo destino. |
| `TRANSFER_GROUP_FULL` | `23514` | 400 | El trigger B02 rechaza la vacante; conservar el mensaje B02 `Grupo sin cupo` o mapearlo mediante `hint`. |
| `TRANSFER_SYNC_FAILED` | `23514` | 400 | No se verificó la sincronización del grupo en `students`; toda la transacción se revierte. |

## 4. Estrategia de bloqueo transaccional

1. Validar sesión y rol `admin`; resolver datos del alumno y destino dentro de su academia.
2. Bloquear la fila de matrícula elegible con `FOR UPDATE`. Esto serializa dos traslados simultáneos del mismo alumno/ciclo y una autorización que cambie el estado de esa misma matrícula.
3. Actualizar `enrollments.group_id`. El trigger B02 toma `FOR UPDATE` sobre el grupo destino, comprueba academia/ciclo, cuenta ocupación actual y rechaza si `occupied >= capacity`; luego sincroniza `students.group_id`.
4. Escribir `enrollment_transfers` y comprobar los dos grupos actuales dentro de la misma transacción. El bloqueo del grupo destino serializa llegadas concurrentes y la restricción única de matrícula evita duplicados por alumno/ciclo.
5. Ante cualquier error, dejar que la excepción aborte la RPC completa; no capturarla y continuar con una actualización parcial.

Mantener el orden matrícula → grupo destino → alumno/historial compatible con el trigger B02, que al actualizar una matrícula obtiene primero el bloqueo de grupo y después sincroniza `students`. No contar manualmente ni prebloquear/actualizar `students` por separado antes de disparar el guard, para evitar criterios divergentes y aumentar el riesgo de interbloqueo.

## 5. Compatibilidad y pruebas B01/B02

- Mantener `create_enrollment_request()` sin cambios: sigue creando `pending`, cargos separados y una sola matrícula por alumno/ciclo.
- Mantener el trigger y `group_capacity()` de B02 como fuente de verdad: solo `active`/`exception` ocupan cupo; `pending` no.
- Mantener las escrituras de matrícula detrás de RPC; no conceder `INSERT`/`UPDATE` directo sobre `enrollments` a `authenticated`.
- Conservar la firma `transfer_student(uuid, uuid) returns void` y sus permisos de ejecución. La autorización interna sigue siendo solo `admin`.
- Ejecutar las pruebas B01 y B02 sin alterar sus criterios: aislamiento por academia, bloqueo de traslado para `cashier`, transferencia admin al grupo libre, rechazo de destino lleno, activación/exception con cupo, grupo/ciclo válido y matrícula duplicada.
- **Compatibilidad de fixture:** B01 se creó antes de `enrollments`, por lo que sus escenarios de traslado se deben interpretar con el esquema de la prueba integrada actual. La regresión `b01_rls.sql` pasó en el esquema B01/B02/B03/B06 local reportado; no se deben relajar los requisitos B06 de matrícula activa/excepcional.
- B02 también conserva el caso de trigger/cupo con `UPDATE` directo ejecutado por el propietario de la prueba. A03 prueba por separado la autorización mediante la RPC real.

## 6. Pruebas de aceptación A03 y A04

### A03 — excepción

- `admin` autoriza solo una matrícula `pending` con motivo y fecha; persisten estado, autor y hora; motivos vacíos y fecha nula devuelven los errores definidos.
- `cashier`, docente, anon y admin de otra academia son rechazados; la matrícula no cambia.
- La excepción incrementa la ocupación exactamente en uno y el trigger rechaza el cambio si el grupo está lleno; ante rechazo no se modifica matrícula, alumno ni historial.
- Se conservan el cargo de inscripción y su saldo impago; la matrícula permanece localizable por `enrollment_id` para seguimiento.
- Pasada `exception_due_date`, el estado sigue siendo `exception`, sigue contando para cupo y la validación académica permite asistir. La fecha límite por sí sola no cancela, suspende ni transforma la matrícula.

### A04 — traslado

- `admin` traslada una matrícula vigente a un grupo con vacante del mismo ciclo/academia; cambian juntos `enrollments.group_id` y `students.group_id`, se añade exactamente un evento con origen/destino/actor/hora y la ocupación origen/destino queda correcta.
- Grupo destino lleno devuelve `TRANSFER_GROUP_FULL`; comprobar que matrícula, alumno, ocupación de ambos grupos e historial quedan iguales a antes de la llamada.
- Rechazar traslado por `cashier`/docente/otra academia, ciclo distinto, matrícula pending/cancelled o matrícula inexistente; ningún caso crea historia ni altera cupos. Los identificadores ajenos quedan ocultos como no encontrados.
- Repetir una llamada al grupo actual no crea evento ni consume cupo. Dos traslados concurrentes hacia la última vacante no pueden admitir ambos: uno obtiene el asiento y el otro falla por cupo.
- Comprobar la restricción `unique (student_id, cycle_id)` y que el traslado actualiza la matrícula existente en lugar de insertar otra.

## 7. Decisiones pendientes de Fernando

1. **Renovación:** ¿`authorize_enrollment_exception` puede renovar una excepción vencida? Si sí, ¿se conserva cada renovación en una tabla de eventos además de los valores actuales en `enrollments`?
2. **Fecha límite:** la RPC acepta cualquier fecha no nula, incluso pasada. Confirmar si se deben rechazar fechas pasadas; la asistencia después del vencimiento sí está fijada por A03.
3. **Varios ciclos:** B02 permite una matrícula por alumno/ciclo, potencialmente en varios ciclos simultáneos, pero `students.group_id` solo representa un grupo. Confirmar si puede haber varias matrículas vigentes y qué grupo debe mostrar `students.group_id`.
4. **Historial y asistencia:** decidir cómo B04 validará grupo/matrícula en la fecha de la sesión. `attendance` conserva `student_id`, no `enrollment_id`; al cambiar `enrollments.group_id`, asistencia retroactiva al grupo anterior requiere consultar `enrollment_transfers`.
5. **Razón del traslado:** confirmar si debe ser obligatoria y guardarse en `enrollment_transfers`.
6. **Capacidad y ciclos:** decidir si se bloquean reducciones de `groups.capacity` por debajo de la ocupación y cambios de `groups.cycle_id` cuando hay matrículas; las restricciones actuales no los impiden integralmente.
## 8. Estado de validación

Los resultados locales y comandos reproducibles están en [`B06_PRUEBAS.md`](B06_PRUEBAS.md). La verificación remota queda pendiente; los resultados locales no se presentan como evidencia de un proyecto remoto ni de un despliegue.
