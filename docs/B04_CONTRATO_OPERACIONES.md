# Contrato de operaciones B04 — Sesiones y asistencia

**Estado:** `create_class_session` y `record_attendance` están implementadas en las migraciones B04; `20261122100000_b04_class_session_uniqueness.sql` agrega la restricción contra sesiones duplicadas y traduce el conflicto a `SESSION_DUPLICATE` (`23505`). La aceptación final de A08 y A10 sigue pendiente.
**Base:** B01/B02 implementados. La zona `America/Lima` queda documentada como regla propuesta para convertir el inicio de sesión a fecha civil.
**Convenciones:** UUID para ids; `starts_at` es `timestamptz` ISO-8601; importes no aplican. Los errores se exponen como `{ code, message, details, hint }`; el frontend debe decidir por `code`/`hint`, no por texto libre.

## 1. Objetivo y alcance

B04 propone crear sesiones de clase para un grupo y curso, y registrar la asistencia de alumnos matriculados en el grupo/ciclo correspondiente. La escritura debe ser transaccional y realizarse mediante RPC autenticadas. El alcance utiliza tenancy, roles, asignaciones docentes y RLS de B01, y ciclos, grupos y estados de matrícula de B02.

| Estado | Elementos |
|---|---|
| **Implementado en B01/B02** | `class_sessions` y `attendance`; estados `present`, `absent`, `late`; lectura RLS para dirección/secretaría y docente de la sesión; sin escritura directa autenticada; funciones de autorización; `cycles.warning_absences`, `review_absences` y `late_counts_as_absence`; `groups.cycle_id`; `enrollments` con estados `pending`, `active`, `exception`, `cancelled`; unicidad de asistencia por `(session_id, student_id)`. |
| **Implementado en código B04 (pendiente de aplicar)** | `create_class_session`: rol docente en la academia, asignación exacta docente/grupo/curso, academia común, ciclo y fecha Lima; el docente se obtiene de `auth.uid()`. Permiso `EXECUTE` solo para `authenticated`. |
| **Implementado en código B04 (pendiente de aplicar)** | `record_attendance`: solo el docente de la sesión, con rol docente y asignación exacta; validación de matrícula activa/excepcional, lote atómico, duplicados y contadores/umbrales. |
| **Aprobado por Fernando** | Mantener provisionalmente `attendance.student_id`; esta decisión no agrega `enrollment_id` y conserva las consecuencias históricas descritas abajo. |
| **Pendiente de aprobación** | Ventana para registrar/corregir asistencia retroactiva y política histórica de traslados. La política de fechas de sesión usa `America/Lima`; confirmar si debe seguir fija o configurarse por academia. |

Fuera de alcance: pagos, activación o autorización de matrículas, traslados y cambios de cupo. B02 sincroniza `students.group_id` cuando la matrícula se activa o pasa a excepción; el traslado existente de B01 no actualiza `enrollments` y requiere resolución en B06.

## 2. `create_class_session` (implementada en migración B04, pendiente de aplicar)

```sql
public.create_class_session(
  p_group_id uuid,
  p_subject_id uuid,
  p_starts_at timestamptz
) returns uuid
```

**Parámetros:** grupo, curso y fecha/hora de inicio. No se acepta `academy_id` ni `teacher_id` del cliente como autoridad; la academia se deriva del grupo y el docente se toma de `auth.uid()`.

**Autorización:** exige usuario autenticado con rol `teacher` en la academia derivada del grupo, y una fila exacta en `teacher_assignments` para ese usuario, grupo y curso. `admin` y `cashier` no pueden usar esta RPC. Grupo y curso deben pertenecer a la misma academia. No basta con estar asignado al grupo en otro curso.

**Validaciones:** sesión autenticada; grupo/curso existentes; asignación válida; fecha de `p_starts_at` dentro de los límites inclusivos del ciclo del grupo. Se convierte el instante con `AT TIME ZONE 'America/Lima'`; la zona es una regla fija propuesta para este contrato, no una zona configurable por academia.

**Resultado:** UUID de `class_sessions.id` creado. La combinación `(academy_id, group_id, subject_id, starts_at)` es única por un índice PostgreSQL; los reintentos exactos no crean otra fila. La restricción resuelve también llamadas concurrentes. Una violación devuelve `23505` / `SESSION_DUPLICATE`.

La migración `20261122100000_b04_class_session_uniqueness.sql` agrega el índice y reemplaza la RPC sin cambiar su firma, autorización ni permisos. No elimina sesiones duplicadas preexistentes; si las hubiera, deben identificarse y resolverse explícitamente antes de aplicar la migración.

