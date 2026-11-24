# B06 — implementación y pruebas

## Estado y alcance de la evidencia

Las 13 migraciones se aplicaron correctamente desde cero en Supabase local B06. Pasaron las pruebas A03, A04, las regresiones B01/B02/B03, la concurrencia real y la integración B03+B06. Todas las pruebas SQL finalizaron con `ROLLBACK`; la prueba shell limpia sus fixtures al terminar.

Esta evidencia corresponde a la instancia local indicada para B06. No se ha registrado aquí una ejecución contra Supabase remoto ni un despliegue; esas validaciones siguen pendientes.

## RPC definitivas

| RPC | Firma | Permiso funcional | Resultado |
|---|---|---|---|
| `authorize_enrollment_exception` | `public.authorize_enrollment_exception(p_enrollment_id uuid, p_reason text, p_due_date date) returns uuid` | Solo `admin` de la academia de la matrícula; `EXECUTE` concedido a `authenticated`. | Cambia una matrícula `pending` a `exception`, escribe motivo, fecha límite, autor y hora. La excepción ocupa cupo y no borra ni modifica cargos/pagos. |
| `transfer_student` | `public.transfer_student(p_student_id uuid, p_group_id uuid) returns void` | Solo `admin` de la academia del alumno; `EXECUTE` concedido a `authenticated`. | Traslada una matrícula `active`/`exception` al mismo ciclo, sincroniza matrícula/alumno e inserta historial atómicamente. |

Ambas funciones son `SECURITY DEFINER`, fijan `search_path` vacío y derivan usuario/academia de la sesión y los datos en base. El cliente no aporta un `academy_id` confiable. La tabla `enrollment_transfers` es append-only para `authenticated`: admin y cashier pueden leer filas de su academia mediante RLS, sin permisos directos de escritura.

### Códigos de error estables

El contrato PostgREST expone el código de negocio en `hint`.

| RPC | `hint` | SQLSTATE | Significado |
|---|---|---:|---|
| Ambas | `SESSION_REQUIRED` | `28000` | Falta sesión autenticada. |
| Ambas | `ACCESS_DENIED` | `42501` | Rol insuficiente para ejecutar la operación. |
| Excepción | `ENROLLMENT_NOT_FOUND` | `P0002` | Matrícula inexistente o fuera del alcance del admin. |
| Excepción | `EXCEPTION_STATUS_INVALID` | `23514` | La matrícula no está `pending`. |
| Excepción | `EXCEPTION_REASON_REQUIRED` | `22023` | Motivo nulo o vacío. |
| Excepción | `EXCEPTION_DUE_DATE_REQUIRED` | `22023` | Fecha límite nula. |
| Excepción | `GROUP_FULL` | `23514` | El grupo no tiene vacante para autorizarla. |
| Excepción | `ENROLLMENT_CYCLE_MISMATCH` | `23514` | Academia/ciclo de grupo y matrícula no coinciden. |
| Traslado | `STUDENT_NOT_FOUND` | `22023` | Alumno inexistente o no accesible. |
| Traslado | `GROUP_NOT_FOUND` | `22023` | Grupo inexistente o fuera de la academia. |
| Traslado | `TRANSFER_CROSS_CYCLE` | `23514` | El destino pertenece a otro ciclo. |
| Traslado | `TRANSFER_NO_ACTIVE_ENROLLMENT` | `23514` | No hay matrícula vigente trasladable en el ciclo destino. |
| Traslado | `TRANSFER_GROUP_FULL` | `23514` | El destino no tiene vacante. |
| Traslado | `TRANSFER_SYNC_FAILED` | `23514` | No se pudo verificar la sincronización; la transacción se revierte. |

## Criterios A03/A04

### A03 — excepción

- Solo se autoriza desde `pending`, con motivo no vacío y fecha límite.
- Persiste `exception`, `exception_reason`, `exception_due_date`, `authorized_by` y `authorized_at`; no crea otra matrícula.
- El trigger de B02 comprueba academia, ciclo y capacidad, y la excepción cuenta como ocupante.
- Los cargos y pagos permanecen relacionados con la matrícula. La excepción no liquida ni condona la inscripción impaga.
- La fecha límite no causa cancelación automática; la matrícula excepcional continúa ocupando cupo.

### A04 — traslado

- Solo mueve matrículas `active`/`exception` dentro de la misma academia y ciclo.
- El trigger B02 bloquea el grupo destino, comprueba cupo y sincroniza `students.group_id` con `enrollments.group_id`.
- Inserta `enrollment_transfers` en la misma transacción, con academia, matrícula, alumno, ciclo, origen, destino, admin y hora.
- Grupo lleno, fallos de validación o de historial revierten los cambios; una llamada al grupo actual es no-op sin evento.
- Dos traslados concurrentes a la última vacante no pueden ocupar ambos el asiento.

## Comandos reproducibles en local

Configura `SUPABASE_DB_URL` hacia la base local B06. Ejecuta desde la raíz, con las migraciones aplicadas:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b06_authorize_enrollment_exception.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b06_transfer_student.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b01_rls.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b02_enrollment.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b03_payments.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/b06_payment_exception_integration.sql
bash scripts/verify-b06-concurrency.sh
```

Las seis pruebas SQL deben terminar en `ROLLBACK`. La prueba de concurrencia usa únicamente el contenedor local `supabase_db_cloud_project_academy_b06_test` y dos procesos `psql` independientes; aborta si ese contenedor falta o no está ejecutándose.

## Resultados locales confirmados

| Verificación | Resultado reportado |
|---|---|
| Aplicación desde cero | 13 migraciones aplicadas correctamente. |
| `b06_authorize_enrollment_exception.sql` (A03) | OK; `ROLLBACK`. |
| `b06_transfer_student.sql` (A04) | OK; `ROLLBACK`. |
| `b01_rls.sql` | OK; `ROLLBACK`. |
| `b02_enrollment.sql` | OK; `ROLLBACK`. |
| `b03_payments.sql` | OK; `ROLLBACK`. |
| `verify-b06-concurrency.sh` | OK: una conexión `SUCCESS`, otra `TRANSFER_GROUP_FULL`, ambas `COMMIT`; sin sobrecupo, sincronización correcta e historial único. La limpieza shell elimina fixtures. |
| `b06_payment_exception_integration.sql` | OK; alcanzó `DO` y terminó con `ROLLBACK`, según la evidencia reportada. |

La prueba integrada recorre `pending → exception → active → traslado → exception`: crea solicitud/cargos, autoriza la excepción, registra inscripción con voucher, traslada y anula el pago. Verifica deuda, cupo, datos de autorización, sincronización alumno/matrícula, relación cargo/pago e historial conservado.

## Validación remota pendiente y limitaciones conocidas

- No se afirma que las 13 migraciones ni estas pruebas se hayan aplicado en un proyecto Supabase remoto; hacerlo requiere una validación separada y autorizada.
- La prueba SQL integrada usa fixtures de base y un objeto ficticio en `storage.objects` dentro de la transacción; no carga un archivo real ni prueba la interfaz/flujo de subida del cliente.
- Las decisiones de producto abiertas en el contrato siguen pendientes: renovación de excepciones, rechazo de fechas límite pasadas, comportamiento con varias matrículas vigentes de distintos ciclos y consulta de asistencia histórica tras traslados.
- El historial conserva origen/destino y actor, pero no un motivo de traslado porque ese campo no forma parte del contrato aprobado.
