# B03 - Pagos bancarios, saldo, activación y anulación

**Tarea:** `B03` · **Responsable:** Fernando · **Dependencia:** `B01`, `B02`
**Alcance:** pago bancario con voucher privado obligatorio, referencia, fecha, parcialidad, saldo, activación de inscripción y anulación auditada.

## Criterios de aceptación

| Prueba | Resultado esperado | Evidencia |
|---|---|---|
| `A05` | S/80 sobre un cargo de S/200 deja saldo S/120; el pago parcial no activa la matrícula. | `scripts/verify-b03-payments.mjs`, `supabase/tests/b03_payments.sql` |
| `A06` | Efectivo, voucher faltante, monto inválido y sobrepago se rechazan sin mutar saldo. | API + SQL |
| `A07` | Solo dirección anula un pago, con motivo, auditoría y recálculo de saldo. | API + SQL |
| Activación | Completar la inscripción activa la matrícula y asigna grupo; si no hay cupo, rollback total. | SQL + API |
| Idempotencia | Reintentar con el mismo `p_payment_id` no duplica el pago. | API + SQL |
| Voucher huérfano | Pago rechazado no deja pago. El descarte inmediato está deshabilitado en P0 para evitar la carrera con `register_payment`; queda limpieza administrativa posterior. | Edge Function `discard-voucher` devuelve `501 DISCARD_DEFERRED` |
| Regresión | B01/B02 siguen pasando. | `40/40` y `28/28` |

## Esquema implementado

- `payments.paid_at date` con backfill desde `created_at`.
- `payments.voided_at timestamptz`, `payments.voided_by uuid`.
- Índice único `(academy_id, reference)`.
- `payments` sin escritura directa para `authenticated`.
- `register_payment(...)`: pago bancario, saldo, voucher, activación e idempotencia.
- `void_payment(...)`: anulación auditada solo para dirección.
- Edge Function `discard-voucher`: **deshabilitada en P0**. No borra objetos para evitar la ventana entre comprobar el pago y eliminar el voucher; responde `501 DISCARD_DEFERRED`. La limpieza se hará administrativamente con `service_role` o en una tarea posterior coordinada con el pago.

## Reglas transaccionales

- Cargo y matrícula deben pertenecer a la misma academia y el cargo a la matrícula.
- El cargo se bloquea y el saldo se calcula como `amount − suma(pagos confirmed)`.
- `amount > 0` y `amount <= saldo`.
- Solo `bank_transfer` o `bank_deposit`; no efectivo.
- Referencia obligatoria y única por academia.
- Voucher obligatorio, en `vouchers/{academy_id}/{payment_id}/{archivo}`, con objeto existente.
- Si el cargo es `registration` y queda saldo cero, la matrícula pasa de `pending`/`exception` a `active`.
- Si no hay cupo, se revierte todo: no queda pago confirmado.
- Anulación: solo `admin`, motivo obligatorio; el saldo se recalcula.
- Si al anular la inscripción el saldo vuelve a positivo:
  - matrícula `active` normal → `pending` y libera `students.group_id`;
  - matrícula con autorización excepcional → vuelve a `exception` y conserva el cupo.

## Idempotencia

- El cliente genera `p_payment_id` antes de subir el voucher.
- La ruta del voucher usa ese mismo UUID.
- Si se pierde la conexión, se reintenta con el mismo `p_payment_id`.
- Mismos datos → misma respuesta con `idempotent = true`.
- Mismo id con datos distintos → `PAYMENT_IDEMPOTENCY_CONFLICT`.
- Pago rechazado → no existe pago; el voucher queda huérfano para limpieza administrativa. El descarte inmediato no se ejecuta en P0.

## Errores de negocio

El código estable viaja en `error.hint`:

