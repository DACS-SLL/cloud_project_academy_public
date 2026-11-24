-- B02 - Contrato definitivo de errores de traslado acordado con B06.
-- Un grupo de otra academia se reporta como inexistente para no revelar
-- recursos ajenos. La ausencia de matrícula activa/excepcional usa el código
-- definitivo TRANSFER_NO_ACTIVE_ENROLLMENT.

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
  v_group_academy_id uuid;
  v_group_cycle_id uuid;
  v_capacity integer;
  v_enrollment_id uuid;
  v_occupied integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select s.academy_id, s.group_id
    into v_academy_id, v_current_group_id
  from public.students s
  where s.id = p_student_id
  for update;

  if v_academy_id is null then
    raise exception 'Alumno no encontrado'
      using errcode = '22023', hint = 'STUDENT_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin}'::public.membership_role[]) then
    raise exception 'Solo dirección puede autorizar traslados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  -- El filtro por academia evita distinguir un grupo ajeno de uno inexistente.
  select g.academy_id, g.cycle_id, g.capacity
    into v_group_academy_id, v_group_cycle_id, v_capacity
  from public.groups g
  where g.id = p_group_id
    and g.academy_id = v_academy_id
  for update;

  if v_group_academy_id is null then
    raise exception 'Grupo destino no encontrado'
      using errcode = '22023', hint = 'GROUP_NOT_FOUND';
  end if;

  select e.id
    into v_enrollment_id
  from public.enrollments e
  where e.student_id = p_student_id
    and e.academy_id = v_academy_id
    and e.cycle_id = v_group_cycle_id
    and e.status in ('active', 'exception')
  for update;

  if v_enrollment_id is null then
    raise exception 'El alumno no tiene matrícula activa o excepcional en el ciclo destino'
      using errcode = '23514', hint = 'TRANSFER_NO_ACTIVE_ENROLLMENT';
  end if;

  if v_current_group_id = p_group_id then
    return;
  end if;

  select count(*)::integer
    into v_occupied
  from public.enrollments e
  where e.group_id = p_group_id
    and e.status in ('active', 'exception')
    and e.id <> v_enrollment_id;

  if v_occupied >= v_capacity then
    raise exception 'Grupo destino sin cupo'
      using errcode = '23514', hint = 'TRANSFER_GROUP_FULL';
  end if;

  update public.enrollments
  set group_id = p_group_id
  where id = v_enrollment_id;
end;
$$;

revoke all on function public.transfer_student(uuid, uuid) from public, anon, authenticated;
grant execute on function public.transfer_student(uuid, uuid) to authenticated;
