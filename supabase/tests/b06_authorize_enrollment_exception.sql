-- B06/A03 - Autorización de excepción de matrícula.
-- Requiere B01, B02, B03 y 20261122110000_b06_authorize_enrollment_exception.sql.
-- Todo el escenario está en una transacción que termina con ROLLBACK.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'b0600000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b06.admin.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B06 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0600000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b06.cashier.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B06 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0600000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b06.teacher.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B06 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0600000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'b06.admin.b@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B06 B"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name)
values
  ('b0600000-0000-4000-8000-000000000100', 'B06 Academia A'),
  ('b0600000-0000-4000-8000-000000000200', 'B06 Academia B')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role)
values
  ('b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000001', 'admin'),
  ('b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000002', 'cashier'),
  ('b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000003', 'teacher'),
  ('b0600000-0000-4000-8000-000000000200', 'b0600000-0000-4000-8000-000000000004', 'admin')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (id, academy_id, name, start_date, end_date, grade)
values
  ('b0600000-0000-4000-8000-000000000110', 'b0600000-0000-4000-8000-000000000100', 'Ciclo B06 A', '2026-11-01', '2027-01-31', '5.º secundaria'),
  ('b0600000-0000-4000-8000-000000000210', 'b0600000-0000-4000-8000-000000000200', 'Ciclo B06 B', '2026-11-01', '2027-01-31', '5.º secundaria')
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, capacity)
values
  ('b0600000-0000-4000-8000-000000000130', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000110', 'Grupo B06 libre', 5),
  ('b0600000-0000-4000-8000-000000000131', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000110', 'Grupo B06 lleno', 1),
  ('b0600000-0000-4000-8000-000000000230', 'b0600000-0000-4000-8000-000000000200', 'b0600000-0000-4000-8000-000000000210', 'Grupo B06 B', 5)
on conflict (id) do nothing;

insert into public.students (id, academy_id, full_name)
values
  ('b0600000-0000-4000-8000-000000000160', 'b0600000-0000-4000-8000-000000000100', 'Alumno B06 a autorizar'),
  ('b0600000-0000-4000-8000-000000000161', 'b0600000-0000-4000-8000-000000000100', 'Alumno B06 ocupante'),
  ('b0600000-0000-4000-8000-000000000162', 'b0600000-0000-4000-8000-000000000100', 'Alumno B06 grupo lleno'),
  ('b0600000-0000-4000-8000-000000000260', 'b0600000-0000-4000-8000-000000000200', 'Alumno B06 academia B')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
)
values
  ('b0600000-0000-4000-8000-000000000170', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000160', 'b0600000-0000-4000-8000-000000000110', 'b0600000-0000-4000-8000-000000000130', 'pending', 100, 50),
  ('b0600000-0000-4000-8000-000000000171', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000161', 'b0600000-0000-4000-8000-000000000110', 'b0600000-0000-4000-8000-000000000131', 'active', 100, 50),
  ('b0600000-0000-4000-8000-000000000172', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000162', 'b0600000-0000-4000-8000-000000000110', 'b0600000-0000-4000-8000-000000000131', 'pending', 100, 50),
  ('b0600000-0000-4000-8000-000000000270', 'b0600000-0000-4000-8000-000000000200', 'b0600000-0000-4000-8000-000000000260', 'b0600000-0000-4000-8000-000000000210', 'b0600000-0000-4000-8000-000000000230', 'pending', 100, 50)
on conflict (id) do nothing;

insert into public.charges (id, academy_id, student_id, enrollment_id, type, amount, due_date)
values
  ('b0600000-0000-4000-8000-000000000180', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000160', 'b0600000-0000-4000-8000-000000000170', 'registration', 100, '2026-11-10'),
  ('b0600000-0000-4000-8000-000000000181', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000160', 'b0600000-0000-4000-8000-000000000170', 'monthly', 50, '2026-12-10'),
  ('b0600000-0000-4000-8000-000000000182', 'b0600000-0000-4000-8000-000000000100', 'b0600000-0000-4000-8000-000000000162', 'b0600000-0000-4000-8000-000000000172', 'registration', 100, '2026-11-10'),
  ('b0600000-0000-4000-8000-000000000280', 'b0600000-0000-4000-8000-000000000200', 'b0600000-0000-4000-8000-000000000260', 'b0600000-0000-4000-8000-000000000270', 'registration', 100, '2026-11-10')
on conflict (id) do nothing;

insert into public.payments (
  id, academy_id, charge_id, amount, method, reference, voucher_path, status, created_by
)
values (
  'b0600000-0000-4000-8000-000000000190',
  'b0600000-0000-4000-8000-000000000100',
  'b0600000-0000-4000-8000-000000000180',
  25, 'bank_transfer', 'B06-A03-PARTIAL',
  'b0600000-0000-4000-8000-000000000100/b0600000-0000-4000-8000-000000000190/voucher.png',
  'confirmed', 'b0600000-0000-4000-8000-000000000001'
)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0600000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_returned_id uuid;
  v_sqlstate text;
  v_hint text;
  v_occupied integer;
  v_registration_amount numeric;
  v_paid_amount numeric;
  v_charge_count integer;
  v_payment_count integer;
begin
  -- Rol indebido: cashier de la misma academia.
  perform set_config('request.jwt.claims', '{"sub":"b0600000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000170', 'Motivo válido', '2026-12-31'
    );
    raise exception 'B06: cashier autorizó una excepción';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B06: cashier produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Rol indebido: docente.
  perform set_config('request.jwt.claims', '{"sub":"b0600000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000170', 'Motivo válido', '2026-12-31'
    );
    raise exception 'B06: docente autorizó una excepción';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B06: docente produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Admin de otra academia: recurso ajeno e inexistente comparten ENROLLMENT_NOT_FOUND.
  perform set_config('request.jwt.claims', '{"sub":"b0600000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000170', 'Motivo válido', '2026-12-31'
    );
    raise exception 'B06: admin B autorizó una matrícula de A';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> 'P0002' or v_hint <> 'ENROLLMENT_NOT_FOUND' then
      raise exception 'B06: matrícula ajena produjo % / %, se esperaba P0002 / ENROLLMENT_NOT_FOUND', v_sqlstate, v_hint;
    end if;
  end;

  -- Un id inexistente debe tener exactamente el mismo código/hint que un id ajeno.
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000009999', 'Motivo válido', '2026-12-31'
    );
    raise exception 'B06: se aceptó una matrícula inexistente';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> 'P0002' or v_hint <> 'ENROLLMENT_NOT_FOUND' then
      raise exception 'B06: matrícula inexistente produjo % / %, se esperaba P0002 / ENROLLMENT_NOT_FOUND', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"b0600000-0000-4000-8000-000000000001","role":"authenticated"}', true);

  -- Motivo vacío.
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000170', '   ', '2026-12-31'
    );
    raise exception 'B06: se aceptó un motivo vacío';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'EXCEPTION_REASON_REQUIRED' then
      raise exception 'B06: motivo inválido produjo % / %, se esperaba 22023 / EXCEPTION_REASON_REQUIRED', v_sqlstate, v_hint;
    end if;
  end;

  -- Fecha límite ausente.
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000170', 'Motivo válido', null
    );
    raise exception 'B06: se aceptó una fecha límite nula';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'EXCEPTION_DUE_DATE_REQUIRED' then
      raise exception 'B06: fecha inválida produjo % / %, se esperaba 22023 / EXCEPTION_DUE_DATE_REQUIRED', v_sqlstate, v_hint;
    end if;
  end;

  -- Una matrícula que no está pending no puede recibir otra autorización.
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000171', 'Motivo válido', '2026-12-31'
    );
    raise exception 'B06: se autorizó una matrícula active';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'EXCEPTION_STATUS_INVALID' then
      raise exception 'B06: estado inválido produjo % / %, se esperaba 23514 / EXCEPTION_STATUS_INVALID', v_sqlstate, v_hint;
    end if;
  end;

  -- A03: autorización válida. La fecha pasada prueba que no se cancela automáticamente.
  select count(*)::integer into v_charge_count
  from public.charges where enrollment_id = 'b0600000-0000-4000-8000-000000000170';
  select coalesce(sum(amount), 0) into v_registration_amount
  from public.charges where enrollment_id = 'b0600000-0000-4000-8000-000000000170';
  select count(*)::integer, coalesce(sum(amount), 0)
    into v_payment_count, v_paid_amount
  from public.payments where charge_id = 'b0600000-0000-4000-8000-000000000180';

  v_returned_id := public.authorize_enrollment_exception(
    'b0600000-0000-4000-8000-000000000170', '  Inscripción pendiente  ', '2020-01-01'
  );
  if v_returned_id <> 'b0600000-0000-4000-8000-000000000170'::uuid then
    raise exception 'B06: retorno no corresponde a la matrícula autorizada';
  end if;

  if not exists (
    select 1 from public.enrollments e
    where e.id = v_returned_id
      and e.status = 'exception'
      and e.exception_reason = 'Inscripción pendiente'
      and e.exception_due_date = '2020-01-01'
      and e.authorized_by = 'b0600000-0000-4000-8000-000000000001'
      and e.authorized_at is not null
  ) then
    raise exception 'A03: campos de autorización no persistieron';
  end if;

  select occupied into v_occupied
  from public.group_capacity('b0600000-0000-4000-8000-000000000130');
  if v_occupied <> 1 then
    raise exception 'A03: la excepción no ocupó exactamente un cupo';
  end if;

  if (select count(*)::integer from public.charges
      where enrollment_id = v_returned_id) <> v_charge_count
     or (select coalesce(sum(amount), 0) from public.charges
         where enrollment_id = v_returned_id) <> v_registration_amount
     or (select count(*)::integer from public.payments
         where charge_id = 'b0600000-0000-4000-8000-000000000180') <> v_payment_count
     or (select coalesce(sum(amount), 0) from public.payments
         where charge_id = 'b0600000-0000-4000-8000-000000000180') <> v_paid_amount then
    raise exception 'A03: cargos o pagos cambiaron al autorizar excepción';
  end if;

  if 100 - v_paid_amount <= 0 then
    raise exception 'A03: fixture no conserva deuda de inscripción';
  end if;

  -- Grupo lleno: el trigger B02 rechaza la transición sin cambiar la matrícula/cupo.
  begin
    perform public.authorize_enrollment_exception(
      'b0600000-0000-4000-8000-000000000172', 'Motivo de prueba', '2026-12-31'
    );
    raise exception 'A03: se autorizó excepción en grupo lleno';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'GROUP_FULL' then
      raise exception 'A03: grupo lleno produjo % / %, se esperaba 23514 / GROUP_FULL', v_sqlstate, v_hint;
    end if;
  end;

  select occupied into v_occupied
  from public.group_capacity('b0600000-0000-4000-8000-000000000131');
  if v_occupied <> 1
     or (select status from public.enrollments where id = 'b0600000-0000-4000-8000-000000000172') <> 'pending'
     or (select authorized_by from public.enrollments where id = 'b0600000-0000-4000-8000-000000000172') is not null then
    raise exception 'A03: rechazo por cupo modificó estado, autorizador u ocupación';
  end if;
end;
$$;

rollback;
