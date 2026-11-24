-- B01 - Endurecimiento de escrituras sensibles.
-- 1. Secretaría no puede cambiar students.group_id directamente; el traslado
--    pasa por una RPC que exige rol admin y valida cupo del grupo destino.
-- 2. Los cargos no se actualizan ni eliminan directamente; B02/B03 añadirán
--    correcciones transaccionales con control de saldo y trazabilidad.

-- Alumnos: se mantiene la lectura/edición de datos personales, pero se retira
-- el UPDATE de tabla y se concede solo por columnas. group_id y academy_id
-- quedan fuera para impedir traslados o cambios de academia por PostgREST.
revoke update on public.students from authenticated;
grant update (full_name, document_id, school, grade) on public.students to authenticated;

-- Cargos: sin UPDATE ni DELETE directo. El INSERT se mantiene para B01; B02
-- sustituirá la creación por una operación con reglas de matrícula.
revoke update, delete on public.charges from authenticated;
drop policy if exists charges_update_staff on public.charges;
drop policy if exists charges_delete_staff on public.charges;

-- Traslado autorizado por dirección. SECURITY DEFINER permite actualizar
-- group_id sin conceder esa columna a authenticated. El bloqueo de la fila del
-- grupo serializa traslados concurrentes al mismo destino en esta base mínima.
create or replace function public.transfer_student(
  p_student_id uuid,
  p_group_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_academy_id uuid;
  v_current_group_id uuid;
  v_capacity integer;
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada' using errcode = '28000';
  end if;

  select s.academy_id, s.group_id
    into v_academy_id, v_current_group_id
  from public.students s
  where s.id = p_student_id;

  if v_academy_id is null then
    raise exception 'Alumno no encontrado' using errcode = 'P0002';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin}'::public.membership_role[]) then
    raise exception 'Solo dirección puede autorizar traslados' using errcode = '42501';
  end if;

  if v_current_group_id = p_group_id then
    return;
  end if;

  select g.capacity
    into v_capacity
  from public.groups g
  where g.id = p_group_id
    and g.academy_id = v_academy_id
  for update;

  if v_capacity is null then
    raise exception 'Grupo destino no encontrado en la academia' using errcode = 'P0002';
  end if;

  select count(*)::integer
    into v_count
  from public.students s
  where s.academy_id = v_academy_id
    and s.group_id = p_group_id;

  if v_count >= v_capacity then
    raise exception 'Grupo destino sin cupo' using errcode = '23514';
  end if;

  update public.students
  set group_id = p_group_id
  where id = p_student_id
    and academy_id = v_academy_id;
end;
$$;

revoke all on function public.transfer_student(uuid, uuid) from public, anon, authenticated;
grant execute on function public.transfer_student(uuid, uuid) to authenticated;
