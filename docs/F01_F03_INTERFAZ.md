# F01–F03 · Interfaz del panel (Juan)

Código en `src/` con datos reales de Supabase. Sin dependencias nuevas; ruteo por hash. Contratos: B02, B03, B04, B05 y B06 (`docs/B0x_CONTRATO_OPERACIONES.md`).

## Qué hace cada entrega
| Entrega | Pantallas | Operaciones reales |
|---|---|---|
| F01 | Ciclos (D02), Grupos y cupos (D03), Nueva matrícula (C02), Alumnos y ficha (C03) | tablas cycles/groups/students/guardians; `create_enrollment_request`, `group_capacity` |
| F02 | Registrar pago (C04), Finanzas (D06/D06a), Mis grupos (T01), Sesiones y asistencia (T02–T04) | `register_payment`, `void_payment`, Storage de vouchers; `create_class_session`, `record_attendance` |
| F03 | Excepciones (D04a), Casos con contactos y decisión (C05–C07, D07), Traslados con historial (D05a), Tablero (D01/C01) | `authorize_enrollment_exception`, `transfer_student`, `enrollment_transfers`, `cycle_cases`, `register_followup`, `register_academic_decision` |

## Reglas aplicadas
- La UI decide por `error.hint`, nunca por texto. Tipos: `business`, `rejected`, `uncertain`.
- Sin respuesta fiable: «no podemos confirmar»; nunca «no se guardó». Tras cada escritura se relee del servidor.
- Pago: el `p_payment_id` se conserva para todo el intento. Un intento sin resolver bloquea otro pago. «No encontrado» no permite descartarlo ni generar otro id; solo reintentar con el mismo.
- **Deuda (B05):** el tablero y los casos usan `cycle_cases`. `balance` es solo la deuda **vencida**; `total_balance` incluye lo futuro. La base ya respeta `exception_due_date` y los pagos anulados; la interfaz no recalcula.
- **Excepciones (B06):** solo dirección, solo sobre matrícula `pending`, motivo y fecha obligatorios. Ocupa cupo y la inscripción impaga sigue como deuda. Repetir la llamada devuelve `EXCEPTION_STATUS_INVALID`.
- **Traslados (B06):** `transfer_student`; el historial se lee de `enrollment_transfers` (tabla y ficha del alumno).
- **Casos (B05):** secretaría registra contactos; solo dirección registra la decisión académica, que no modifica asistencias.
- Docente: solo `id, full_name, group_id`; sin acceso a casos ni finanzas.

## Limitaciones
- No se probó contra Supabase cloud desde este entorno. La evidencia conectada se toma en el recorrido con Daniel.
- B06 no pide razón del traslado, así que la pantalla no la muestra.
- El saldo de la ficha y de Registrar pago se sigue calculando en el cliente; el valor autoritativo del pago es `charge_balance` del RPC.
- Decisiones pendientes de Fernando (B06 §7): renovar excepciones vencidas y rechazar fechas pasadas; la UI avisa de una fecha pasada pero no la bloquea.
