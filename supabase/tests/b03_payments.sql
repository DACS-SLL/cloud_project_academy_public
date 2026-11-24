-- B03 - Prueba reproducible de pagos, saldo, activación y anulación.
-- Todo ocurre en una transacción con ROLLBACK.
-- Ejecutar después de B01, B02 y B03:
--   psql "$SUPABASE_DB_URL" -f supabase/tests/b03_payments.sql
-- o pegar el contenido en el SQL Editor.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b03.admin.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B03 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b03.cashier.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B03 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b03.teacher.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B03 A"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name) values
  ('55555555-5555-4555-8555-555555555555', 'B03 Academia A')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role) values
  ('55555555-5555-4555-8555-555555555555', 'd0000000-0000-4000-8000-000000000001', 'admin'),
  ('55555555-5555-4555-8555-555555555555', 'd0000000-0000-4000-8000-000000000002', 'cashier'),
  ('55555555-5555-4555-8555-555555555555', 'd0000000-0000-4000-8000-000000000003', 'teacher')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (
  id, academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
) values (
  '55555555-5555-4555-8555-0000000000c1',
  '55555555-5555-4555-8555-555555555555',
  'Ciclo B03', '2026-11-01', '2027-01-31', '5.º secundaria', 10, 15, true
)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, shift, capacity) values
  ('55555555-5555-4555-8555-0000000000a1', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000c1', 'Grupo pago', 'morning', 1),
  ('55555555-5555-4555-8555-0000000000a2', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000c1', 'Grupo lleno pago', 'morning', 1),
  ('55555555-5555-4555-8555-0000000000a3', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000c1', 'Grupo excepción pago', 'afternoon', 1)
on conflict (id) do nothing;

insert into public.students (id, academy_id, full_name) values
  ('55555555-5555-4555-8555-0000000000e1', '55555555-5555-4555-8555-555555555555', 'Alumno pago uno'),
  ('55555555-5555-4555-8555-0000000000e2', '55555555-5555-4555-8555-555555555555', 'Alumno pago dos'),
  ('55555555-5555-4555-8555-0000000000e3', '55555555-5555-4555-8555-555555555555', 'Alumno pago tres'),
  ('55555555-5555-4555-8555-0000000000e4', '55555555-5555-4555-8555-555555555555', 'Alumno pago cuatro')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price,
  exception_reason, exception_due_date, authorized_by, authorized_at
) values
  ('55555555-5555-4555-8555-0000000000f1', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e1', '55555555-5555-4555-8555-0000000000c1', '55555555-5555-4555-8555-0000000000a1', 'pending', 200, 200, null, null, null, null),
  ('55555555-5555-4555-8555-0000000000f2', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e2', '55555555-5555-4555-8555-0000000000c1', '55555555-5555-4555-8555-0000000000a2', 'active', 200, 200, null, null, null, null),
  ('55555555-5555-4555-8555-0000000000f3', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e3', '55555555-5555-4555-8555-0000000000c1', '55555555-5555-4555-8555-0000000000a2', 'pending', 200, 200, null, null, null, null),
  ('55555555-5555-4555-8555-0000000000f4', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e4', '55555555-5555-4555-8555-0000000000c1', '55555555-5555-4555-8555-0000000000a3', 'exception', 200, 200, 'Excepción B03', '2026-11-30', 'd0000000-0000-4000-8000-000000000001', now())
on conflict (id) do nothing;

insert into public.charges (id, academy_id, student_id, enrollment_id, type, amount, due_date) values
  ('55555555-5555-4555-8555-0000000000b1', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e1', '55555555-5555-4555-8555-0000000000f1', 'registration', 200, '2026-11-10'),
  ('55555555-5555-4555-8555-0000000000b2', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e2', '55555555-5555-4555-8555-0000000000f2', 'registration', 200, '2026-11-10'),
  ('55555555-5555-4555-8555-0000000000b3', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e3', '55555555-5555-4555-8555-0000000000f3', 'registration', 200, '2026-11-10'),
  ('55555555-5555-4555-8555-0000000000b4', '55555555-5555-4555-8555-555555555555', '55555555-5555-4555-8555-0000000000e4', '55555555-5555-4555-8555-0000000000f4', 'registration', 200, '2026-11-10')
on conflict (id) do nothing;

-- Objetos privados ficticios para validar la obligatoriedad del voucher.
insert into storage.objects (
  id, bucket_id, name, owner, created_at, updated_at, metadata,
  is_delete_marker, is_versioned
) values
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d1/v.png', null, now(), now(), '{}'::jsonb, false, false),
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d2/v.png', null, now(), now(), '{}'::jsonb, false, false),
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d4/v.png', null, now(), now(), '{}'::jsonb, false, false),
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d5/v.png', null, now(), now(), '{}'::jsonb, false, false),
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d6/v.png', null, now(), now(), '{}'::jsonb, false, false),
  (gen_random_uuid(), 'vouchers', '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d7/v.png', null, now(), now(), '{}'::jsonb, false, false)
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
declare
  v_result record;
  v_hint text;
  v_count integer;
begin
  select * into v_result
  from public.register_payment(
    '55555555-5555-4555-8555-0000000000d1',
    '55555555-5555-4555-8555-0000000000f1',
    '55555555-5555-4555-8555-0000000000b1',
    80, '2026-12-01', 'bank_transfer', 'B03-P-001',
    '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d1/v.png'
  );

  if v_result.charge_balance <> 120 or v_result.enrollment_status <> 'pending' then
    raise exception 'B03: el pago parcial no dejó saldo 120/pending: %/%',
      v_result.charge_balance, v_result.enrollment_status;
  end if;

  select * into v_result
  from public.register_payment(
    '55555555-5555-4555-8555-0000000000d1',
    '55555555-5555-4555-8555-0000000000f1',
    '55555555-5555-4555-8555-0000000000b1',
    80, '2026-12-01', 'bank_transfer', 'B03-P-001',
    '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d1/v.png'
  );

  if not v_result.idempotent then
    raise exception 'B03: el reintento no fue idempotente';
  end if;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d2',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      121, '2026-12-02', 'bank_transfer', 'B03-P-002',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d2/v.png'
    );
    raise exception 'B03: se aceptó un sobrepago';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_OVERPAY' then
        raise exception 'B03: hint inesperado para sobrepago: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d3',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      0, '2026-12-02', 'bank_transfer', 'B03-P-003',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d3/v.png'
    );
    raise exception 'B03: se aceptó un monto cero';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_INVALID_AMOUNT' then
        raise exception 'B03: hint inesperado para monto inválido: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d3',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      10, '2026-12-02', 'bank_transfer', 'B03-P-003', ''
    );
    raise exception 'B03: se aceptó un pago sin voucher';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_VOUCHER_REQUIRED' then
        raise exception 'B03: hint inesperado para voucher faltante: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d3',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      10, '2026-12-02', 'cash', 'B03-P-003',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d3/v.png'
    );
    raise exception 'B03: se aceptó efectivo';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_METHOD_INVALID' then
        raise exception 'B03: hint inesperado para método inválido: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d3',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      10, '2026-12-02', null, 'B03-P-003N', ''
    );
    raise exception 'B03: se aceptó un método nulo';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_METHOD_INVALID' then
        raise exception 'B03: hint inesperado para método nulo: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d3',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      10, '2026-12-02', 'bank_transfer', 'B03-P-003',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d3/v.png'
    );
    raise exception 'B03: se aceptó un voucher inexistente';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_VOUCHER_OBJECT_NOT_FOUND' then
        raise exception 'B03: hint inesperado para voucher inexistente: %', v_hint;
      end if;
  end;

  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d4',
      '55555555-5555-4555-8555-0000000000f1',
      '55555555-5555-4555-8555-0000000000b1',
      10, '2026-12-02', 'bank_transfer', 'B03-P-001',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d4/v.png'
    );
    raise exception 'B03: se aceptó una referencia duplicada';
  exception
    when unique_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_DUPLICATE_REFERENCE' then
        raise exception 'B03: hint inesperado para referencia duplicada: %', v_hint;
      end if;
  end;

  select count(*)::integer into v_count
  from public.payments
  where id in (
    '55555555-5555-4555-8555-0000000000d2',
    '55555555-5555-4555-8555-0000000000d3',
    '55555555-5555-4555-8555-0000000000d4'
  );

  if v_count <> 0 then
    raise exception 'B03: los rechazos dejaron pagos (%)', v_count;
  end if;

  select * into v_result
  from public.register_payment(
    '55555555-5555-4555-8555-0000000000d5',
    '55555555-5555-4555-8555-0000000000f1',
    '55555555-5555-4555-8555-0000000000b1',
    120, '2026-12-03', 'bank_transfer', 'B03-P-005',
    '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d5/v.png'
  );

  if v_result.charge_balance <> 0 or v_result.enrollment_status <> 'active' then
    raise exception 'B03: la inscripción pagada no activó: %/%',
      v_result.charge_balance, v_result.enrollment_status;
  end if;

  if (select group_id from public.students where id = '55555555-5555-4555-8555-0000000000e1')
     is distinct from '55555555-5555-4555-8555-0000000000a1'::uuid then
    raise exception 'B03: la activación no sincronizó el grupo del alumno';
  end if;

  begin
    perform public.void_payment(
      '55555555-5555-4555-8555-0000000000d5',
      'Prueba de anulación por secretaría'
    );
    raise exception 'B03: secretaría anuló un pago';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_VOID_FORBIDDEN' then
        raise exception 'B03: hint inesperado para anulación denegada: %', v_hint;
      end if;
  end;
end $$;

-- La anulación solo la hace dirección y exige motivo.
set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_result record;
  v_hint text;
begin
  begin
    perform public.void_payment(
      '55555555-5555-4555-8555-0000000000d5',
      ''
    );
    raise exception 'B03: se anuló un pago sin motivo';
  exception
    when invalid_parameter_value then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_VOID_REASON_REQUIRED' then
        raise exception 'B03: hint inesperado para motivo faltante: %', v_hint;
      end if;
  end;

  select * into v_result
  from public.void_payment(
    '55555555-5555-4555-8555-0000000000d5',
    'Error de registro B03'
  );

  if v_result.charge_balance <> 120 or v_result.enrollment_status <> 'pending' then
    raise exception 'B03: la anulación no revirtió saldo/matrícula: %/%',
      v_result.charge_balance, v_result.enrollment_status;
  end if;

  if (select group_id from public.students where id = '55555555-5555-4555-8555-0000000000e1') is not null then
    raise exception 'B03: la anulación no liberó el grupo del alumno';
  end if;
end $$;

-- Activación de una matrícula excepcional y reversión a exception al anular.
do $$
declare
  v_result record;
begin
  select * into v_result
  from public.register_payment(
    '55555555-5555-4555-8555-0000000000d7',
    '55555555-5555-4555-8555-0000000000f4',
    '55555555-5555-4555-8555-0000000000b4',
    200, '2026-12-04', 'bank_transfer', 'B03-P-007',
    '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d7/v.png'
  );

  if v_result.enrollment_status <> 'active' then
    raise exception 'B03: la excepción pagada no se activó';
  end if;

  select * into v_result
  from public.void_payment(
    '55555555-5555-4555-8555-0000000000d7',
    'Anulación de excepción B03'
  );

  if v_result.enrollment_status <> 'exception' then
    raise exception 'B03: la anulación no devolvió la excepción a su estado';
  end if;
end $$;

-- Grupo lleno al activar la inscripción: rollback completo del pago.
set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-000000000002","role":"authenticated"}';

do $$
declare
  v_hint text;
begin
  begin
    perform public.register_payment(
      '55555555-5555-4555-8555-0000000000d6',
      '55555555-5555-4555-8555-0000000000f3',
      '55555555-5555-4555-8555-0000000000b3',
      200, '2026-12-04', 'bank_transfer', 'B03-P-006',
      '55555555-5555-4555-8555-555555555555/55555555-5555-4555-8555-0000000000d6/v.png'
    );
    raise exception 'B03: se activó una matrícula en grupo lleno';
  exception
    when check_violation then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint <> 'PAYMENT_GROUP_FULL' then
        raise exception 'B03: hint inesperado para grupo lleno: %', v_hint;
      end if;
  end;

  if exists (
    select 1 from public.payments
    where id = '55555555-5555-4555-8555-0000000000d6'
  ) then
    raise exception 'B03: quedó un pago confirmado tras fallar el cupo';
  end if;
end $$;

reset role;

select 'B03 RLS: todas las comprobaciones pasaron' as resultado;
rollback;

