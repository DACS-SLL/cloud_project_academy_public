-- B02 - Invariantes de matrícula/cupo y códigos de negocio estables.
-- 1. transfer_student sincroniza la matrícula y exige matrícula activa o
--    excepcional en el ciclo del grupo destino.
-- 2. No se puede bajar la capacidad por debajo de los ocupados ni cambiar
--    ciclo/academia de un grupo con matrículas.
-- 3. Los errores de B02 exponen un código estable en el campo hint de
--    PostgREST; el frontend no compara mensajes.

-- Códigos de negocio:
-- SESSION_REQUIRED, ACCESS_DENIED, GROUP_NOT_FOUND, STUDENT_NOT_FOUND,
-- INVALID_AMOUNT, INVALID_DUE_DATE, ENROLLMENT_DUPLICATE, GROUP_FULL,
-- GROUP_CYCLE_MISMATCH, GROUP_CAPACITY_BELOW_OCCUPIED,
-- GROUP_CYCLE_HAS_ENROLLMENTS, GROUP_ACADEMY_HAS_ENROLLMENTS,
-- TRANSFER_CROSS_ACADEMY, TRANSFER_ENROLLMENT_REQUIRED, TRANSFER_GROUP_FULL.

create or replace function public.b02_enrollment_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_academy_id uuid;
  v_group_cycle_id uuid;
  v_capacity integer;
  v_occupied integer;
begin
  select g.academy_id, g.cycle_id, g.capacity
    into v_group_academy_id, v_group_cycle_id, v_capacity
  from public.groups g
  where g.id = new.group_id
  for update;

  if v_group_academy_id is null then
    raise exception 'Grupo no encontrado'
      using errcode = 'P0002', hint = 'GROUP_NOT_FOUND';
  end if;

  if v_group_academy_id <> new.academy_id or v_group_cycle_id <> new.cycle_id then
    raise exception 'El grupo no pertenece al ciclo y academia de la matrícula'
      using errcode = '23514', hint = 'GROUP_CYCLE_MISMATCH';
  end if;

  if new.status in ('active', 'exception') then
    if tg_op = 'INSERT'
       or old.status not in ('active', 'exception')
       or old.group_id is distinct from new.group_id then
      select count(*)::integer
        into v_occupied
      from public.enrollments e
      where e.group_id = new.group_id
        and e.status in ('active', 'exception')
        and e.id is distinct from new.id;

      if v_occupied >= v_capacity then
        raise exception 'Grupo sin cupo'
          using errcode = '23514', hint = 'GROUP_FULL';
      end if;

      update public.students s
      set group_id = new.group_id
      where s.id = new.student_id
        and s.academy_id = new.academy_id;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.group_capacity(p_group_id uuid)
