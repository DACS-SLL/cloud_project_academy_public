-- B01 - Privilegios explícitos.
-- RLS filtra filas, pero PostgREST también exige GRANT por tabla/función.
-- Se parte de denegación total para anon/authenticated y se habilita lo mínimo.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from PUBLIC, anon, authenticated;

-- Las tablas y funciones de B02-B04 también nacen denegadas; cada migración
-- debe conceder explícitamente lo que necesita.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from PUBLIC, anon, authenticated;

grant usage on schema public to anon, authenticated;

-- Lectura base de la sesión.
grant select on public.academies, public.profiles, public.memberships to authenticated;
grant update (name) on public.academies to authenticated;
grant update (full_name) on public.profiles to authenticated;

-- Operación de configuración y matrícula (B01 deja la estructura; B02 amplía reglas).
grant select, insert, update, delete
  on public.groups,
     public.subjects,
     public.teacher_assignments,
     public.students,
     public.guardians,
     public.charges
  to authenticated;

-- Finanzas y asistencia: solo lectura en B01.
-- La escritura de pagos (B03) y de sesiones/asistencia (B04) se hará por RPC.
grant select on public.payments, public.class_sessions, public.attendance to authenticated;

-- RPC de autorización y firma de sesión.
grant execute on function public.current_academy_ids() to authenticated;
grant execute on function public.is_member_of(uuid) to authenticated;
grant execute on function public.has_academy_role(uuid, public.membership_role[]) to authenticated;
grant execute on function public.is_teacher_of_group(uuid) to authenticated;
grant execute on function public.is_teacher_of_subject(uuid) to authenticated;
grant execute on function public.is_teacher_of_session(uuid) to authenticated;
grant execute on function public.can_access_voucher(text) to authenticated;
grant execute on function public.my_access() to authenticated;
