# Seguridad

Este es un MVP con datos ficticios. Las cuentas del demo compartido son privadas para el equipo; instalar el código requiere una instancia Supabase propia.

Para informar una vulnerabilidad, contactar al propietario DACS-SLL por un canal privado. No publicar credenciales ni datos personales en issues. No existe SLA propio de respuesta.

Usar Auth/RLS/RPC y Storage privado; ocultar botones no sustituye controles de acceso. Las claves privilegiadas nunca se incorporan al frontend o a variables VITE_. Un cierre global revoca refresh tokens, pero los access tokens emitidos previamente pueden conservar validez hasta su vencimiento.

El historial nuevo de esta edición no incluye la antigua contraseña demo, los metadatos de agentes ni los archivos institucionales del archivo académico. Las cuentas del equipo se rotaron y verificaron antes de esta publicación. Mantener secretos fuera de Git y revisar los cambios y ramas antes de compartirlos.
