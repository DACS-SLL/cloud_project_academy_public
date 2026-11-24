-- B04 - A08/A10: registro, seguridad, duplicados y atomicidad de asistencia.
-- Requiere B01, B02 y 20261121100000_b04_record_attendance.sql.
-- Ejecutar localmente o en SQL Editor; el ROLLBACK no deja datos.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'b0410000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b041.teacher@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0410000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b041.cashier@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0410000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b041.admin@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0410000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'b041.teacher.other@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Unassigned teacher B04"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name)
values
  ('b0410000-0000-4000-8000-000000000100', 'B04 Asistencia A'),
  ('b0410000-0000-4000-8000-000000000200', 'B04 Asistencia B')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role)
values
  ('b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000001', 'teacher'),
  ('b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000002', 'cashier'),
  ('b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000003', 'admin'),
  ('b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000004', 'teacher')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (
  id, academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
)
values
  ('b0410000-0000-4000-8000-000000000110', 'b0410000-0000-4000-8000-000000000100', 'Ciclo B04 tardanza cuenta', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, true),
  ('b0410000-0000-4000-8000-000000000210', 'b0410000-0000-4000-8000-000000000200', 'Ciclo B04 otra academia', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, true),
  ('b0410000-0000-4000-8000-000000000120', 'b0410000-0000-4000-8000-000000000100', 'Ciclo B04 tardanza no cuenta', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, false)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, capacity)
