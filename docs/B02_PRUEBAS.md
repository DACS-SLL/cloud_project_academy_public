# B02 - Ciclos, cupos, matrícula y cargos

**Tarea:** `B02` · **Responsable:** Fernando · **Dependencia:** `B01`
**Alcance:** persistir ciclos, grupos con turno y capacidad, cursos/docentes, alumnos/apoderados, precio fijo del ciclo, inscripción y mensualidades. Una solicitud pendiente no ocupa cupo; una matrícula activa o excepcional sí.

## Criterios de aceptación

| Prueba | Resultado esperado | Evidencia |
|---|---|---|
| `A01` | Ciclo, grupo con cupo, curso y docente persisten; alumno con inscripción y mensualidades mantiene precio individual. | `scripts/verify-b02-enrollment.mjs` |
| `A02` (base) | Una solicitud sin pago ni excepción queda pendiente y no ocupa cupo; no se admite una segunda matrícula del mismo alumno/ciclo. | Verificación API + `supabase/tests/b02_enrollment.sql` |
| Cupo | Activar una matrícula en un grupo lleno se rechaza; activa y excepción cuentan para el cupo. | `supabase/tests/b02_enrollment.sql` |
| Invariantes | No se baja capacidad bajo ocupados ni se cambia ciclo/academia con matrículas; traslado sincroniza matrícula y alumno. | `supabase/tests/b02_enrollment.sql` + `scripts/verify-b02-enrollment.mjs` |
| Errores | Los errores B02 devuelven `hint` de negocio, no solo texto. | API: `ENROLLMENT_DUPLICATE`, `INVALID_AMOUNT`, `ACCESS_DENIED`, `GROUP_CAPACITY_BELOW_OCCUPIED`, `GROUP_CYCLE_HAS_ENROLLMENTS`, `GROUP_NOT_FOUND`; SQL: `TRANSFER_NO_ACTIVE_ENROLLMENT`, `TRANSFER_GROUP_FULL` |
| Regresión B01 | Roles, aislamiento y escrituras bloqueadas siguen funcionando. | `40/40` en `scripts/verify-b01-isolation.mjs` |

## Modelo implementado

- `cycles`: fechas, grado, umbral de aviso, límite de revisión y regla de tardanza por academia.
- `groups.cycle_id`: cada grupo pertenece a un ciclo de su academia.
- `enrollments`: alumno, ciclo, grupo, estado (`pending`, `active`, `exception`, `cancelled`), precio de inscripción y mensualidad acordados, motivo/fecha de excepción y autor.
- `charges.enrollment_id`: cada cargo pertenece a una matrícula; inscripción y mensualidades son filas separadas.
- Unicidad `(student_id, cycle_id)`: impide una segunda matrícula del mismo alumno en el ciclo.
- `create_enrollment_request(...)`: crea la matrícula pendiente y sus cargos en una sola transacción. No ocupa cupo ni asigna grupo al alumno.
- `group_capacity(...)`: devuelve capacidad, ocupados y disponibles; solo dirección, secretaría o el docente asignado.
- Trigger de matrícula: bloquea la fila del grupo y vuelve a contar cupos al pasar a `active` o `exception`. También sincroniza `students.group_id`.
- Trigger de grupos: impide bajar capacidad bajo ocupados y cambiar ciclo/academia si existen matrículas.
- `transfer_student` exige matrícula `active`/`exception` en el ciclo destino, valida cupo y sincroniza matrícula + alumno.
- Los errores de B02 exponen un `hint` de negocio estable (`ENROLLMENT_DUPLICATE`, `GROUP_FULL`, `ACCESS_DENIED`, etc.).
- `charges` ya no admite `INSERT` directo desde la API: los cargos nacen solo desde la RPC de matrícula.

## Decisiones de seguridad

- El rol y la academia se comprueban dentro de las RPC con `auth.uid()` y `memberships`, no con datos del navegador.
- La solicitud pendiente no actualiza `students.group_id`; el docente no ve al alumno hasta que la matrícula ocupa cupo.
- La activación real ya está implementada en la RPC de pago de B03; B02 deja el trigger y la unicidad que rechazan sobrecupo y duplicados aunque otra ruta intente activar.
- La excepción ocupará cupo cuando B06 la implemente; el modelo ya exige motivo, fecha límite y autor, y el trigger la cuenta igual que una activa.
- El traslado de B01 quedó corregido en B02: ya no puede asignar grupo sin matrícula ni desalinear el cupo. B06 solo añadirá historial.
- No hay borrado directo de matrículas ni cargos para `authenticated`.

## Registro de ejecución

| Fecha | Entorno | Comando | Resultado |
|---|---|---|---|
| 2026-11-19 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db push --remote --yes` | `20261119090000_b02_cycles_enrollments.sql` aplicada. |
| 2026-11-20 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db push --remote --yes` | `20261119091000_b02_invariants_error_codes.sql` aplicada. |
| 2026-11-20 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/seed-b01-demo.mjs` | Ciclos, matrículas, precios, inscripción y tres mensualidades demo. |
| 2026-11-19 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b02-enrollment.mjs` | `28/28 comprobaciones OK`. |
| 2026-11-19 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db query --remote --file supabase/tests/b02_enrollment.sql --yes` | `B02 RLS: todas las comprobaciones pasaron`. |
| 2026-11-19 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b01-isolation.mjs` | `40/40 comprobaciones OK` sin regresión. |
| 2026-11-19 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db query --remote --file supabase/tests/b01_rls.sql --yes` | `B01 RLS: todas las comprobaciones pasaron`. |

## Datos demo relevantes

- `Ciclo Demo 2026` en ambas academias, con umbrales 10/15 y tardanza computable.
- `Alumno Ficticio A1`: matrícula activa, inscripción pagada y tres mensualidades de S/200.
- `Alumno Ficticio A2`: matrícula excepcional con motivo y fecha límite; ocupa cupo.
- `Alumno Ficticio B1`: matrícula activa con inscripción pagada.
- Grupo A queda lleno con dos matrículas que ocupan cupo; el grupo A2 queda libre para solicitudes nuevas.

## Pendientes de otras tareas

- `B03`: RPC de pago con voucher que active la inscripción y llame al control de cupo en la misma transacción.
- `B05`: deuda vencida, faltas y casos de seguimiento calculados desde estos datos.
- `B06`: autorización de excepción y traslado con historial. El traslado ya sincroniza matrícula y alumno en B02; falta registrar el origen/destino/autor.
