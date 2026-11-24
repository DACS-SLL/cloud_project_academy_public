# Prueba de recuperación de pagos (F02)

No forma parte del build. Para ejecutarla sin tocar `package.json`:

```
npm i --no-save vitest@2 jsdom @testing-library/react@16 @testing-library/dom @testing-library/user-event
```
Crear `vitest.config.ts` temporal:
```
import { defineConfig } from 'vitest/config'
export default defineConfig({ esbuild: { jsx: 'automatic' }, test: { include: ['pruebas/**/*.test.tsx'] } })
```
Y ejecutar `npx vitest run`. Resultado esperado: 10 pruebas aprobadas en 2 archivos (en la rama F03: 11 en 3 archivos).

- `RegisterPayment.recovery.test.tsx` (5): recuperación de un pago sin confirmar con el mismo `p_payment_id`.
- `domain.dueDate.test.tsx` (5): vencimiento efectivo con `exception_due_date` en la inscripción excepcional y pago parcial.
- `followups.name.test.tsx` (1, solo F03): el historial de contactos conserva el nombre del alumno tras resolverse su caso.
