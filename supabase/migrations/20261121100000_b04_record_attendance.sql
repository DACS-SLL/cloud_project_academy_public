-- B04 - Registro transaccional de asistencia por sesión.
-- Se conserva attendance.student_id; la matrícula se valida al escribir,
-- pero el id de matrícula no queda persistido en la asistencia.

create or replace function public.record_attendance(
  p_session_id uuid,
  p_records jsonb
)
returns table (
  student_id uuid,
  status text,
  absences_counted integer,
  warning_active boolean,
  review_active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_group_id uuid;
  v_subject_id uuid;
  v_cycle_id uuid;
  v_warning_absences integer;
  v_review_absences integer;
  v_late_counts_as_absence boolean;
  v_item jsonb;
  v_student_id uuid;
  v_student_academy_id uuid;
  v_student_ids uuid[] := array[]::uuid[];
  v_statuses text[] := array[]::text[];
  v_index integer;
  v_absences integer;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  -- Resolve only a session the caller is already authorized to teach. The
  -- same empty result covers an unknown id, another academy, and no assignment.
  select cs.academy_id, cs.group_id, cs.subject_id,
         g.cycle_id, c.warning_absences, c.review_absences,
         c.late_counts_as_absence
    into v_academy_id, v_group_id, v_subject_id,
         v_cycle_id, v_warning_absences, v_review_absences,
         v_late_counts_as_absence
  from public.class_sessions cs
  join public.groups g
    on g.id = cs.group_id
   and g.academy_id = cs.academy_id
  join public.cycles c
    on c.id = g.cycle_id
   and c.academy_id = g.academy_id
  where cs.id = p_session_id
    and cs.teacher_id = v_user_id
    and exists (
      select 1
      from public.memberships m
      where m.academy_id = cs.academy_id
        and m.user_id = v_user_id
        and m.role = 'teacher'::public.membership_role
    )
    and exists (
      select 1
      from public.teacher_assignments ta
      where ta.academy_id = cs.academy_id
        and ta.teacher_id = v_user_id
        and ta.group_id = cs.group_id
        and ta.subject_id = cs.subject_id
    );

  if not found then
    raise exception 'Sin acceso a la sesión solicitada'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if p_records is null or jsonb_typeof(p_records) is distinct from 'array' then
    raise exception 'El lote de asistencia debe ser un arreglo JSON no vacío'
      using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
  end if;

  if jsonb_array_length(p_records) = 0 then
    raise exception 'El lote de asistencia debe ser un arreglo JSON no vacío'
      using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
  end if;

  for v_item in
    select item.value
    from jsonb_array_elements(p_records) as item(value)
  loop
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'Cada elemento requiere student_id UUID y status válido'
        using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
    end if;

    if not (v_item ? 'student_id')
       or not (v_item ? 'status')
       or (v_item - 'student_id' - 'status') <> '{}'::jsonb
       or jsonb_typeof(v_item -> 'student_id') is distinct from 'string'
       or jsonb_typeof(v_item -> 'status') is distinct from 'string' then
      raise exception 'Cada elemento requiere student_id UUID y status válido'
        using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
    end if;

    begin
      v_student_id := (v_item ->> 'student_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Cada elemento requiere student_id UUID y status válido'
        using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
    end;

    if v_item ->> 'status' not in ('present', 'absent', 'late') then
      raise exception 'Cada elemento requiere student_id UUID y status válido'
        using errcode = '22023', hint = 'INVALID_ATTENDANCE_BATCH';
    end if;

    if array_position(v_student_ids, v_student_id) is not null then
      raise exception 'El alumno está repetido en el lote'
        using errcode = '23505', hint = 'ATTENDANCE_DUPLICATE';
    end if;

    v_student_ids := array_append(v_student_ids, v_student_id);
    v_statuses := array_append(v_statuses, v_item ->> 'status');
  end loop;

  -- Serialize writes for overlapping students; stable ordering avoids deadlocks.
  perform s.id
  from public.students s
  where s.id = any (v_student_ids)
  order by s.id
  for update;

  for v_index in 1..cardinality(v_student_ids) loop
    select s.academy_id
      into v_student_academy_id
    from public.students s
    where s.id = v_student_ids[v_index];

    if v_student_academy_id is distinct from v_academy_id then
      raise exception 'Alumno no encontrado'
        using errcode = 'P0002', hint = 'STUDENT_NOT_FOUND';
    end if;

    if not exists (
      select 1
      from public.enrollments e
      where e.academy_id = v_academy_id
        and e.student_id = v_student_ids[v_index]
        and e.cycle_id = v_cycle_id
        and e.group_id = v_group_id
        and e.status in ('active', 'exception')
    ) then
      raise exception 'El alumno no tiene matrícula activa en el grupo y ciclo de la sesión'
        using errcode = '23514', hint = 'ENROLLMENT_NOT_ACTIVE';
    end if;
  end loop;

  if exists (
    select 1
    from public.attendance a
    where a.session_id = p_session_id
      and a.student_id = any (v_student_ids)
  ) then
    raise exception 'Ya existe asistencia para uno o más alumnos de esta sesión'
      using errcode = '23505', hint = 'ATTENDANCE_DUPLICATE';
  end if;

  begin
    for v_index in 1..cardinality(v_student_ids) loop
      insert into public.attendance (
        academy_id, session_id, student_id, status
      ) values (
        v_academy_id, p_session_id, v_student_ids[v_index],
        v_statuses[v_index]::public.attendance_status
      );
    end loop;
  exception when unique_violation then
    raise exception 'Ya existe asistencia para uno o más alumnos de esta sesión'
      using errcode = '23505', hint = 'ATTENDANCE_DUPLICATE';
  end;

  for v_index in 1..cardinality(v_student_ids) loop
    select count(*)::integer
      into v_absences
    from public.attendance a
    join public.class_sessions historical_session
      on historical_session.id = a.session_id
     and historical_session.academy_id = a.academy_id
    join public.groups historical_group
      on historical_group.id = historical_session.group_id
     and historical_group.academy_id = historical_session.academy_id
    where a.academy_id = v_academy_id
      and a.student_id = v_student_ids[v_index]
      and historical_group.cycle_id = v_cycle_id
      and (
        a.status = 'absent'::public.attendance_status
        or (
          v_late_counts_as_absence
          and a.status = 'late'::public.attendance_status
        )
      );

    student_id := v_student_ids[v_index];
    status := v_statuses[v_index];
    absences_counted := v_absences;
    warning_active := v_absences >= v_warning_absences;
    review_active := v_absences >= v_review_absences;
    return next;
  end loop;
end;
$$;

revoke all on function public.record_attendance(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_attendance(uuid, jsonb)
  to authenticated;