**Errores de esta RPC:** `SESSION_REQUIRED` (`28000`), `ACCESS_DENIED` (`42501`, rol/academia/asignación o recurso no autorizado), `INVALID_START_TIME` (`22023`, nulo o instante no finito), `SESSION_OUTSIDE_CYCLE` (`23514`) y `SESSION_DUPLICATE` (`23505`). Para no revelar existencia, grupo inexistente/ajeno, curso inexistente/ajeno y asignación ausente devuelven el mismo SQLSTATE, `hint` y mensaje de acceso denegado. `business_code` se envía en `hint`.

## 3. `record_attendance` (implementada en migración B04, pendiente de aplicar)

```sql
public.record_attendance(
  p_session_id uuid,
  p_records jsonb
) returns table (
  student_id uuid,
  status text,
  absences_counted integer,
  warning_active boolean,
  review_active boolean
)
```

`p_records` será un arreglo JSON no vacío, con exactamente un objeto por alumno:

```json
[
  {"student_id":"00000000-0000-0000-0000-000000000001","status":"present"},
  {"student_id":"00000000-0000-0000-0000-000000000002","status":"late"}
]
```

`student_id` debe ser UUID y `status` uno de `present`, `absent`, `late`. Se rechaza el lote completo si un elemento es inválido, se repite un alumno dentro del lote, hay una asistencia previa para esa sesión/alumno, o falla cualquier validación. Retorna una fila por alumno una vez confirmado el lote; los contadores son del ciclo asociado a la sesión, incluyendo el lote recién guardado.

**Autorización:** exclusivamente el docente registrado en `class_sessions.teacher_id`, con rol `teacher` en la academia y una asignación exacta actual en `teacher_assignments` para la academia, grupo y curso de la sesión. `admin`, `cashier` y otros docentes son rechazados. La búsqueda de sesión incluye estos predicados de autorización; una sesión inexistente, ajena o no asignada devuelve el mismo `42501` / `ACCESS_DENIED` y mensaje genérico. No acepta academia, ciclo ni docente desde el cliente.

**Matrícula requerida:** cada alumno debe tener una fila `enrollments` en la misma academia, ciclo y grupo de la sesión, con `status IN ('active','exception')`. `pending` y `cancelled` no son elegibles. La matrícula `exception` es elegible igual que `active`, pues B02 la considera vigente y ocupa cupo; sus condiciones de pago no alteran asistencia. No validar únicamente contra `students.group_id`, porque puede cambiar tras un traslado.

**Duplicados:** B01 ya define `unique (session_id, student_id)`. La RPC rechaza alumnos repetidos en el JSON y asistencias ya registradas con `ATTENDANCE_DUPLICATE`; la restricción única permanece como defensa ante concurrencia. Se validan todas las filas antes de insertar. Una violación única concurrente también se traduce al error estable. El lote es todo-o-nada; la operación no actualiza una asistencia existente.

**Atomicidad y concurrencia:** todos los alumnos se validan antes de insertar; ante error, la llamada falla y no persiste ninguna fila del lote. Los alumnos se bloquean por UUID ascendente para serializar registros concurrentes que comparten alumnos y reducir interbloqueos.

## 4. Errores estables

| `business_code` (`hint`) | SQLSTATE (`code`) | HTTP | Uso |
|---|---:|---:|---|
| `SESSION_REQUIRED` | `28000` | 401 | No hay JWT autenticado. |
| `ACCESS_DENIED` | `42501` | 403 | Rol no permitido, sesión inexistente/ajena/no asignada o docente sin asignación requerida. |
| `GROUP_NOT_FOUND` | `P0002` | 404 | Recurso propuesto para consultas futuras; `create_class_session` usa `ACCESS_DENIED` de forma uniforme. |
| `SUBJECT_NOT_FOUND` | `P0002` | 404 | Recurso propuesto para consultas futuras; `create_class_session` usa `ACCESS_DENIED` de forma uniforme. |
| `INVALID_START_TIME` | `22023` | 400 | El instante de inicio es nulo o no finito. |
| `SESSION_DUPLICATE` | `23505` | 409 | Ya existe una sesión con la misma academia, grupo, curso e instante. |
| `SESSION_OUTSIDE_CYCLE` | `23514` | 400 | Inicio de sesión fuera del ciclo del grupo. |
| `INVALID_ATTENDANCE_BATCH` | `22023` | 400 | Arreglo vacío/mal formado, status inválido o UUID inválido. |
| `ATTENDANCE_DUPLICATE` | `23505` | 409 | Alumno repetido en el lote o registro ya existente para la sesión. |
| `STUDENT_NOT_FOUND` | `P0002` | 404 | Alumno inexistente o de otra academia. |
| `ENROLLMENT_NOT_ACTIVE` | `23514` | 400 | No hay matrícula `active`/`exception` coincidente en academia, grupo y ciclo. |

