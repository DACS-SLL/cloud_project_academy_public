-- B04/B02 - Integración: faltas históricas después de un traslado real.
-- Requiere B01, B02, create_class_session, record_attendance y el índice
-- class_sessions_academy_group_subject_starts_at_uidx.
-- Todo se ejecuta en una transacción y termina con ROLLBACK.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'b0440000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b04.transfer.admin@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin integración B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0440000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b04.transfer.teacher.source@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Docente origen B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0440000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b04.transfer.teacher.destination@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Docente destino B04"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name)
values ('b0440000-0000-4000-8000-000000000100', 'Academia integración B04')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role)
values
  ('b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000001', 'admin'),
  ('b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000002', 'teacher'),
  ('b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000003', 'teacher')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (
  id, academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
)
values (
  'b0440000-0000-4000-8000-000000000110',
  'b0440000-0000-4000-8000-000000000100',
  'Ciclo integración B04', '2026-11-01', '2027-01-31', '5.º secundaria',
  2, 4, true
)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, capacity)
values
  ('b0440000-0000-4000-8000-000000000130', 'b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000110', 'Grupo origen integración', 5),
  ('b0440000-0000-4000-8000-000000000131', 'b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000110', 'Grupo destino integración', 5)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name)
values ('b0440000-0000-4000-8000-000000000140', 'b0440000-0000-4000-8000-000000000100', 'Curso integración B04')
on conflict (id) do nothing;

insert into public.teacher_assignments (id, academy_id, teacher_id, group_id, subject_id)
values
  ('b0440000-0000-4000-8000-000000000150', 'b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000002', 'b0440000-0000-4000-8000-000000000130', 'b0440000-0000-4000-8000-000000000140'),
  ('b0440000-0000-4000-8000-000000000151', 'b0440000-0000-4000-8000-000000000100', 'b0440000-0000-4000-8000-000000000003', 'b0440000-0000-4000-8000-000000000131', 'b0440000-0000-4000-8000-000000000140')
on conflict (id) do nothing;

insert into public.students (id, academy_id, full_name)
values ('b0440000-0000-4000-8000-000000000160', 'b0440000-0000-4000-8000-000000000100', 'Alumno traslado B04')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
)
values (
  'b0440000-0000-4000-8000-000000000170',
  'b0440000-0000-4000-8000-000000000100',
  'b0440000-0000-4000-8000-000000000160',
  'b0440000-0000-4000-8000-000000000110',
  'b0440000-0000-4000-8000-000000000130',
  'active', 100, 100
)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0440000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_source_session_1 uuid;
  v_source_session_2 uuid;
  v_source_unmarked_session uuid;
  v_destination_session uuid;
  v_result record;
  v_sqlstate text;
  v_hint text;
  v_count integer;
  v_available integer;
