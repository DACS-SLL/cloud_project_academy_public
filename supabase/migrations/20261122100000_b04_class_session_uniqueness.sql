-- B04 - Evita sesiones duplicadas, incluso ante inserciones concurrentes.
-- No elimina ni consolida sesiones preexistentes: si ya hay duplicados, la
-- creación del índice falla para que se resuelvan explícitamente antes.
create unique index class_sessions_academy_group_subject_starts_at_uidx
  on public.class_sessions (academy_id, group_id, subject_id, starts_at);

-- Mantiene la autorización y validaciones existentes; solo traduce la
-- violación de la clave de sesión a un código estable para el cliente.
create or replace function public.create_class_session(
  p_group_id uuid,
  p_subject_id uuid,
  p_starts_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_cycle_start date;
  v_cycle_end date;
  v_session_id uuid;
  v_local_session_date date;
  v_constraint_name text;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  -- Resolve the group only through a teacher membership in its academy.
  -- Missing groups and groups outside the caller's academies share one error.
  select g.academy_id
    into v_academy_id
  from public.groups g
  where g.id = p_group_id
    and exists (
      select 1
      from public.memberships m
      where m.academy_id = g.academy_id
        and m.user_id = v_user_id
        and m.role = 'teacher'::public.membership_role
    );

  if v_academy_id is null then
    raise exception 'Sin acceso a los recursos solicitados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  -- Read cycle bounds only after proving teacher membership in this academy.
  select c.start_date, c.end_date
    into v_cycle_start, v_cycle_end
  from public.groups g
  join public.cycles c
    on c.id = g.cycle_id
   and c.academy_id = g.academy_id
  where g.id = p_group_id
    and g.academy_id = v_academy_id;

  if v_cycle_start is null or v_cycle_end is null then
    raise exception 'Sin acceso a los recursos solicitados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  -- Scope the course lookup to the already-authorized academy. A foreign or
  -- nonexistent course has the same response as an unassigned course.
  if not exists (
    select 1
    from public.subjects s
    where s.id = p_subject_id
      and s.academy_id = v_academy_id
  ) then
    raise exception 'Sin acceso a los recursos solicitados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    where ta.academy_id = v_academy_id
      and ta.teacher_id = v_user_id
      and ta.group_id = p_group_id
      and ta.subject_id = p_subject_id
  ) then
    raise exception 'Sin acceso a los recursos solicitados'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if p_starts_at is null or not isfinite(p_starts_at) then
    raise exception 'La fecha y hora de inicio no son válidas'
      using errcode = '22023', hint = 'INVALID_START_TIME';
  end if;

  v_local_session_date := (p_starts_at at time zone 'America/Lima')::date;
  if v_local_session_date < v_cycle_start or v_local_session_date > v_cycle_end then
    raise exception 'La sesión está fuera de las fechas del ciclo'
      using errcode = '23514', hint = 'SESSION_OUTSIDE_CYCLE';
  end if;

  begin
    insert into public.class_sessions (
      academy_id, group_id, subject_id, teacher_id, starts_at
    ) values (
      v_academy_id, p_group_id, p_subject_id, v_user_id, p_starts_at
    )
    returning id into v_session_id;
  exception when unique_violation then
    get stacked diagnostics v_constraint_name = constraint_name;
    if v_constraint_name = 'class_sessions_academy_group_subject_starts_at_uidx' then
      raise exception 'Ya existe una sesión para el grupo, curso y fecha indicados'
        using errcode = '23505', hint = 'SESSION_DUPLICATE';
    end if;
    raise;
  end;

  return v_session_id;
end;
$$;

revoke all on function public.create_class_session(uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_class_session(uuid, uuid, timestamptz)
  to authenticated;