values
  ('b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000110', 'Grupo B04 asistencia', 30),
  ('b0410000-0000-4000-8000-000000000131', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000110', 'Grupo B04 traslado', 30),
  ('b0410000-0000-4000-8000-000000000132', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000120', 'Grupo B04 tardanza no cuenta', 30),
  ('b0410000-0000-4000-8000-000000000230', 'b0410000-0000-4000-8000-000000000200', 'b0410000-0000-4000-8000-000000000210', 'Grupo B04 otra academia', 30)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name)
values
  ('b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000100', 'Curso B04 asistencia'),
  ('b0410000-0000-4000-8000-000000000240', 'b0410000-0000-4000-8000-000000000200', 'Curso B04 otra academia')
on conflict (id) do nothing;

insert into public.teacher_assignments (id, academy_id, teacher_id, group_id, subject_id)
values
  ('b0410000-0000-4000-8000-000000000150', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000001', 'b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000140'),
  ('b0410000-0000-4000-8000-000000000151', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000001', 'b0410000-0000-4000-8000-000000000132', 'b0410000-0000-4000-8000-000000000140')
on conflict (id) do nothing;

insert into public.students (id, academy_id, group_id, full_name)
values
  ('b0410000-0000-4000-8000-000000000160', 'b0410000-0000-4000-8000-000000000100', null, 'Alumno B04 activo'),
  ('b0410000-0000-4000-8000-000000000161', 'b0410000-0000-4000-8000-000000000100', null, 'Alumno B04 excepción'),
  ('b0410000-0000-4000-8000-000000000162', 'b0410000-0000-4000-8000-000000000100', null, 'Alumno B04 pendiente'),
  ('b0410000-0000-4000-8000-000000000260', 'b0410000-0000-4000-8000-000000000200', null, 'Alumno B04 de otra academia')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price,
  exception_reason, exception_due_date
)
values
  ('b0410000-0000-4000-8000-000000000170', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000160', 'b0410000-0000-4000-8000-000000000110', 'b0410000-0000-4000-8000-000000000130', 'active', 100, 100, null, null),
  ('b0410000-0000-4000-8000-000000000171', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000161', 'b0410000-0000-4000-8000-000000000110', 'b0410000-0000-4000-8000-000000000130', 'exception', 100, 100, 'Excepción de prueba', '2026-12-31'),
  ('b0410000-0000-4000-8000-000000000172', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000162', 'b0410000-0000-4000-8000-000000000110', 'b0410000-0000-4000-8000-000000000130', 'pending', 100, 100, null, null),
  ('b0410000-0000-4000-8000-000000000270', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000160', 'b0410000-0000-4000-8000-000000000120', 'b0410000-0000-4000-8000-000000000132', 'active', 100, 100, null, null)
on conflict (id) do nothing;

-- Simular el grupo actual tras un traslado B01: la asistencia histórica sigue
-- validándose contra la matrícula y el grupo/ciclo de su sesión.
update public.students
set group_id = 'b0410000-0000-4000-8000-000000000131'
where id = 'b0410000-0000-4000-8000-000000000160';

insert into public.class_sessions (id, academy_id, group_id, subject_id, teacher_id, starts_at)
values
  ('b0410000-0000-4000-8000-000000000180', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000001', '2026-11-20 10:00:00-05'),
  ('b0410000-0000-4000-8000-000000000181', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000001', '2026-11-21 10:00:00-05'),
  ('b0410000-0000-4000-8000-000000000182', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000004', '2026-11-22 10:00:00-05'),
  ('b0410000-0000-4000-8000-000000000184', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000130', 'b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000001', '2026-11-23 10:00:00-05'),
  ('b0410000-0000-4000-8000-000000000185', 'b0410000-0000-4000-8000-000000000100', 'b0410000-0000-4000-8000-000000000132', 'b0410000-0000-4000-8000-000000000140', 'b0410000-0000-4000-8000-000000000001', '2026-11-24 10:00:00-05'),
  ('b0410000-0000-4000-8000-000000000183', 'b0410000-0000-4000-8000-000000000200', 'b0410000-0000-4000-8000-000000000230', 'b0410000-0000-4000-8000-000000000240', 'b0410000-0000-4000-8000-000000000001', '2026-11-20 10:00:00-05')
on conflict (id) do nothing;

with historical_sessions as (
  insert into public.class_sessions (
    academy_id, group_id, subject_id, teacher_id, starts_at
  )
  select
    'b0410000-0000-4000-8000-000000000100',
    'b0410000-0000-4000-8000-000000000130',
    'b0410000-0000-4000-8000-000000000140',
    'b0410000-0000-4000-8000-000000000001',
    ('2026-11-02 10:00:00-05'::timestamptz + make_interval(days => n))
  from generate_series(1, 9) as series(n)
  returning id, academy_id
)
insert into public.attendance (academy_id, session_id, student_id, status)
select academy_id, id, 'b0410000-0000-4000-8000-000000000160', 'absent'
from historical_sessions;

with historical_sessions as (
  insert into public.class_sessions (
    academy_id, group_id, subject_id, teacher_id, starts_at
  )
  select
    'b0410000-0000-4000-8000-000000000100',
    'b0410000-0000-4000-8000-000000000130',
    'b0410000-0000-4000-8000-000000000140',
    'b0410000-0000-4000-8000-000000000001',
    ('2026-12-01 10:00:00-05'::timestamptz + make_interval(days => n))
  from generate_series(1, 14) as series(n)
  returning id, academy_id
)
insert into public.attendance (academy_id, session_id, student_id, status)
select academy_id, id, 'b0410000-0000-4000-8000-000000000161', 'absent'
from historical_sessions;

insert into public.attendance (academy_id, session_id, student_id, status)
values
  ('b0410000-0000-4000-8000-000000000200', 'b0410000-0000-4000-8000-000000000183', 'b0410000-0000-4000-8000-000000000260', 'present')
on conflict (session_id, student_id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0410000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_result record;
  v_sqlstate text;
  v_hint text;
  v_message text;
  v_unknown_session_message text;
begin
  -- Una sesión inexistente y una sesión real de otra academia devuelven
  -- exactamente el mismo error observable.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000999',
      '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"present"}]'::jsonb
    );
    raise exception 'B04: se aceptó un id de sesión inexistente';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a la sesión solicitada' then
      raise exception 'B04: id inexistente produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
    v_unknown_session_message := v_message;
  end;

  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000183',
      '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"present"}]'::jsonb
    );
    raise exception 'B04: se aceptó una sesión de otra academia';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> v_unknown_session_message then
      raise exception 'B04: sesión ajena produjo una respuesta distinta de sesión inexistente';
    end if;
  end;

  -- A08: nueve faltas previas más tardanza contabilizable activan aviso al llegar a diez.
  select * into v_result
  from public.record_attendance(
    'b0410000-0000-4000-8000-000000000180',
    '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"late"}]'::jsonb
  );
  if v_result.absences_counted <> 10
     or not v_result.warning_active
     or v_result.review_active then
    raise exception 'A08: tardanza contabilizable no activó el aviso en la décima falta';
  end if;

  -- A08: la regla se lee del ciclo, no del cliente; en este ciclo late no cuenta.
  select * into v_result
  from public.record_attendance(
    'b0410000-0000-4000-8000-000000000185',
    '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"late"}]'::jsonb
  );
  if v_result.absences_counted <> 0
     or v_result.warning_active
     or v_result.review_active then
    raise exception 'A08: tardanza se contó pese a late_counts_as_absence=false';
  end if;

  -- La matrícula exception es elegible para asistencia.
  select * into v_result
  from public.record_attendance(
    'b0410000-0000-4000-8000-000000000180',
    '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"present"}]'::jsonb
  );
  if v_result.student_id <> 'b0410000-0000-4000-8000-000000000161'::uuid
     or v_result.status <> 'present'
     or v_result.absences_counted <> 14
     or not v_result.warning_active
     or v_result.review_active then
    raise exception 'B04: no se aceptó la matrícula exception';
  end if;

  select * into v_result
  from public.record_attendance(
    'b0410000-0000-4000-8000-000000000184',
    '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"absent"}]'::jsonb
  );
  if v_result.absences_counted <> 15
     or not v_result.warning_active
     or not v_result.review_active then
    raise exception 'A08: el umbral review_absences no activó review_active';
  end if;

  -- La matrícula activa histórica también se valida aunque students.group_id ya cambió.
  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  if not exists (
    select 1
    from public.attendance a
    join public.students s on s.id = a.student_id and s.academy_id = a.academy_id
    where a.session_id = 'b0410000-0000-4000-8000-000000000180'
      and a.student_id = 'b0410000-0000-4000-8000-000000000160'
      and s.group_id = 'b0410000-0000-4000-8000-000000000131'
  ) then
    raise exception 'B04: no se preservó el caso de asistencia histórica tras traslado';
  end if;
  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000001","role":"authenticated"}', true);

  -- A10: segunda llamada para la misma sesión/alumno.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000180',
      '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"absent"}]'::jsonb
    );
    raise exception 'A10: se aceptó asistencia duplicada';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23505' or v_hint <> 'ATTENDANCE_DUPLICATE' then
      raise exception 'A10: duplicado existente produjo % / %, se esperaba 23505 / ATTENDANCE_DUPLICATE', v_sqlstate, v_hint;
    end if;
  end;

  -- A10: id repetido dentro del lote también se rechaza.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000181',
      '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"present"},{"student_id":"b0410000-0000-4000-8000-000000000161","status":"late"}]'::jsonb
    );
    raise exception 'A10: se aceptó alumno duplicado en el lote';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23505' or v_hint <> 'ATTENDANCE_DUPLICATE' then
      raise exception 'A10: duplicado en lote produjo % / %, se esperaba 23505 / ATTENDANCE_DUPLICATE', v_sqlstate, v_hint;
    end if;
  end;

  -- Un status no soportado usa el error de lote estable.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000181',
      '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"excused"}]'::jsonb
    );
    raise exception 'B04: se aceptó un status desconocido';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'INVALID_ATTENDANCE_BATCH' then
      raise exception 'B04: status inválido produjo % / %, se esperaba 22023 / INVALID_ATTENDANCE_BATCH', v_sqlstate, v_hint;
    end if;
  end;

  -- Solo el docente asignado a la sesión puede registrar.
  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000181',
      '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"present"}]'::jsonb
    );
    raise exception 'B04: cashier pudo registrar asistencia';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B04: acceso cashier produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000181',
      '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"present"}]'::jsonb
    );
    raise exception 'B04: admin pudo registrar asistencia';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B04: acceso admin produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000182',
      '[{"student_id":"b0410000-0000-4000-8000-000000000161","status":"present"}]'::jsonb
    );
    raise exception 'A10: docente no asignado pudo registrar asistencia';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'A10: docente no asignado produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"b0410000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  if exists (
    select 1 from public.attendance a
    where a.session_id = 'b0410000-0000-4000-8000-000000000181'
      and a.student_id = 'b0410000-0000-4000-8000-000000000161'
  ) then
    raise exception 'B04: un acceso indebido dejó una asistencia insertada';
  end if;

  -- Lote atómico: el alumno activo no debe insertarse si el otro no es elegible.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000181',
      '[{"student_id":"b0410000-0000-4000-8000-000000000160","status":"present"},{"student_id":"b0410000-0000-4000-8000-000000000162","status":"absent"}]'::jsonb
    );
    raise exception 'B04: lote con matrícula pendiente fue aceptado';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'ENROLLMENT_NOT_ACTIVE' then
      raise exception 'B04: lote no elegible produjo % / %, se esperaba 23514 / ENROLLMENT_NOT_ACTIVE', v_sqlstate, v_hint;
    end if;
  end;
  if exists (
    select 1 from public.attendance a
    where a.session_id = 'b0410000-0000-4000-8000-000000000181'
      and a.student_id in (
        'b0410000-0000-4000-8000-000000000160',
        'b0410000-0000-4000-8000-000000000162'
      )
  ) then
    raise exception 'B04: rollback de lote dejó filas parciales';
  end if;

  -- Un alumno de otra academia no se puede adjuntar a la sesión.
  begin
    perform public.record_attendance(
      'b0410000-0000-4000-8000-000000000180',
      '[{"student_id":"b0410000-0000-4000-8000-000000000260","status":"present"}]'::jsonb
    );
    raise exception 'B04: se aceptó alumno de otra academia';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> 'P0002' or v_hint <> 'STUDENT_NOT_FOUND' then
      raise exception 'B04: alumno de otra academia produjo % / %, se esperaba P0002 / STUDENT_NOT_FOUND', v_sqlstate, v_hint;
    end if;
  end;
end;
$$;

rollback;
