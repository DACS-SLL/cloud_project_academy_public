-- B01 - Prueba reproducible de RLS en local o en el SQL Editor de Supabase.
-- Todo ocurre en una transacción que termina en ROLLBACK: no deja datos.
-- Ejecutar después de las migraciones:
--   psql "$SUPABASE_DB_URL" -f supabase/tests/b01_rls.sql
-- o pegar el contenido en el SQL Editor.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b01.admin.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b01.cashier.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b01.teacher.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b01.admin.b@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b01.cashier.b@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b01.teacher.b@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name) values
  ('11111111-1111-4111-8111-111111111111', 'B01 Academia A'),
  ('22222222-2222-4222-8222-222222222222', 'B01 Academia B')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role) values
  ('11111111-1111-4111-8111-111111111111', 'a0000000-0000-4000-8000-000000000001', 'admin'),
  ('11111111-1111-4111-8111-111111111111', 'a0000000-0000-4000-8000-000000000002', 'cashier'),
  ('11111111-1111-4111-8111-111111111111', 'a0000000-0000-4000-8000-000000000003', 'teacher'),
  ('22222222-2222-4222-8222-222222222222', 'b0000000-0000-4000-8000-000000000001', 'admin'),
  ('22222222-2222-4222-8222-222222222222', 'b0000000-0000-4000-8000-000000000002', 'cashier'),
  ('22222222-2222-4222-8222-222222222222', 'b0000000-0000-4000-8000-000000000003', 'teacher')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (id, academy_id, name, start_date, end_date, grade) values
  ('11111111-1111-4111-8111-0000000000c0', '11111111-1111-4111-8111-111111111111', 'Ciclo B01 A', '2026-11-01', '2027-01-31', '5.º secundaria'),
  ('22222222-2222-4222-8222-0000000000c0', '22222222-2222-4222-8222-222222222222', 'Ciclo B01 B', '2026-11-01', '2027-01-31', '5.º secundaria')
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, shift, capacity) values
  ('11111111-1111-4111-8111-0000000000a1', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000c0', 'Grupo A', 'morning', 3),
  ('11111111-1111-4111-8111-0000000000a0', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000c0', 'Grupo A no asignado', 'morning', 2),
  ('22222222-2222-4222-8222-0000000000b1', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000c0', 'Grupo B', 'afternoon', 2)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name) values
  ('11111111-1111-4111-8111-0000000000a2', '11111111-1111-4111-8111-111111111111', 'Curso A'),
  ('11111111-1111-4111-8111-0000000000ae', '11111111-1111-4111-8111-111111111111', 'Curso A no asignado'),
  ('22222222-2222-4222-8222-0000000000b2', '22222222-2222-4222-8222-222222222222', 'Curso B')
on conflict (id) do nothing;

insert into public.teacher_assignments (id, academy_id, teacher_id, group_id, subject_id) values
  ('11111111-1111-4111-8111-0000000000ad', '11111111-1111-4111-8111-111111111111', 'a0000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-0000000000a1', '11111111-1111-4111-8111-0000000000a2'),
  ('22222222-2222-4222-8222-0000000000bd', '22222222-2222-4222-8222-222222222222', 'b0000000-0000-4000-8000-000000000003', '22222222-2222-4222-8222-0000000000b1', '22222222-2222-4222-8222-0000000000b2')
on conflict (id) do nothing;

insert into public.students (id, academy_id, group_id, full_name) values
  ('11111111-1111-4111-8111-0000000000a3', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a1', 'Alumno A1'),
  ('11111111-1111-4111-8111-0000000000a4', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a1', 'Alumno A2'),
  ('22222222-2222-4222-8222-0000000000b3', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b1', 'Alumno B1')
on conflict (id) do nothing;

insert into public.guardians (id, academy_id, student_id, full_name) values
  ('11111111-1111-4111-8111-0000000000a5', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a3', 'Apoderado A1'),
  ('22222222-2222-4222-8222-0000000000b5', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b3', 'Apoderado B1')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
) values
  ('11111111-1111-4111-8111-0000000000e1', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a3', '11111111-1111-4111-8111-0000000000c0', '11111111-1111-4111-8111-0000000000a1', 'active', 200, 200),
  ('11111111-1111-4111-8111-0000000000e2', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a4', '11111111-1111-4111-8111-0000000000c0', '11111111-1111-4111-8111-0000000000a1', 'active', 200, 200),
  ('22222222-2222-4222-8222-0000000000e1', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b3', '22222222-2222-4222-8222-0000000000c0', '22222222-2222-4222-8222-0000000000b1', 'active', 200, 200)
on conflict (id) do nothing;

insert into public.charges (id, academy_id, student_id, enrollment_id, type, amount, due_date) values
  ('11111111-1111-4111-8111-0000000000a7', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a3', '11111111-1111-4111-8111-0000000000e1', 'registration', 200, '2026-11-10'),
  ('22222222-2222-4222-8222-0000000000b7', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b3', '22222222-2222-4222-8222-0000000000e1', 'registration', 200, '2026-11-10')
on conflict (id) do nothing;

insert into public.payments (id, academy_id, charge_id, amount, method, reference, voucher_path, status) values
  ('11111111-1111-4111-8111-0000000000a9', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a7', 80, 'bank_transfer', 'B01-A', '11111111-1111-4111-8111-111111111111/11111111-1111-4111-8111-0000000000a9/voucher.png', 'confirmed'),
  ('22222222-2222-4222-8222-0000000000b9', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b7', 80, 'bank_transfer', 'B01-B', '22222222-2222-4222-8222-222222222222/22222222-2222-4222-8222-0000000000b9/voucher.png', 'confirmed')
on conflict (id) do nothing;

insert into public.class_sessions (id, academy_id, group_id, subject_id, teacher_id, starts_at) values
  ('11111111-1111-4111-8111-0000000000aa', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a1', '11111111-1111-4111-8111-0000000000a2', 'a0000000-0000-4000-8000-000000000003', now()),
  ('22222222-2222-4222-8222-0000000000ba', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000b1', '22222222-2222-4222-8222-0000000000b2', 'b0000000-0000-4000-8000-000000000003', now())
on conflict (id) do nothing;

insert into public.attendance (id, academy_id, session_id, student_id, status) values
  ('11111111-1111-4111-8111-0000000000ab', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000aa', '11111111-1111-4111-8111-0000000000a3', 'present'),
  ('22222222-2222-4222-8222-0000000000bb', '22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-0000000000ba', '22222222-2222-4222-8222-0000000000b3', 'present')
on conflict (id) do nothing;

-- Dirección A: lectura de su academia, bloqueo de la academia B.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
begin
  if (select count(*) from public.academies) <> 1 then
    raise exception 'RLS: admin A ve % academias', (select count(*) from public.academies);
  end if;
  if exists (select 1 from public.academies where id = '22222222-2222-4222-8222-222222222222') then
    raise exception 'RLS: admin A ve la academia B';
  end if;
  if (select count(*) from public.groups) <> 2 then
    raise exception 'RLS: admin A no ve todos sus grupos';
  end if;
  if (select count(*) from public.subjects) <> 2 then
    raise exception 'RLS: admin A no ve todos sus cursos';
  end if;
  if (select count(*) from public.guardians) <> 1 then
    raise exception 'RLS: admin A no ve sus apoderados';
  end if;
  if (select count(*) from public.payments) <> 1 then
    raise exception 'RLS: admin A no ve sus pagos';
  end if;
  if not public.can_access_voucher('11111111-1111-4111-8111-111111111111/11111111-1111-4111-8111-0000000000a9/v.png') then
    raise exception 'Storage: admin A no puede leer su voucher';
  end if;
  if public.can_access_voucher('22222222-2222-4222-8222-222222222222/22222222-2222-4222-8222-0000000000b9/v.png') then
    raise exception 'Storage: admin A puede leer el voucher de B';
  end if;
end $$;

reset role;

-- Secretaría A: finanzas propias, sin academia B.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
begin
  if (select count(*) from public.groups) <> 2 then
    raise exception 'RLS: cashier A no ve todos sus grupos';
  end if;
  if (select count(*) from public.subjects) <> 2 then
    raise exception 'RLS: cashier A no ve todos sus cursos';
  end if;
  if (select count(*) from public.guardians) <> 1 then
    raise exception 'RLS: cashier A no ve sus apoderados';
  end if;
  if (select count(*) from public.charges) <> 1 then
    raise exception 'RLS: cashier A no ve sus cargos';
  end if;
  if (select count(*) from public.payments) <> 1 then
    raise exception 'RLS: cashier A no ve sus pagos';
  end if;
  if (select count(*) from public.payments where academy_id = '22222222-2222-4222-8222-222222222222') <> 0 then
    raise exception 'RLS: cashier A ve pagos de B';
  end if;
  if (select role from public.my_access() limit 1) <> 'cashier'::public.membership_role then
    raise exception 'RPC: my_access no devuelve el rol cashier';
  end if;
end $$;

reset role;

-- Docente A: solo su grupo y su asistencia; nada de finanzas ni apoderados.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}';

do $$
begin
  if (select count(*) from public.academies) <> 1 then
    raise exception 'RLS: teacher A ve % academias', (select count(*) from public.academies);
  end if;
  if (select count(*) from public.groups) <> 1 then
    raise exception 'RLS: teacher A ve % grupos y esperaba solo el asignado', (select count(*) from public.groups);
  end if;
  if (select count(*) from public.subjects) <> 1 then
    raise exception 'RLS: teacher A ve % cursos y esperaba solo el asignado', (select count(*) from public.subjects);
  end if;
  if (select count(*) from public.students) <> 2 then
    raise exception 'RLS: teacher A ve % alumnos y esperaba 2', (select count(*) from public.students);
  end if;
  if (select count(*) from public.guardians) <> 0 then
    raise exception 'RLS: teacher A lee apoderados';
  end if;
  if (select count(*) from public.charges) <> 0 then
    raise exception 'RLS: teacher A lee cargos';
  end if;
  if (select count(*) from public.payments) <> 0 then
    raise exception 'RLS: teacher A lee pagos';
  end if;
  if (select count(*) from public.class_sessions) <> 1 then
    raise exception 'RLS: teacher A ve % sesiones y esperaba 1', (select count(*) from public.class_sessions);
  end if;
  if (select count(*) from public.attendance) <> 1 then
    raise exception 'RLS: teacher A ve % asistencias y esperaba 1', (select count(*) from public.attendance);
  end if;
  if public.can_access_voucher('11111111-1111-4111-8111-111111111111/11111111-1111-4111-8111-0000000000a9/v.png') then
    raise exception 'Storage: teacher A puede leer vouchers';
  end if;
end $$;

reset role;

-- Docente B: aislamiento inverso.
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-4000-8000-000000000003","role":"authenticated"}';

do $$
begin
  if (select count(*) from public.students) <> 1 then
    raise exception 'RLS: teacher B ve % alumnos y esperaba 1', (select count(*) from public.students);
  end if;
  if (select count(*) from public.academies) <> 1 then
    raise exception 'RLS: teacher B ve % academias', (select count(*) from public.academies);
  end if;
end $$;

reset role;

-- Escrituras sensibles: secretaría no traslada alumnos ni corrige cargos.
insert into public.students (id, academy_id, group_id, full_name) values
  ('11111111-1111-4111-8111-0000000000af', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000a1', 'Alumno temporal para cupo')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
) values
  ('11111111-1111-4111-8111-0000000000e3', '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-0000000000af', '11111111-1111-4111-8111-0000000000c0', '11111111-1111-4111-8111-0000000000a1', 'active', 200, 200)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
declare
  v_student_id uuid;
begin
  begin
    insert into public.students (academy_id, group_id, full_name)
    values (
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-0000000000a1',
      'Alumno con grupo no autorizado'
    );
    raise exception 'RLS: cashier A creó un alumno con group_id';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.students
    where id = '11111111-1111-4111-8111-0000000000a3';
    raise exception 'RLS: cashier A eliminó un alumno directamente';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.students (academy_id, full_name)
  values ('11111111-1111-4111-8111-111111111111', 'Alumno sin grupo')
  returning id into v_student_id;

  if (select group_id from public.students where id = v_student_id) is not null then
    raise exception 'RLS: cashier A creó un alumno ya asignado a un grupo';
  end if;

  begin
    update public.students
    set group_id = '11111111-1111-4111-8111-0000000000a0'
    where id = '11111111-1111-4111-8111-0000000000a3';
    raise exception 'RLS: cashier A cambió students.group_id directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.charges set amount = 1
    where id = '11111111-1111-4111-8111-0000000000a7';
    raise exception 'RLS: cashier A actualizó un cargo directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.charges
    where id = '11111111-1111-4111-8111-0000000000a7';
    raise exception 'RLS: cashier A eliminó un cargo directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.transfer_student(
      '11111111-1111-4111-8111-0000000000a3',
      '11111111-1111-4111-8111-0000000000a0'
    );
    raise exception 'RLS: cashier A autorizó un traslado por RPC';
  exception
    when insufficient_privilege then null;
  end;
end $$;

reset role;

-- Dirección no edita group_id ni cargos directamente, pero sí autoriza
-- traslados por RPC y el cupo se valida.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
begin
  begin
    insert into public.students (academy_id, group_id, full_name)
    values (
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-0000000000a1',
      'Alumno con grupo no autorizado'
    );
    raise exception 'RLS: admin A creó un alumno con group_id';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.students
    where id = '11111111-1111-4111-8111-0000000000a3';
    raise exception 'RLS: admin A eliminó un alumno directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.students
    set group_id = '11111111-1111-4111-8111-0000000000a0'
    where id = '11111111-1111-4111-8111-0000000000a3';
    raise exception 'RLS: admin A cambió students.group_id directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.charges set amount = 1
    where id = '11111111-1111-4111-8111-0000000000a7';
    raise exception 'RLS: admin A actualizó un cargo directamente';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.charges
    where id = '11111111-1111-4111-8111-0000000000a7';
    raise exception 'RLS: admin A eliminó un cargo directamente';
  exception
    when insufficient_privilege then null;
  end;

  perform public.transfer_student(
    '11111111-1111-4111-8111-0000000000a4',
    '11111111-1111-4111-8111-0000000000a0'
  );
  if (select group_id from public.students where id = '11111111-1111-4111-8111-0000000000a4')
     is distinct from '11111111-1111-4111-8111-0000000000a0'::uuid then
    raise exception 'RPC: admin A no pudo trasladar un alumno';
  end if;

  perform public.transfer_student(
    '11111111-1111-4111-8111-0000000000a3',
    '11111111-1111-4111-8111-0000000000a0'
  );

  begin
    perform public.transfer_student(
      '11111111-1111-4111-8111-0000000000af',
      '11111111-1111-4111-8111-0000000000a0'
    );
    raise exception 'RPC: admin A trasladó a un grupo sin cupo';
  exception
    when check_violation then null;
  end;
end $$;

reset role;

-- Anónimo: sin privilegios de tabla.
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  begin
    perform count(*) from public.academies;
    raise exception 'RLS: anon pudo leer academias';
  exception
    when insufficient_privilege then null;
  end;
end $$;

reset role;

select 'B01 RLS: todas las comprobaciones pasaron' as resultado;
rollback;