begin
  -- Los dos grupos comparten academia/ciclo y tienen vacantes antes del cambio.
  select available into v_available
  from public.group_capacity('b0440000-0000-4000-8000-000000000131');
  if v_available < 1 then raise exception 'Fixture B04: grupo destino sin vacante'; end if;
  select available into v_available
  from public.group_capacity('b0440000-0000-4000-8000-000000000130');
  if v_available < 1 then raise exception 'Fixture B04: grupo origen sin vacante'; end if;

  -- El docente de origen crea tres sesiones únicas en el grupo anterior.
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  v_source_session_1 := public.create_class_session(
    'b0440000-0000-4000-8000-000000000130',
    'b0440000-0000-4000-8000-000000000140',
    '2026-11-20 09:00:00-05'
  );
  v_source_session_2 := public.create_class_session(
    'b0440000-0000-4000-8000-000000000130',
    'b0440000-0000-4000-8000-000000000140',
    '2026-11-21 09:00:00-05'
  );
  -- Sesión deliberadamente sin asistencia para comprobar el límite retroactivo.
  v_source_unmarked_session := public.create_class_session(
    'b0440000-0000-4000-8000-000000000130',
    'b0440000-0000-4000-8000-000000000140',
    '2026-11-21 10:00:00-05'
  );

  select * into v_result
  from public.record_attendance(
    v_source_session_1,
    '[{"student_id":"b0440000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
  );
  if v_result.absences_counted <> 1 or v_result.warning_active then
    raise exception 'A08 integración: primera falta del grupo origen incorrecta';
  end if;

  select * into v_result
  from public.record_attendance(
    v_source_session_2,
    '[{"student_id":"b0440000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
  );
  if v_result.absences_counted <> 2 or not v_result.warning_active or v_result.review_active then
    raise exception 'A08 integración: faltas del grupo origen no alcanzaron el aviso esperado';
  end if;

  if (select count(*)::integer from public.class_sessions
      where academy_id = 'b0440000-0000-4000-8000-000000000100'
        and group_id = 'b0440000-0000-4000-8000-000000000130'
        and subject_id = 'b0440000-0000-4000-8000-000000000140') <> 3
     or (select count(distinct starts_at)::integer from public.class_sessions
         where academy_id = 'b0440000-0000-4000-8000-000000000100'
           and group_id = 'b0440000-0000-4000-8000-000000000130'
           and subject_id = 'b0440000-0000-4000-8000-000000000140') <> 3 then
    raise exception 'Fixture B04: sesiones de origen repetidas';
  end if;

  -- Traslado real autenticado como admin; B02 actualiza matrícula y alumno
  -- mediante el trigger de cupo en la misma transacción.
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform public.transfer_student(
    'b0440000-0000-4000-8000-000000000160',
    'b0440000-0000-4000-8000-000000000131'
  );

  if (select group_id from public.enrollments where id = 'b0440000-0000-4000-8000-000000000170')
       is distinct from 'b0440000-0000-4000-8000-000000000131'::uuid
     or (select group_id from public.students where id = 'b0440000-0000-4000-8000-000000000160')
       is distinct from 'b0440000-0000-4000-8000-000000000131'::uuid then
    raise exception 'Integración B04: matrícula y alumno no cambiaron juntos';
  end if;

  select count(*)::integer into v_count
  from public.attendance
  where academy_id = 'b0440000-0000-4000-8000-000000000100'
    and student_id = 'b0440000-0000-4000-8000-000000000160'
    and session_id in (v_source_session_1, v_source_session_2)
    and status = 'absent';
  if v_count <> 2 then
    raise exception 'Integración B04: las dos faltas de sesiones anteriores no permanecieron';
  end if;

  -- El docente anterior puede consultar/intentar sobre su sesión histórica,
  -- pero ya no puede registrar retroactivamente: la matrícula está en el destino.
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  begin
    perform public.record_attendance(
      v_source_unmarked_session,
      '[{"student_id":"b0440000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
    );
    raise exception 'Integración B04: se permitió asistencia retroactiva en el grupo anterior';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'ENROLLMENT_NOT_ACTIVE' then
      raise exception 'Integración B04: retroactividad devolvió % / %, se esperaba 23514 / ENROLLMENT_NOT_ACTIVE', v_sqlstate, v_hint;
    end if;
  end;
  if exists (
    select 1 from public.attendance
    where session_id = v_source_unmarked_session
      and student_id = 'b0440000-0000-4000-8000-000000000160'
  ) then
    raise exception 'Integración B04: rechazo retroactivo dejó asistencia';
  end if;

  -- El docente de origen no está asignado al grupo/sesión nuevos.
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  v_destination_session := public.create_class_session(
    'b0440000-0000-4000-8000-000000000131',
    'b0440000-0000-4000-8000-000000000140',
    '2026-11-22 09:00:00-05'
  );
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  begin
    perform public.record_attendance(
      v_destination_session,
      '[{"student_id":"b0440000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
    );
    raise exception 'Integración B04: docente no asignado registró asistencia en destino';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'Integración B04: docente no asignado devolvió % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- El docente asignado registra una falta destino: el total del ciclo suma
  -- las dos faltas históricas de origen más la nueva falta.
  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  select * into v_result
  from public.record_attendance(
    v_destination_session,
    '[{"student_id":"b0440000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
  );
  if v_result.absences_counted <> 3 or not v_result.warning_active or v_result.review_active then
    raise exception 'A08 integración: acumulado tras traslado no fue 3 con aviso activo';
  end if;

  perform set_config('request.jwt.claims', '{"sub":"b0440000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  if (select count(*)::integer from public.attendance
      where student_id = 'b0440000-0000-4000-8000-000000000160'
        and status = 'absent') <> 3
     or (select count(*)::integer from public.attendance
         where session_id = v_destination_session
           and student_id = 'b0440000-0000-4000-8000-000000000160'
           and status = 'absent') <> 1 then
    raise exception 'Integración B04: faltas previas/nueva asistencia no persistieron';
  end if;
end;
$$;

rollback;