| `hint` | HTTP | Uso |
|---|---|---|
| `PAYMENT_INVALID_AMOUNT` | 400 | Monto nulo, cero o negativo |
| `PAYMENT_INVALID_DATE` | 400 | Fecha faltante |
| `PAYMENT_METHOD_INVALID` | 400 | Efectivo, método nulo u otro método |
| `PAYMENT_REFERENCE_REQUIRED` | 400 | Referencia vacía |
| `PAYMENT_VOUCHER_REQUIRED` | 400 | Voucher vacío |
| `PAYMENT_VOUCHER_PATH_INVALID` | 400 | Ruta de otra academia/pago |
| `PAYMENT_VOUCHER_OBJECT_NOT_FOUND` | 400 | Objeto privado inexistente |
| `PAYMENT_DUPLICATE_REFERENCE` | 409 | Referencia ya registrada |
| `PAYMENT_IDEMPOTENCY_CONFLICT` | 409 | Mismo pago con datos distintos |
| `PAYMENT_OVERPAY` | 400 | Monto mayor al saldo |
| `PAYMENT_CHARGE_MISMATCH` | 400 | Cargo de otra matrícula |
| `PAYMENT_CHARGE_NOT_FOUND` | 400 | Cargo inexistente |
| `PAYMENT_ENROLLMENT_NOT_FOUND` | 400 | Matrícula inexistente |
| `PAYMENT_GROUP_FULL` | 400 | Activación sin cupo |
| `PAYMENT_VOID_FORBIDDEN` | 403 | Secretaría intenta anular |
| `PAYMENT_VOID_REASON_REQUIRED` | 400 | Anulación sin motivo |
| `PAYMENT_ALREADY_VOIDED` | 400 | Pago ya anulado |
| `PAYMENT_NOT_FOUND` | 400 | Pago inexistente |
| `ACCESS_DENIED` | 403 | Rol incorrecto |
| `SESSION_REQUIRED` | 401 | Sin sesión |

`discard-voucher` devuelve `501 { error: { code: 'DISCARD_DEFERRED', message } }`. No elimina objetos ni compite con `register_payment`.

## Registro de ejecución

| Fecha | Entorno | Comando | Resultado |
|---|---|---|---|
| 2026-11-22 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db push --remote --dry-run` | Solo `20261122090000_b03_payments.sql` pendiente; queda después de B02 `20261121091000`. |
| 2026-11-22 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db push --remote --yes` | `20261122090000_b03_payments.sql` aplicada después de B02 `20261121091000`. |
| 2026-11-22 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase functions deploy discard-voucher --project-ref ufrwqsgzfhjmwcworxlz --yes` | Función desplegada con descarte inmediato deshabilitado (`501 DISCARD_DEFERRED`). |
| 2026-11-21 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/seed-b01-demo.mjs` | Pago parcial demo S/80 sobre mensualidad S/200. |
| 2026-11-22 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b03-payments.mjs` | `27/27 comprobaciones OK`. |
| 2026-11-21 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `npx supabase db query --remote --file supabase/tests/b03_payments.sql --yes` | `B03 RLS: todas las comprobaciones pasaron`. |
| 2026-11-21 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b01-isolation.mjs` | `40/40 comprobaciones OK`. |
| 2026-11-21 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | `node scripts/verify-b02-enrollment.mjs` | `28/28 comprobaciones OK`. |
| 2026-11-21 | Supabase cloud (`ufrwqsgzfhjmwcworxlz`) | SQL B01/B02 | Ambos tests aprobados. |

## Historial de migraciones

Orden remoto después de la corrección:

```text
20261118090000 b01_core_tenancy
20261118090100 b01_helpers
20261118090200 b01_rls
20261118090300 b01_storage_private
20261118090400 b01_grants
20261118090500 b01_hardening
20261118090600 b01_student_writes
20261119090000 b02_cycles_enrollments
20261119091000 b02_invariants_error_codes
20261121091000 b02_transfer_final_codes
20261122090000 b03_payments
```

## Pendientes de otras tareas

- `B06`: excepción y traslado con historial `enrollment_transfers`; reglas confirmadas con Yony.
- `B05`: deuda/faltas, seguimiento y decisión de dirección.
- `F02`: pantallas de pago, voucher y anulación.