returns table (
  group_id uuid,
  capacity integer,
  occupied integer,
  available integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_academy_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select g.academy_id into v_academy_id
  from public.groups g
  where g.id = p_group_id;

  if v_academy_id is null then
    raise exception 'Grupo no encontrado'
      using errcode = 'P0002', hint = 'GROUP_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[])
     and not public.is_teacher_of_group(p_group_id) then
    raise exception 'Sin acceso al grupo'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  return query
  select
    g.id,
    g.capacity,
    count(e.id)::integer,
    greatest(g.capacity - count(e.id)::integer, 0)
  from public.groups g
  left join public.enrollments e
    on e.group_id = g.id
   and e.academy_id = g.academy_id
   and e.status in ('active', 'exception')
  where g.id = p_group_id
  group by g.id, g.capacity;
end;
$$;

create or replace function public.create_enrollment_request(
  p_student_id uuid,
  p_group_id uuid,
  p_registration_price numeric,
  p_monthly_price numeric,
  p_registration_due_date date,
  p_monthly_due_dates date[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_academy_id uuid;
  v_cycle_id uuid;
  v_enrollment_id uuid;
  v_due_date date;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select g.academy_id, g.cycle_id
    into v_academy_id, v_cycle_id
  from public.groups g
  where g.id = p_group_id;

  if v_academy_id is null then
    raise exception 'Grupo no encontrado'
      using errcode = 'P0002', hint = 'GROUP_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[]) then
    raise exception 'Solo dirección o secretaría pueden registrar matrículas'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if not exists (
    select 1 from public.students s
    where s.id = p_student_id
      and s.academy_id = v_academy_id
  ) then
    raise exception 'Alumno no encontrado en la academia'
      using errcode = 'P0002', hint = 'STUDENT_NOT_FOUND';
  end if;

  if p_registration_price is null or p_registration_price <= 0
     or p_monthly_price is null or p_monthly_price <= 0 then
    raise exception 'Los precios deben ser positivos'
      using errcode = '22023', hint = 'INVALID_AMOUNT';
  end if;

  if p_registration_due_date is null
     or p_monthly_due_dates is null
     or cardinality(p_monthly_due_dates) = 0 then
    raise exception 'La inscripción y al menos una mensualidad requieren vencimiento'
      using errcode = '22023', hint = 'INVALID_DUE_DATE';
  end if;

  if exists (
    select 1 from public.enrollments e
    where e.student_id = p_student_id
      and e.cycle_id = v_cycle_id
  ) then
    raise exception 'El alumno ya tiene una matrícula en este ciclo'
      using errcode = '23505', hint = 'ENROLLMENT_DUPLICATE';
  end if;

  insert into public.enrollments (
    academy_id, student_id, cycle_id, group_id, status,
    agreed_registration_price, agreed_monthly_price, created_by
  )
  values (
    v_academy_id, p_student_id, v_cycle_id, p_group_id, 'pending',
    p_registration_price, p_monthly_price, (select auth.uid())
  )
  returning id into v_enrollment_id;

  insert into public.charges (
    academy_id, student_id, enrollment_id, type, amount, due_date
  )
  values (
    v_academy_id, p_student_id, v_enrollment_id, 'registration',
    p_registration_price, p_registration_due_date
  );

  foreach v_due_date in array p_monthly_due_dates loop
    insert into public.charges (
      academy_id, student_id, enrollment_id, type, amount, due_date
    )
    values (
      v_academy_id, p_student_id, v_enrollment_id, 'monthly',
      p_monthly_price, v_due_date
    );
  end loop;

  return v_enrollment_id;
end;
$$;

-- Traslado consistente: usa la matrícula activa/excepcional del ciclo del
-- grupo destino y deja que el trigger sincronice students.group_id.
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
      using errcode = 'P0002', hint = 'STUDENT_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin}'::public.membership_role[]) then
    raise exception 'Solo dirección puede autorizar traslados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  select g.academy_id, g.cycle_id, g.capacity
    into v_group_academy_id, v_group_cycle_id, v_capacity
  from public.groups g
  where g.id = p_group_id
  for update;

  if v_group_academy_id is null then
    raise exception 'Grupo destino no encontrado'
      using errcode = 'P0002', hint = 'GROUP_NOT_FOUND';
  end if;

  if v_group_academy_id <> v_academy_id then
    raise exception 'El grupo destino pertenece a otra academia'
      using errcode = '42501', hint = 'TRANSFER_CROSS_ACADEMY';
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
      using errcode = '23514', hint = 'TRANSFER_ENROLLMENT_REQUIRED';
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

-- Invariantes de grupos con matrículas existentes.
create or replace function public.b02_groups_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occupied integer;
begin
  if new.academy_id is distinct from old.academy_id
     and exists (
       select 1 from public.enrollments e where e.group_id = old.id
     ) then
    raise exception 'No se puede cambiar la academia de un grupo con matrículas'
      using errcode = '23514', hint = 'GROUP_ACADEMY_HAS_ENROLLMENTS';
  end if;

  if new.cycle_id is distinct from old.cycle_id
     and exists (
       select 1 from public.enrollments e where e.group_id = old.id
     ) then
    raise exception 'No se puede cambiar el ciclo de un grupo con matrículas'
      using errcode = '23514', hint = 'GROUP_CYCLE_HAS_ENROLLMENTS';
  end if;

  if new.capacity < old.capacity then
    select count(*)::integer
      into v_occupied
    from public.enrollments e
    where e.group_id = old.id
      and e.status in ('active', 'exception');

    if v_occupied > new.capacity then
      raise exception 'La capacidad no puede quedar por debajo de los alumnos matriculados'
        using errcode = '23514', hint = 'GROUP_CAPACITY_BELOW_OCCUPIED';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists b02_on_groups_guard on public.groups;
create trigger b02_on_groups_guard
  before update of capacity, cycle_id, academy_id on public.groups
  for each row execute function public.b02_groups_guard();

revoke all on function public.group_capacity(uuid) from public, anon, authenticated;
revoke all on function public.create_enrollment_request(uuid, uuid, numeric, numeric, date, date[])
  from public, anon, authenticated;
revoke all on function public.transfer_student(uuid, uuid) from public, anon, authenticated;

grant execute on function public.group_capacity(uuid) to authenticated;
grant execute on function public.create_enrollment_request(uuid, uuid, numeric, numeric, date, date[])
  to authenticated;
grant execute on function public.transfer_student(uuid, uuid) to authenticated;
