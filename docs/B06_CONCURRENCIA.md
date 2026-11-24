# Verificación de concurrencia B06

Ejecutar desde la raíz del repositorio cuando esté disponible y en ejecución el contenedor local dedicado `supabase_db_cloud_project_academy_b06_test`:

```bash
./scripts/verify-b06-concurrency.sh
```

El script comprueba explícitamente el nombre del contenedor y solo ejecuta `psql` mediante `docker exec` contra esa instancia. Crea fixtures con IDs reservados `b066…`, dos alumnos con matrícula `active` en grupos de origen y un grupo destino de capacidad 2 con un ocupante activo; por tanto hay exactamente una vacante antes de iniciar la prueba.

Las dos llamadas a `transfer_student` se ejecutan en procesos `psql` separados, cada uno con su propia conexión PostgreSQL y claims de un administrador autenticado. Ambos clientes se lanzan en segundo plano antes de esperar resultados; no se usa una secuencia de llamadas para inferir concurrencia.

Resultado real reportado para la ejecución local B06:

```text
Una conexión: B06_RESULT=SUCCESS; COMMIT.
Otra conexión: B06_RESULT=TRANSFER_GROUP_FULL; COMMIT.
Verificaciones: sin sobrecupo, matrícula/alumno sincronizados e historial único.
```

La comprobación posterior exige que el grupo destino termine con dos matrículas ocupantes, que exactamente uno de los dos alumnos y su matrícula estén en destino, que el otro conserve ambos grupos de origen, y que exista exactamente un registro en `enrollment_transfers` correspondiente al traslado exitoso. El `trap` elimina historial y fixtures aunque falle la ejecución o se interrumpa el script. Los resultados no dependen del orden de llegada: cualquiera de los dos alumnos puede ganar la vacante.

## Integración de pagos y excepciones B03+B06

La prueba transaccional [`b06_payment_exception_integration.sql`](../supabase/tests/b06_payment_exception_integration.sql) cubre solicitud pendiente, autorización excepcional, pago bancario con voucher, traslado y anulación del pago. Ejecutar después de aplicar B01/B02/B03/B06 con `psql "$SUPABASE_DB_URL" -f supabase/tests/b06_payment_exception_integration.sql`. La prueba nueva está preparada con `BEGIN`/`ROLLBACK`; todavía no se registra un resultado de ejecución.