Para ambas RPC, los códigos se emiten mediante `SQLSTATE` y `hint` en sus migraciones B04. Mantener `message` breve y estable; `hint` lleva el `business_code` para conservar SQLSTATE interoperable.

## 5. Cómputo de faltas y aviso (A08)

Para cada asistencia del ciclo, el aporte a faltas será:

```text
absent = 1
late   = 1 si cycles.late_counts_as_absence = true; en otro caso 0
present = 0
```

El total se calcula por alumno y ciclo; `warning_active` se activa cuando el total alcanza o supera `cycles.warning_absences`, y `review_active` cuando alcanza o supera `cycles.review_absences`. Estos campos reportan umbrales configurados por B02; no sustituyen una decisión académica. El conteo debe incluir los registros del lote una sola vez y leer la configuración del ciclo de la sesión.

**Prueba local aprobada para A08:** con `warning_absences = 10`, al guardar la décima falta contabilizable el resultado informa `warning_active = true`. Una tardanza contribuye si `late_counts_as_absence = true` y no contribuye si es `false`; las pruebas SQL locales cubren ambos valores y `review_active` al alcanzar `review_absences`. Esto no constituye aceptación final de A08, que queda pendiente.

## 6. Casos A10

Las pruebas SQL locales de los casos descritos abajo están aprobadas; la aceptación final de A10 queda pendiente.

- **Asistencia duplicada:** una segunda inserción del mismo `student_id` en `session_id` se rechaza con `23505` / `ATTENDANCE_DUPLICATE`; la primera fila permanece intacta.
- **Sesión de grupo no asignado:** un docente que no tenga asignación para el grupo **y curso** de la sesión no puede crearla ni registrar asistencia; se rechaza con `42501` / `ACCESS_DENIED`. La sesión no queda creada y el lote no escribe filas.

La creación rechaza grupos/cursos no asignados; `record_attendance` rechaza al docente que no sea dueño/asignado de la sesión. La prueba `b04_record_attendance.sql` cubre accesos indebidos, duplicidad, matrícula `exception` y rollback de un lote inválido.

## 7. Historial y traslados

**Decisión aprobada por Fernando:** conservar `attendance.student_id` tal como está en B01, de manera provisional. La tabla ya referencia alumno y sesión, pero no matrícula. La futura RPC debe validar la matrícula elegible que coincida con el grupo/ciclo de la sesión al registrar.

Consecuencias y control: la asistencia conserva el alumno y la sesión histórica, y las faltas se cuentan uniendo asistencia → sesión → grupo/ciclo. No se usa el grupo actual de `students`. La matrícula coincidente se valida al momento de registrar, pero su `enrollment_id` no queda guardado en `attendance`. La prueba local `supabase/tests/b04_attendance_after_transfer.sql` usa `transfer_student` autenticado como admin y comprueba dos faltas en el grupo origen, sincronización de `enrollments.group_id`/`students.group_id`, persistencia de esas faltas y acumulado tres después de una nueva falta en el destino. También comprueba que el docente no asignado al destino recibe `ACCESS_DENIED`. Esta evidencia local no es la prueba definitiva: debe repetirse después de integrar B06 para confirmar el comportamiento con el historial de traslados integrado.

**Limitación retroactiva cubierta por la prueba:** una nueva asistencia para una sesión antigua del grupo origen debe rechazarse con `ENROLLMENT_NOT_ACTIVE`, porque `record_attendance` exige que la matrícula actual coincida con el grupo de esa sesión. Las asistencias ya registradas no se borran y siguen contando por ciclo. Para permitir registrar faltas retroactivas en el grupo anterior, la validación debe consultar `enrollment_transfers` en la fecha de la sesión o conservar una relación histórica de matrícula. La lectura RLS de docente sigue ligada a asignaciones vigentes y puede limitar la visibilidad del historial después de un traslado.

## 8. Decisiones pendientes de Fernando

1. Confirmar si a futuro se cambia a `enrollment_id` o se almacenan ambos con integridad; `student_id` sigue siendo la decisión provisional aprobada.
2. Definir con B06 cómo conservar el derecho a registrar asistencia retroactiva en sesiones del grupo anterior si se traslada/sincroniza `enrollments.group_id`.
3. Confirmar si el docente puede crear sesiones retroactivas/futuras y el flujo de corrección; `record_attendance` no actualiza registros existentes.
4. Confirmar si `America/Lima` debe permanecer como regla fija para fechas de sesión o convertirse en configuración por academia.
5. La combinación `(academy_id, group_id, subject_id, starts_at)` ya tiene restricción `UNIQUE` mediante `class_sessions_academy_group_subject_starts_at_uidx`. Un intento duplicado se rechaza con SQLSTATE `23505` y `SESSION_DUPLICATE`; esta decisión ya no está pendiente.
