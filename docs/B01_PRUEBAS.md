# B01 — Matriz de pruebas de roles, aislamiento y Storage

**Responsable:** Fernando Perez del Castillo

**Estado:** migraciones aplicadas, hardening de escrituras y pruebas ejecutadas en Supabase cloud; pendiente revisión del PR y repetición en `Q01`.

**Proyecto de prueba:** `academia-manager-b01` (`ufrwqsgzfhjmwcworxlz`), región `sa-east-1`. Proyecto dedicado a la demo; no contiene datos reales.

**Alcance:** base mínima de seguridad de B01. Las pruebas completas `A11`/`A12` se repiten en `Q01` cuando existan los módulos de B02–B04.

## Evidencia ejecutable

| Caso | Acción | Resultado esperado | Script |
|---|---|---|---|
| `A11` | Iniciar sesión como docente y consultar `guardians`, `charges`, `payments` y vouchers por API/Storage. | Respuesta vacía o denegada; nunca datos de la academia. | `scripts/verify-b01-isolation.mjs` |
| `A12` | Iniciar sesión como dirección/secretaría de A y consultar datos o vouchers de B cambiando IDs. | Sin filas y sin objeto descargable. | `scripts/verify-b01-isolation.mjs` |
| Hardening | Intentar cambiar `students.group_id`, crear alumnos ya asignados, borrar alumnos, actualizar/eliminar cargos y trasladar sin rol dirección. | Todas las escrituras directas se deniegan; el traslado autorizado valida cupo. | `scripts/verify-b01-isolation.mjs`, `supabase/tests/b01_rls.sql` |
| RLS local | Ejecutar fixtures de dos academias y tres roles dentro de una transacción. | Todas las aserciones pasan y la transacción termina en `ROLLBACK`. | `supabase/tests/b01_rls.sql` |

## Registro de ejecución

| Fecha | Entorno | Comando | Resultado | Evidencia |
|---|---|---|---|---|
| 2026-11-18 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/seed-b01-demo.mjs` | 2 academias, 6 usuarios y vouchers demo creados. | Salida de consola del seed. |
| 2026-11-18 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db push --remote --yes` | `20261118090500_b01_hardening.sql` y `20261118090600_b01_student_writes.sql` aplicadas. | Salida del CLI. |
| 2026-11-18 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b01-isolation.mjs` | `40/40 comprobaciones OK`. | Salida de consola con `PASS` de `A11`/`A12` y escrituras denegadas. |
| 2026-11-18 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db query --remote --file supabase/tests/b01_rls.sql --yes` | `B01 RLS: todas las comprobaciones pasaron`. | Resultado del SQL Editor/CLI, incluido traslado con cupo. |
| 2026-11-18 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `POST /auth/v1/signup` con la clave anónima | `422`; registro público desactivado. | Respuesta HTTP sin usuario creado. |

## Decisiones verificadas

- El rol y la academia se leen de `memberships`, no de `user_metadata`.
- Un docente no tiene políticas sobre apoderados, cargos ni pagos.
- Un docente solo ve alumnos de grupos asignados y asistencia de sus sesiones.
- Los vouchers viven en un bucket privado con ruta `{academy_id}/{payment_id}/{archivo}`.
- El bucket `vouchers` quedó con `public = false`; el seed creó 12 tablas en `public` y 6 usuarios de Auth.
- No hay borrado de vouchers para `authenticated`.
- No hay `INSERT` directo de pagos, sesiones o asistencia; se implementará por RPC en B03/B04.
- `students.group_id` no se puede cambiar con `UPDATE` directo, ni siquiera como dirección. El traslado usa `transfer_student()`, que exige rol `admin`, matrícula activa/excepcional en el ciclo destino, valida academia y cupo, y sincroniza matrícula y alumno.
- Un alumno solo puede crearse por `INSERT` directo sin `group_id`; la columna no está concedida para inserción y la política exige `group_id is null`. La asignación inicial ocurre por el RPC de traslado.
- El borrado directo de alumnos está revocado para `authenticated`; una baja administrativa con trazabilidad queda para B02.
- `charges` no admite `UPDATE` ni `DELETE` directo para `authenticated`; las correcciones con saldo y trazabilidad quedan para RPC de B02/B03.
- El registro público y los sign-ins anónimos quedaron desactivados en el proyecto de prueba.

## Riesgos y pendientes

- Mantener el proyecto demo activo para `Q01` o documentar su pausa/eliminación.
- Repetir `A11`/`A12` en `Q01` con el frontend y todas las tablas de negocio.
- Implementar en B03 las correcciones de cargos y en B06 el historial de traslados con trazabilidad.
- Definir en B03 la limpieza de un voucher subido cuando la RPC rechaza el pago.
- Revisar `A14` con Yony cuando la aplicación esté publicada.
