-- B02 - Prueba reproducible de ciclos, matrícula, cupos y cargos.
-- Todo ocurre dentro de una transacción que termina en ROLLBACK.
-- Ejecutar después de las migraciones de B01 y B02:
--   psql "$SUPABASE_DB_URL" -f supabase/tests/b02_enrollment.sql
-- o pegar el contenido en el SQL Editor.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b02.admin.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B02 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b02.cashier.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B02 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b02.teacher.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B02 A"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name) values
  ('33333333-3333-4333-8333-333333333333', 'B02 Academia A'),
  ('44444444-4444-4444-8444-444444444444', 'B02 Academia B')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role) values
  ('33333333-3333-4333-8333-333333333333', 'c0000000-0000-4000-8000-000000000001', 'admin'),
  ('33333333-3333-4333-8333-333333333333', 'c0000000-0000-4000-8000-000000000002', 'cashier'),
  ('33333333-3333-4333-8333-333333333333', 'c0000000-0000-4000-8000-000000000003', 'teacher')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (
  id, academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
) values
  ('33333333-3333-4333-8333-0000000000c1', '33333333-3333-4333-8333-333333333333', 'Ciclo B02 A', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, true),
  ('33333333-3333-4333-8333-0000000000c2', '33333333-3333-4333-8333-333333333333', 'Ciclo B02 A2', '2027-02-01', '2027-04-30', '5.º secundaria', 10, 15, true),
  ('44444444-4444-4444-8444-0000000000c1', '44444444-4444-4444-8444-444444444444', 'Ciclo B02 B', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, true)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, shift, capacity) values
  ('33333333-3333-4333-8333-0000000000a1', '33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-0000000000c1', 'Grupo B02 lleno', 'morning', 1),
  ('33333333-3333-4333-8333-0000000000a2', '33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-0000000000c1', 'Grupo B02 libre', 'morning', 2),
  ('33333333-3333-4333-8333-0000000000a3', '33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-0000000000c2', 'Grupo B02 otro ciclo', 'afternoon', 2),
  ('44444444-4444-4444-8444-0000000000b1', '44444444-4444-4444-8444-444444444444', '44444444-4444-4444-8444-0000000000c1', 'Grupo B02 B', 'afternoon', 2)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name) values
  ('33333333-3333-4333-8333-0000000000a4', '33333333-3333-4333-8333-333333333333', 'Curso B02 A'),
  ('44444444-4444-4444-8444-0000000000b4', '44444444-4444-4444-8444-444444444444', 'Curso B02 B')
on conflict (id) do nothing;

insert into public.teacher_assignments (id, academy_id, teacher_id, group_id, subject_id) values
  ('33333333-3333-4333-8333-0000000000a5', '33333333-3333-4333-8333-333333333333', 'c0000000-0000-4000-8000-000000000003', '33333333-3333-4333-8333-0000000000a1', '33333333-3333-4333-8333-0000000000a4')
on conflict (id) do nothing;

insert into public.students (id, academy_id, full_name) values
  ('33333333-3333-4333-8333-0000000000e1', '33333333-3333-4333-8333-333333333333', 'Alumno B02 Uno'),
  ('33333333-3333-4333-8333-0000000000e2', '33333333-3333-4333-8333-333333333333', 'Alumno B02 Dos'),
  ('33333333-3333-4333-8333-0000000000e3', '33333333-3333-4333-8333-333333333333', 'Alumno B02 Tres'),
  ('33333333-3333-4333-8333-0000000000e4', '33333333-3333-4333-8333-333333333333', 'Alumno B02 Cuatro')
on conflict (id) do nothing;

-- Secretaría crea una solicitud: queda pendiente, con cargos separados y sin ocupar cupo.
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
declare
  v_enrollment_id uuid;
  v_occupied integer;
  v_charge_count integer;
  v_charge_sum numeric;
  v_student_group uuid;
