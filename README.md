# Academia Manager

Aplicación web para matrícula, cobranza bancaria y asistencia de academias pequeñas. Implementada con React, TypeScript, Vite y Supabase Auth/PostgreSQL/Storage, con despliegue estático en Cloudflare Pages.

Esta edición pública contiene código y documentación técnica bajo MIT. Tiene historial nuevo y créditos de los autores humanos; la entrega académica, los informes institucionales y el tablero de coordinación se conservan en privado. No se proporcionan cuentas del demo del equipo.

## Autores

Juan Alexis Quispe Luque — interfaz. Fernando Perez del Castillo — backend y datos. Yony Alex Vilca Mamani — integración cloud y asistencia. Daniel Casas — coordinación, QA y documentación.

## Instalación del frontend

Requiere Node.js 20.19+ o 22.12+, npm y un proyecto Supabase propio.

```powershell
git clone https://github.com/DACS-SLL/cloud_project_academy_public.git
cd cloud_project_academy_public
npm ci
Copy-Item .env.example .env.local
```

Completar `.env.local` únicamente con `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` del proyecto propio. Luego ejecutar `npm run dev`. `npm run build` comprueba TypeScript y genera `dist/`; `npm run preview` permite consultar el bundle local.

## Backend y configuración

Crear una instancia Supabase aislada y aplicar, en orden, las migraciones de `supabase/migrations/` con Supabase CLI. Confirmar siempre el proyecto destino antes de aplicar cambios:

```powershell
npx supabase link --project-ref <PROJECT_REF_PROPIO>
npx supabase db push
```

Los roles Dirección, Secretaría y Docente se separan por academia con RLS y RPC. Los vouchers se guardan en un bucket privado. El alta de usuarios y fixtures se realiza mediante scripts administrativos en una instancia de prueba propia. El seed requiere `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `Q01_DEMO_PASSWORD` (al menos 12 caracteres) como variables de terminal privada. Usar `supabase/.env.example` solo como referencia de nombres; los scripts no cargan archivos de entorno automáticamente.

La clave de servidor nunca se coloca en `VITE_*`, en el navegador ni en Git. No ejecutar seeds en una instancia que deba conservar datos existentes. `seed-i01-attendance-only.mjs` prepara faltas sobre fixtures existentes, ofrece `--dry-run` y no sustituye al seed base; tiene supuestos sobre los datos previos y escrituras no transaccionales.

## Pruebas y alcance

Los contratos de operaciones están en `docs/`; `supabase/tests/` contiene verificaciones SQL y `scripts/verify-*.mjs` comprobaciones de módulos. Ejecutarlas únicamente sobre una instancia ficticia propia. Los verificadores B01–B03 reciben `Q01_DEMO_PASSWORDS_JSON` como objeto correo a contraseña para credenciales distintas, o `Q01_DEMO_PASSWORD` para una instancia aislada con contraseña común. No registrar sus valores en capturas ni salidas compartidas.

La evaluación anterior aprobó diez casos seleccionados del MVP. La ampliación de cuatro casos internos, las mediciones de rendimiento, escalabilidad, restauración y satisfacción permanecen pendientes. La publicación del código no acredita aptitud para operar con datos reales. El borrado inmediato de vouchers huérfanos está diferido; `discard-voucher` devuelve `501 DISCARD_DEFERRED` en P0.

## Despliegue

En Cloudflare Pages usar `npm run build`, directorio `dist` y las dos variables públicas Vite de la instancia propia. Migraciones y frontend se despliegan por separado; publicar HTTPS no verifica permisos ni integridad. El demo compartido del equipo permanece restringido a sus integrantes.

## Licencia y seguridad

Código y documentación original bajo [MIT](LICENSE). Consultar [avisos de terceros](THIRD_PARTY_NOTICES.md) y [seguridad](SECURITY.md). No se incluyen logotipos, plantilla, informe institucional ni contraseñas demo.
