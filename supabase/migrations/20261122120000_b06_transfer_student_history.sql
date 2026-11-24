-- B06/A04 - Traslado transaccional de una matrícula con historial append-only.

create table public.enrollment_transfers (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  enrollment_id uuid not null,
  student_id uuid not null,
  cycle_id uuid not null,
  from_group_id uuid not null,
  to_group_id uuid not null,
  transferred_by uuid not null references auth.users (id) on delete restrict,
  transferred_at timestamptz not null default now(),
  constraint enrollment_transfers_distinct_groups check (from_group_id <> to_group_id),
  constraint enrollment_transfers_enrollment_academy_fk
    foreign key (enrollment_id, academy_id)
    references public.enrollments (id, academy_id) on delete restrict,
  constraint enrollment_transfers_student_academy_fk
    foreign key (student_id, academy_id)
    references public.students (id, academy_id) on delete restrict,
  constraint enrollment_transfers_cycle_academy_fk
    foreign key (cycle_id, academy_id)
    references public.cycles (id, academy_id) on delete restrict,
  constraint enrollment_transfers_from_group_academy_fk
    foreign key (from_group_id, academy_id)
    references public.groups (id, academy_id) on delete restrict,
  constraint enrollment_transfers_to_group_academy_fk
    foreign key (to_group_id, academy_id)
    references public.groups (id, academy_id) on delete restrict
);

create index enrollment_transfers_enrollment_time_idx
  on public.enrollment_transfers (academy_id, enrollment_id, transferred_at desc);
create index enrollment_transfers_student_time_idx
  on public.enrollment_transfers (academy_id, student_id, transferred_at desc);

alter table public.enrollment_transfers enable row level security;

create policy enrollment_transfers_select_staff on public.enrollment_transfers
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

revoke all on table public.enrollment_transfers from public, anon, authenticated;
grant select on table public.enrollment_transfers to authenticated;

-- Mantener la firma B01 consumida por frontend, reemplazando su implementación.
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
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_destination_cycle_id uuid;
  v_enrollment_id uuid;
  v_cycle_id uuid;
  v_from_group_id uuid;
  v_trigger_message text;
  v_student_group_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  -- No consultamos ids de alumnos o grupos antes de confirmar que el usuario
  -- tiene algún rol admin. Las búsquedas posteriores quedan limitadas a una
  -- academia donde el mismo usuario es admin.
  if not exists (
    select 1 from public.memberships m
    where m.user_id = v_user_id
      and m.role = 'admin'::public.membership_role
  ) then
    raise exception 'Solo dirección puede autorizar traslados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  select s.academy_id
    into v_academy_id
  from public.students s
  where s.id = p_student_id
    and exists (
      select 1 from public.memberships m
      where m.user_id = v_user_id
        and m.academy_id = s.academy_id
        and m.role = 'admin'::public.membership_role
    );

  if not found then
    raise exception 'Alumno no encontrado'
      using errcode = '22023', hint = 'STUDENT_NOT_FOUND';
  end if;

  -- Un grupo ausente y uno de otra academia generan la misma respuesta.
  select g.cycle_id
    into v_destination_cycle_id
  from public.groups g
  where g.id = p_group_id
    and g.academy_id = v_academy_id;

  if not found then
    raise exception 'Grupo destino no encontrado'
      using errcode = '22023', hint = 'GROUP_NOT_FOUND';
  end if;

  -- El destino identifica el ciclo cuya matrícula se desea mover. El bloqueo
  -- serializa traslados concurrentes de esa matrícula y sigue el orden
  -- matrícula -> grupo (trigger B02) -> alumno.
  select e.id, e.cycle_id, e.group_id
    into v_enrollment_id, v_cycle_id, v_from_group_id
  from public.enrollments e
  where e.student_id = p_student_id
    and e.academy_id = v_academy_id
    and e.cycle_id = v_destination_cycle_id
    and e.status in ('active'::public.enrollment_status, 'exception'::public.enrollment_status)
  for update of e;

  if not found then
    if exists (
      select 1 from public.enrollments e
      where e.student_id = p_student_id
        and e.academy_id = v_academy_id
        and e.status in ('active'::public.enrollment_status, 'exception'::public.enrollment_status)
    ) then
      raise exception 'El grupo destino pertenece a otro ciclo de la matrícula'
        using errcode = '23514', hint = 'TRANSFER_CROSS_CYCLE';
    end if;

    raise exception 'El alumno no tiene matrícula activa o excepcional en el ciclo destino'
      using errcode = '23514', hint = 'TRANSFER_NO_ACTIVE_ENROLLMENT';
  end if;

  if v_from_group_id = p_group_id then
    return;
  end if;

  begin
    update public.enrollments e
    set group_id = p_group_id
    where e.id = v_enrollment_id
      and e.academy_id = v_academy_id;
  exception when check_violation then
    get stacked diagnostics v_trigger_message = message_text;
    if v_trigger_message = 'Grupo sin cupo' then
      raise exception 'El grupo destino no tiene vacante'
        using errcode = '23514', hint = 'TRANSFER_GROUP_FULL';
    elsif v_trigger_message = 'El grupo no pertenece al ciclo y academia de la matrícula' then
      raise exception 'El grupo destino no corresponde a la academia y ciclo de la matrícula'
        using errcode = '23514', hint = 'TRANSFER_CROSS_CYCLE';
    else
      raise;
    end if;
  end;

  select s.group_id
    into v_student_group_id
  from public.students s
  where s.id = p_student_id
    and s.academy_id = v_academy_id;

  if v_student_group_id is distinct from p_group_id then
    raise exception 'No se pudo sincronizar el grupo actual del alumno'
      using errcode = '23514', hint = 'TRANSFER_SYNC_FAILED';
  end if;

  insert into public.enrollment_transfers (
    academy_id, enrollment_id, student_id, cycle_id,
    from_group_id, to_group_id, transferred_by
  ) values (
    v_academy_id, v_enrollment_id, p_student_id, v_cycle_id,
    v_from_group_id, p_group_id, v_user_id
  );
end;
$$;

revoke all on function public.transfer_student(uuid, uuid) from public, anon, authenticated;
grant execute on function public.transfer_student(uuid, uuid) to authenticated;