begin
  v_enrollment_id := public.create_enrollment_request(
    '33333333-3333-4333-8333-0000000000e1',
    '33333333-3333-4333-8333-0000000000a1',
    300,
    200,
    '2026-11-10',
    array['2026-12-10', '2027-01-10', '2027-02-10']::date[]
  );

  if (select status from public.enrollments where id = v_enrollment_id) <> 'pending' then
    raise exception 'B02: la solicitud no quedó pendiente';
  end if;

  select count(*)::integer, coalesce(sum(amount), 0)
    into v_charge_count, v_charge_sum
  from public.charges
  where enrollment_id = v_enrollment_id;

  if v_charge_count <> 4 or v_charge_sum <> 900 then
    raise exception 'B02: cargos incorrectos: % cargos por %', v_charge_count, v_charge_sum;
  end if;

  if (select agreed_registration_price from public.enrollments where id = v_enrollment_id) <> 300
     or (select agreed_monthly_price from public.enrollments where id = v_enrollment_id) <> 200 then
    raise exception 'B02: precio acordado no persistió';
  end if;

  select occupied into v_occupied
  from public.group_capacity('33333333-3333-4333-8333-0000000000a1');

  if v_occupied <> 0 then
    raise exception 'B02: la solicitud pendiente ocupó cupo';
  end if;

  select group_id into v_student_group
  from public.students
  where id = '33333333-3333-4333-8333-0000000000e1';

  if v_student_group is not null then
    raise exception 'B02: la solicitud pendiente asignó grupo al alumno';
  end if;

  begin
    perform public.create_enrollment_request(
      '33333333-3333-4333-8333-0000000000e1',
      '33333333-3333-4333-8333-0000000000a1',
      300,
      200,
      '2026-11-10',
      array['2026-12-10']::date[]
    );
    raise exception 'B02: se permitió una segunda matrícula para el mismo ciclo';
  exception
    when unique_violation then null;
  end;
end $$;

-- Docente no puede crear matrículas.
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000003","role":"authenticated"}';

do $$
begin
  begin
    perform public.create_enrollment_request(
      '33333333-3333-4333-8333-0000000000e2',
      '33333333-3333-4333-8333-0000000000a1',
      300,
      200,
      '2026-11-10',
      array['2026-12-10']::date[]
    );
    raise exception 'B02: un docente creó una matrícula';
  exception
    when insufficient_privilege then null;
  end;
end $$;

-- Secretaría puede solicitar otro alumno al mismo grupo lleno mientras está pendiente.
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
begin
  perform public.create_enrollment_request(
    '33333333-3333-4333-8333-0000000000e2',
    '33333333-3333-4333-8333-0000000000a1',
    300,
    200,
    '2026-11-10',
    array['2026-12-10']::date[]
  );
end $$;

-- Secretaría no puede matricular en otra academia.
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
begin
  begin
    perform public.create_enrollment_request(
      '33333333-3333-4333-8333-0000000000e4',
      '44444444-4444-4444-8444-0000000000b1',
      300,
      200,
      '2026-11-10',
      array['2026-12-10']::date[]
    );
    raise exception 'B02: se matriculó en otra academia';
  exception
    when insufficient_privilege then null;
  end;
end $$;

reset role;

-- Activación simulada por B03: la primera ocupa el único cupo.
do $$
begin
  update public.enrollments
  set status = 'active'
  where student_id = '33333333-3333-4333-8333-0000000000e1';

  if (select group_id from public.students where id = '33333333-3333-4333-8333-0000000000e1')
     is distinct from '33333333-3333-4333-8333-0000000000a1'::uuid then
    raise exception 'B02: la activación no asignó el grupo al alumno';
  end if;

  begin
    update public.enrollments
    set status = 'active'
    where student_id = '33333333-3333-4333-8333-0000000000e2';
    raise exception 'B02: se activó una matrícula en un grupo lleno';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.enrollments (
      academy_id, student_id, cycle_id, group_id, status,
      agreed_registration_price, agreed_monthly_price
    )
    values (
      '33333333-3333-4333-8333-333333333333',
      '33333333-3333-4333-8333-0000000000e1',
      '33333333-3333-4333-8333-0000000000c1',
      '33333333-3333-4333-8333-0000000000a2',
      'active', 300, 200
    );
    raise exception 'B02: se permitió una segunda matrícula activa';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.enrollments (
      academy_id, student_id, cycle_id, group_id, status,
      agreed_registration_price, agreed_monthly_price
    )
    values (
      '33333333-3333-4333-8333-333333333333',
      '33333333-3333-4333-8333-0000000000e4',
      '33333333-3333-4333-8333-0000000000c1',
      '33333333-3333-4333-8333-0000000000a3',
      'active', 300, 200
    );
    raise exception 'B02: se permitió una matrícula con grupo de otro ciclo';
  exception
    when check_violation then null;
  end;
end $$;

-- La excepción también ocupa cupo; el grupo libre tiene 2 asientos.
do $$
declare
  v_enrollment_id uuid;
  v_occupied integer;
  v_available integer;
begin
  v_enrollment_id := public.create_enrollment_request(
    '33333333-3333-4333-8333-0000000000e3',
    '33333333-3333-4333-8333-0000000000a2',
    300,
    200,
    '2026-11-10',
    array['2026-12-10']::date[]
  );

  update public.enrollments
  set status = 'exception',
      exception_reason = 'Excepción autorizada B02',
      exception_due_date = '2026-11-30'
  where id = v_enrollment_id;

  select occupied, available into v_occupied, v_available
  from public.group_capacity('33333333-3333-4333-8333-0000000000a2');

  if v_occupied <> 1 or v_available <> 1 then
    raise exception 'B02: la excepción no ocupó exactamente un cupo (%/%)', v_occupied, v_available;
  end if;
end $$;

-- Traslado consistente: sincroniza matrícula y alumno; rechaza grupo lleno,
-- otra academia y alumno sin matrícula activa/excepcional en el ciclo.
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_hint text;
begin
  perform public.transfer_student(
    '33333333-3333-4333-8333-0000000000e1',
    '33333333-3333-4333-8333-0000000000a2'
  );

  if (select group_id from public.enrollments
      where student_id = '33333333-3333-4333-8333-0000000000e1'
        and cycle_id = '33333333-3333-4333-8333-0000000000c1')
     is distinct from '33333333-3333-4333-8333-0000000000a2'::uuid then
    raise exception 'B02: el traslado no actualizó la matrícula';
  end if;

  if (select group_id from public.students
      where id = '33333333-3333-4333-8333-0000000000e1')
     is distinct from '33333333-3333-4333-8333-0000000000a2'::uuid then
    raise exception 'B02: el traslado no sincronizó students.group_id';
  end if;

  begin
    perform public.transfer_student(
      '33333333-3333-4333-8333-0000000000e1',
      '44444444-4444-4444-8444-0000000000b1'
    );
    raise exception 'B02: se permitió un traslado entre academias';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'GROUP_NOT_FOUND' then
        raise exception 'B02: hint inesperado para grupo ajeno: %', v_hint;
      end if;
  end;

  begin
    perform public.transfer_student(
      '33333333-3333-4333-8333-0000000000e2',
      '33333333-3333-4333-8333-0000000000a2'
    );
    raise exception 'B02: se trasladó un alumno sin matrícula activa';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'TRANSFER_NO_ACTIVE_ENROLLMENT' then
        raise exception 'B02: hint inesperado para matrícula requerida: %', v_hint;
      end if;
  end;
end $$;

reset role;

-- Alumno e4 con matrícula activa en el grupo A1, todavía con cupo.
insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
) values (
  '33333333-3333-4333-8333-0000000000e4',
  '33333333-3333-4333-8333-333333333333',
  '33333333-3333-4333-8333-0000000000e4',
  '33333333-3333-4333-8333-0000000000c1',
  '33333333-3333-4333-8333-0000000000a1',
  'active', 300, 200
)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_hint text;
begin
  begin
    perform public.transfer_student(
      '33333333-3333-4333-8333-0000000000e4',
      '33333333-3333-4333-8333-0000000000a2'
    );
    raise exception 'B02: se trasladó a un grupo lleno';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'TRANSFER_GROUP_FULL' then
        raise exception 'B02: hint inesperado para grupo lleno en traslado: %', v_hint;
      end if;
  end;

  begin
    update public.groups
    set capacity = 1
    where id = '33333333-3333-4333-8333-0000000000a2';
    raise exception 'B02: se bajó la capacidad bajo el cupo ocupado';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'GROUP_CAPACITY_BELOW_OCCUPIED' then
        raise exception 'B02: hint inesperado para capacidad inválida: %', v_hint;
      end if;
  end;

  begin
    update public.groups
    set cycle_id = '33333333-3333-4333-8333-0000000000c2'
    where id = '33333333-3333-4333-8333-0000000000a2';
    raise exception 'B02: se cambió el ciclo de un grupo con matrículas';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'GROUP_CYCLE_HAS_ENROLLMENTS' then
        raise exception 'B02: hint inesperado para cambio de ciclo: %', v_hint;
      end if;
  end;
end $$;

reset role;

select 'B02 RLS: todas las comprobaciones pasaron' as resultado;
rollback;
