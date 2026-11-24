-- B05 - Prueba reproducible de casos, seguimiento y decisión académica.
-- Requiere B01, B02, B03, B04, B06 y las migraciones B05
-- (20261122130000_b05_alerts_decisions y 20261123100000_b05_debt_overdue_only).
-- Todo ocurre en una transacción con ROLLBACK.
-- Ejecutar:
--   psql "$SUPABASE_DB_URL" -f supabase/tests/b05_alerts_decisions.sql
-- o pegar el contenido en el SQL Editor.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'e0500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b05.admin.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B05 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'e0500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b05.cashier.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B05 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'e0500000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b05.teacher.a@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B05 A"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'e0500000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'b05.admin.b@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B05 B"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name) values
  ('e0500000-0000-4000-8000-000000000100', 'B05 Academia A'),
  ('e0500000-0000-4000-8000-000000000200', 'B05 Academia B')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role) values
  ('e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000001', 'admin'),
  ('e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000002', 'cashier'),
  ('e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000003', 'teacher'),
  ('e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000004', 'admin')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (
  id, academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
) values
  (
    'e0500000-0000-4000-8000-000000000110',
    'e0500000-0000-4000-8000-000000000100',
    'Ciclo B05 vigente', (now() at time zone 'America/Lima')::date - 30,
    (now() at time zone 'America/Lima')::date + 30,
    '5.º secundaria', 2, 4, true
  ),
  (
    'e0500000-0000-4000-8000-000000000120',
    'e0500000-0000-4000-8000-000000000100',
    'Ciclo B05 terminado', (now() at time zone 'America/Lima')::date - 60,
    (now() at time zone 'America/Lima')::date - 1,
    '5.º secundaria', 2, 4, true
  ),
  (
    'e0500000-0000-4000-8000-000000000130',
    'e0500000-0000-4000-8000-000000000100',
    'Ciclo B05 sin tardanza', (now() at time zone 'America/Lima')::date - 30,
    (now() at time zone 'America/Lima')::date + 30,
    '5.º secundaria', 2, 4, false
  ),
  (
    'e0500000-0000-4000-8000-000000000210',
    'e0500000-0000-4000-8000-000000000200',
    'Ciclo B05 ajeno', (now() at time zone 'America/Lima')::date - 30,
    (now() at time zone 'America/Lima')::date + 30,
    '5.º secundaria', 2, 4, true
  )
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, shift, capacity) values
  ('e0500000-0000-4000-8000-000000000140', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000110', 'Grupo B05 A1', 'morning', 10),
  ('e0500000-0000-4000-8000-000000000141', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000110', 'Grupo B05 A2', 'morning', 10),
  ('e0500000-0000-4000-8000-000000000150', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000120', 'Grupo B05 terminado', 'morning', 10),
  ('e0500000-0000-4000-8000-000000000160', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000130', 'Grupo B05 sin tardanza', 'morning', 10),
  ('e0500000-0000-4000-8000-000000000240', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000210', 'Grupo B05 ajeno', 'morning', 10)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name) values
  ('e0500000-0000-4000-8000-000000000170', 'e0500000-0000-4000-8000-000000000100', 'Curso B05 vigente'),
  ('e0500000-0000-4000-8000-000000000171', 'e0500000-0000-4000-8000-000000000100', 'Curso B05 terminado'),
  ('e0500000-0000-4000-8000-000000000172', 'e0500000-0000-4000-8000-000000000100', 'Curso B05 sin tardanza'),
  ('e0500000-0000-4000-8000-000000000270', 'e0500000-0000-4000-8000-000000000200', 'Curso B05 ajeno')
on conflict (id) do nothing;

insert into public.students (id, academy_id, full_name) values
  ('e0500000-0000-4000-8000-000000000180', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 deuda agregada'),
  ('e0500000-0000-4000-8000-000000000181', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 pendiente'),
  ('e0500000-0000-4000-8000-000000000182', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 pagado'),
  ('e0500000-0000-4000-8000-000000000183', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 pago anulado'),
  ('e0500000-0000-4000-8000-000000000184', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 excepción futura'),
  ('e0500000-0000-4000-8000-000000000185', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 excepción vencida'),
  ('e0500000-0000-4000-8000-000000000186', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 faltas abiertas'),
  ('e0500000-0000-4000-8000-000000000187', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 faltas en revisión'),
  ('e0500000-0000-4000-8000-000000000188', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 faltas ciclo terminado'),
  ('e0500000-0000-4000-8000-000000000189', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 tardanza suma'),
  ('e0500000-0000-4000-8000-000000000190', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 tardanza no suma'),
  ('e0500000-0000-4000-8000-000000000191', 'e0500000-0000-4000-8000-000000000100', 'Alumno B05 traslado'),
  ('e0500000-0000-4000-8000-000000000192', 'e0500000-0000-4000-8000-000000000200', 'Alumno B05 de otra academia')
on conflict (id) do nothing;

insert into public.enrollments (
  id, academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price,
  exception_reason, exception_due_date, authorized_by, authorized_at, created_by
) values
  ('e0500000-0000-4000-8000-0000000001a0', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000180', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a1', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000181', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'pending', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000002'),
  ('e0500000-0000-4000-8000-0000000001a2', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000182', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a3', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000183', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a4', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000184', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'exception', 200, 200, 'Excepción B05 futura', (now() at time zone 'America/Lima')::date + 10, 'e0500000-0000-4000-8000-000000000001', now(), 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a5', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000185', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'exception', 200, 200, 'Excepción B05 vencida', (now() at time zone 'America/Lima')::date - 5, 'e0500000-0000-4000-8000-000000000001', now(), 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a6', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000186', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a7', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000187', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a8', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000188', 'e0500000-0000-4000-8000-000000000120', 'e0500000-0000-4000-8000-000000000150', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001a9', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000189', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001aa', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000190', 'e0500000-0000-4000-8000-000000000130', 'e0500000-0000-4000-8000-000000000160', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001ab', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000191', 'e0500000-0000-4000-8000-000000000110', 'e0500000-0000-4000-8000-000000000140', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000001'),
  ('e0500000-0000-4000-8000-0000000001ac', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000192', 'e0500000-0000-4000-8000-000000000210', 'e0500000-0000-4000-8000-000000000240', 'active', 200, 200, null, null, null, null, 'e0500000-0000-4000-8000-000000000004')
on conflict (id) do nothing;

insert into public.charges (
  id, academy_id, student_id, enrollment_id, type, amount, due_date
) values
  ('e0500000-0000-4000-8000-0000000001b0', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000180', 'e0500000-0000-4000-8000-0000000001a0', 'monthly', 200, (now() at time zone 'America/Lima')::date - 10),
  ('e0500000-0000-4000-8000-0000000001b1', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000180', 'e0500000-0000-4000-8000-0000000001a0', 'monthly', 200, (now() at time zone 'America/Lima')::date + 10),
  ('e0500000-0000-4000-8000-0000000001b2', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000181', 'e0500000-0000-4000-8000-0000000001a1', 'registration', 200, (now() at time zone 'America/Lima')::date - 10),
  ('e0500000-0000-4000-8000-0000000001b3', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000182', 'e0500000-0000-4000-8000-0000000001a2', 'monthly', 200, (now() at time zone 'America/Lima')::date - 10),
  ('e0500000-0000-4000-8000-0000000001b4', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000183', 'e0500000-0000-4000-8000-0000000001a3', 'monthly', 200, (now() at time zone 'America/Lima')::date - 10),
  ('e0500000-0000-4000-8000-0000000001b5', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000184', 'e0500000-0000-4000-8000-0000000001a4', 'registration', 200, (now() at time zone 'America/Lima')::date - 30),
  ('e0500000-0000-4000-8000-0000000001b6', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000185', 'e0500000-0000-4000-8000-0000000001a5', 'registration', 200, (now() at time zone 'America/Lima')::date - 30)
on conflict (id) do nothing;

insert into public.payments (
  id, academy_id, charge_id, amount, paid_at, method, reference,
  voucher_path, status, created_by, void_reason, voided_at, voided_by
) values
  ('e0500000-0000-4000-8000-0000000001c0', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001b0', 80, (now() at time zone 'America/Lima')::date - 9, 'bank_transfer', 'B05-P-001', 'b05/test-001.png', 'confirmed', 'e0500000-0000-4000-8000-000000000002', null, null, null),
  ('e0500000-0000-4000-8000-0000000001c1', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001b3', 200, (now() at time zone 'America/Lima')::date - 9, 'bank_transfer', 'B05-P-002', 'b05/test-002.png', 'confirmed', 'e0500000-0000-4000-8000-000000000002', null, null, null),
  ('e0500000-0000-4000-8000-0000000001c2', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001b4', 200, (now() at time zone 'America/Lima')::date - 9, 'bank_transfer', 'B05-P-003', 'b05/test-003.png', 'voided', 'e0500000-0000-4000-8000-000000000002', 'Anulación de prueba B05', now(), 'e0500000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

insert into public.class_sessions (
  id, academy_id, group_id, subject_id, teacher_id, starts_at
) values
  ('e0500000-0000-4000-8000-0000000001d0', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000140', 'e0500000-0000-4000-8000-000000000170', 'e0500000-0000-4000-8000-000000000003', now() - interval '20 days'),
  ('e0500000-0000-4000-8000-0000000001d1', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000140', 'e0500000-0000-4000-8000-000000000170', 'e0500000-0000-4000-8000-000000000003', now() - interval '19 days'),
  ('e0500000-0000-4000-8000-0000000001d2', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000140', 'e0500000-0000-4000-8000-000000000170', 'e0500000-0000-4000-8000-000000000003', now() - interval '18 days'),
  ('e0500000-0000-4000-8000-0000000001d3', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000140', 'e0500000-0000-4000-8000-000000000170', 'e0500000-0000-4000-8000-000000000003', now() - interval '17 days'),
  ('e0500000-0000-4000-8000-0000000001d4', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000150', 'e0500000-0000-4000-8000-000000000171', 'e0500000-0000-4000-8000-000000000003', now() - interval '40 days'),
  ('e0500000-0000-4000-8000-0000000001d5', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000150', 'e0500000-0000-4000-8000-000000000171', 'e0500000-0000-4000-8000-000000000003', now() - interval '39 days'),
  ('e0500000-0000-4000-8000-0000000001d6', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000160', 'e0500000-0000-4000-8000-000000000172', 'e0500000-0000-4000-8000-000000000003', now() - interval '20 days'),
  ('e0500000-0000-4000-8000-0000000001d7', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000160', 'e0500000-0000-4000-8000-000000000172', 'e0500000-0000-4000-8000-000000000003', now() - interval '19 days'),
  ('e0500000-0000-4000-8000-0000000001d8', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-000000000160', 'e0500000-0000-4000-8000-000000000172', 'e0500000-0000-4000-8000-000000000003', now() - interval '18 days'),
  ('e0500000-0000-4000-8000-0000000001d9', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000240', 'e0500000-0000-4000-8000-000000000270', 'e0500000-0000-4000-8000-000000000003', now() - interval '20 days'),
  ('e0500000-0000-4000-8000-0000000001da', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000240', 'e0500000-0000-4000-8000-000000000270', 'e0500000-0000-4000-8000-000000000003', now() - interval '19 days'),
  ('e0500000-0000-4000-8000-0000000001db', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000240', 'e0500000-0000-4000-8000-000000000270', 'e0500000-0000-4000-8000-000000000003', now() - interval '18 days'),
  ('e0500000-0000-4000-8000-0000000001dc', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-000000000240', 'e0500000-0000-4000-8000-000000000270', 'e0500000-0000-4000-8000-000000000003', now() - interval '17 days')
on conflict (id) do nothing;

insert into public.attendance (id, academy_id, session_id, student_id, status) values
  ('e0500000-0000-4000-8000-0000000001e0', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d0', 'e0500000-0000-4000-8000-000000000186', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e1', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d1', 'e0500000-0000-4000-8000-000000000186', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e2', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d0', 'e0500000-0000-4000-8000-000000000187', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e3', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d1', 'e0500000-0000-4000-8000-000000000187', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e4', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d2', 'e0500000-0000-4000-8000-000000000187', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e5', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d3', 'e0500000-0000-4000-8000-000000000187', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e6', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d0', 'e0500000-0000-4000-8000-000000000189', 'late'),
  ('e0500000-0000-4000-8000-0000000001e7', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d1', 'e0500000-0000-4000-8000-000000000189', 'late'),
  ('e0500000-0000-4000-8000-0000000001e8', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d0', 'e0500000-0000-4000-8000-000000000191', 'absent'),
  ('e0500000-0000-4000-8000-0000000001e9', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d1', 'e0500000-0000-4000-8000-000000000191', 'absent'),
  ('e0500000-0000-4000-8000-0000000001ea', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d4', 'e0500000-0000-4000-8000-000000000188', 'absent'),
  ('e0500000-0000-4000-8000-0000000001eb', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d5', 'e0500000-0000-4000-8000-000000000188', 'absent'),
  ('e0500000-0000-4000-8000-0000000001ec', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d6', 'e0500000-0000-4000-8000-000000000190', 'late'),
  ('e0500000-0000-4000-8000-0000000001ed', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d7', 'e0500000-0000-4000-8000-000000000190', 'late'),
  ('e0500000-0000-4000-8000-0000000001ee', 'e0500000-0000-4000-8000-000000000100', 'e0500000-0000-4000-8000-0000000001d8', 'e0500000-0000-4000-8000-000000000190', 'late'),
  ('e0500000-0000-4000-8000-0000000001f0', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-0000000001d9', 'e0500000-0000-4000-8000-000000000192', 'absent'),
  ('e0500000-0000-4000-8000-0000000001f1', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-0000000001da', 'e0500000-0000-4000-8000-000000000192', 'absent'),
  ('e0500000-0000-4000-8000-0000000001f2', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-0000000001db', 'e0500000-0000-4000-8000-000000000192', 'absent'),
  ('e0500000-0000-4000-8000-0000000001f3', 'e0500000-0000-4000-8000-000000000200', 'e0500000-0000-4000-8000-0000000001dc', 'e0500000-0000-4000-8000-000000000192', 'absent')
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0500000-0000-4000-8000-000000000001","role":"authenticated"}';

-- Acceso: sesión, rol, academia y ciclo.
do $$
declare
  v_sqlstate text;
  v_hint text;
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  begin
    perform public.cycle_cases('e0500000-0000-4000-8000-000000000110');
    raise exception 'B05: cycle_cases aceptó una llamada sin sesión';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '28000' or v_hint <> 'SESSION_REQUIRED' then
      raise exception 'B05: sin sesión produjo % / %, se esperaba 28000 / SESSION_REQUIRED', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'call', 'Contacto sin sesión'
    );
    raise exception 'B05: register_followup aceptó una llamada sin sesión';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '28000' or v_hint <> 'SESSION_REQUIRED' then
      raise exception 'B05: followup sin sesión produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'continue', 'Decisión sin sesión'
    );
    raise exception 'B05: register_academic_decision aceptó una llamada sin sesión';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '28000' or v_hint <> 'SESSION_REQUIRED' then
      raise exception 'B05: decisión sin sesión produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  begin
    perform public.cycle_cases('e0500000-0000-4000-8000-000000000110');
    raise exception 'B05: un docente accedió a cycle_cases';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: docente en cycle_cases produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  begin
    perform public.cycle_cases('e0500000-0000-4000-8000-000000000110');
    raise exception 'B05: un admin de otra academia accedió al ciclo';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: admin ajeno produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  begin
    perform public.cycle_cases('e0500000-0000-4000-8000-000000000210');
    raise exception 'B05: admin A accedió al ciclo de la academia B';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: ciclo ajeno produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.cycle_cases('e0500000-0000-4000-8000-000000000999');
    raise exception 'B05: se aceptó un ciclo inexistente';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'CYCLE_NOT_FOUND' then
      raise exception 'B05: ciclo inexistente produjo % / %', v_sqlstate, v_hint;
    end if;
  end;
end;
$$;

-- Casos de deuda y faltas calculados desde la base.
do $$
declare
  v_today date := (now() at time zone 'America/Lima')::date;
  v_case record;
begin
  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000002","role":"authenticated"}', true);

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000180'
    and case_type = 'debt';
  if not found
     or v_case.balance <> 120
     or v_case.total_balance <> 320
     or v_case.due_date <> v_today - 10
     or not v_case.overdue
     or v_case.status <> 'open'
     or v_case.warning_threshold <> 2
     or v_case.review_threshold <> 4 then
    raise exception 'B05: deuda vencida/total incorrecta: %', row_to_json(v_case);
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000181'
    and case_type = 'debt';
  if not found or v_case.balance <> 200 or v_case.total_balance <> 200
     or not v_case.overdue then
    raise exception 'B05: deuda de matrícula pending incorrecta: %', row_to_json(v_case);
  end if;

  if exists (
    select 1 from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
    where student_id = 'e0500000-0000-4000-8000-000000000182'
      and case_type = 'debt'
  ) then
    raise exception 'B05: una deuda pagada siguió apareciendo';
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000183'
    and case_type = 'debt';
  if not found or v_case.balance <> 200 or v_case.total_balance <> 200
     or not v_case.overdue then
    raise exception 'B05: un pago anulado no restauró la deuda: %', row_to_json(v_case);
  end if;

  if exists (
    select 1 from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
    where student_id = 'e0500000-0000-4000-8000-000000000184'
      and case_type = 'debt'
  ) then
    raise exception 'B05: la excepción con fecha futura no debe generar alerta de deuda';
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000185'
    and case_type = 'debt';
  if not found or v_case.balance <> 200 or v_case.total_balance <> 200
     or v_case.due_date <> v_today - 5 or not v_case.overdue then
    raise exception 'B05: la excepción vencida no usó exception_due_date: %', row_to_json(v_case);
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000186'
    and case_type = 'attendance';
  if not found or v_case.absences <> 2 or v_case.status <> 'open'
     or v_case.requires_decision or v_case.balance is not null
     or v_case.total_balance is not null then
    raise exception 'B05: caso de faltas abierto incorrecto: %', row_to_json(v_case);
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000187'
    and case_type = 'attendance';
  if not found or v_case.absences <> 4 or v_case.status <> 'needs_decision'
     or not v_case.requires_decision then
    raise exception 'B05: caso de faltas en revisión incorrecto: %', row_to_json(v_case);
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000189'
    and case_type = 'attendance';
  if not found or v_case.absences <> 2 or v_case.status <> 'open' then
    raise exception 'B05: la tardanza contabilizable no sumó faltas: %', row_to_json(v_case);
  end if;

  if exists (
    select 1 from public.cycle_cases('e0500000-0000-4000-8000-000000000130')
    where student_id = 'e0500000-0000-4000-8000-000000000190'
      and case_type = 'attendance'
  ) then
    raise exception 'B05: la tardanza sumó con late_counts_as_absence=false';
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000120')
  where student_id = 'e0500000-0000-4000-8000-000000000188'
    and case_type = 'attendance';
  if not found or v_case.absences <> 2 or v_case.status <> 'resolved'
     or v_case.requires_decision then
    raise exception 'B05: el caso no se cerró al terminar el ciclo: %', row_to_json(v_case);
  end if;

  if exists (
    select 1 from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
    where student_id = 'e0500000-0000-4000-8000-000000000182'
  ) then
    raise exception 'B05: un alumno sin casos apareció en cycle_cases';
  end if;
end;
$$;

-- Seguimiento: contacto válido y errores estables.
do $$
declare
  v_id uuid;
  v_sqlstate text;
  v_hint text;
  v_case record;
begin
  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000002","role":"authenticated"}', true);

  v_id := public.register_followup(
    'e0500000-0000-4000-8000-000000000187',
    'e0500000-0000-4000-8000-000000000110',
    'call', 'Llamada a apoderado por faltas'
  );
  if v_id is null then raise exception 'B05: no se guardó el seguimiento válido'; end if;

  v_id := public.register_followup(
    'e0500000-0000-4000-8000-000000000180',
    'e0500000-0000-4000-8000-000000000110',
    'whatsapp', 'Mensaje por deuda'
  );
  if v_id is null then raise exception 'B05: no se guardó el seguimiento de deuda'; end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000187'
    and case_type = 'attendance';
  if v_case.status <> 'needs_decision' or v_case.absences <> 4 then
    raise exception 'B05: el contacto alteró el caso de faltas';
  end if;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'sms', 'Canal inválido'
    );
    raise exception 'B05: se aceptó un canal inválido';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'INVALID_FOLLOWUP' then
      raise exception 'B05: canal inválido produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'call', '   '
    );
    raise exception 'B05: se aceptó una nota vacía';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'INVALID_FOLLOWUP' then
      raise exception 'B05: nota vacía produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000182',
      'e0500000-0000-4000-8000-000000000110',
      'call', 'Sin caso'
    );
    raise exception 'B05: se permitió seguimiento sin caso';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'CASE_NOT_FOUND' then
      raise exception 'B05: seguimiento sin caso produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000188',
      'e0500000-0000-4000-8000-000000000120',
      'call', 'Caso cerrado'
    );
    raise exception 'B05: se permitió seguimiento sobre un caso resuelto';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'CASE_NOT_CLOSABLE' then
      raise exception 'B05: seguimiento cerrado produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000192',
      'e0500000-0000-4000-8000-000000000110',
      'call', 'Alumno ajeno'
    );
    raise exception 'B05: se permitió seguimiento de un alumno ajeno';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'CASE_NOT_FOUND' then
      raise exception 'B05: alumno ajeno en followup produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  begin
    perform public.register_followup(
      'e0500000-0000-4000-8000-000000000180',
      'e0500000-0000-4000-8000-000000000110',
      'call', 'Docente'
    );
    raise exception 'B05: un docente registró seguimiento';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: docente en followup produjo % / %', v_sqlstate, v_hint;
    end if;
  end;
end;
$$;

-- Decisión: solo dirección, solo al límite, con historial de varias decisiones.
do $$
declare
  v_id uuid;
  v_sqlstate text;
  v_hint text;
  v_case record;
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'continue', 'Secretaría no decide'
    );
    raise exception 'B05: secretaría registró una decisión académica';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: decisión de secretaría produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'continue', 'Docente no decide'
    );
    raise exception 'B05: docente registró una decisión académica';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then
      raise exception 'B05: decisión de docente produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'promote', 'Decisión inválida'
    );
    raise exception 'B05: se aceptó una decisión inválida';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'INVALID_DECISION' then
      raise exception 'B05: decisión inválida produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'continue', '   '
    );
    raise exception 'B05: se aceptó una decisión sin motivo';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'INVALID_DECISION' then
      raise exception 'B05: decisión sin motivo produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000182',
      'e0500000-0000-4000-8000-000000000110',
      'continue', 'Sin caso'
    );
    raise exception 'B05: se decidió sin caso de faltas';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'CASE_NOT_FOUND' then
      raise exception 'B05: decisión sin caso produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000186',
      'e0500000-0000-4000-8000-000000000110',
      'continue', 'Todavía no llega al límite'
    );
    raise exception 'B05: se decidió antes del límite';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'CASE_NOT_CLOSABLE' then
      raise exception 'B05: decisión antes del límite produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  begin
    perform public.register_academic_decision(
      'e0500000-0000-4000-8000-000000000188',
      'e0500000-0000-4000-8000-000000000120',
      'continue', 'Ciclo terminado bajo el límite'
    );
    raise exception 'B05: se decidió en un caso cerrado bajo el límite';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'CASE_NOT_CLOSABLE' then
      raise exception 'B05: decisión bajo el límite produjo % / %', v_sqlstate, v_hint;
    end if;
  end;

  v_id := public.register_academic_decision(
    'e0500000-0000-4000-8000-000000000187',
    'e0500000-0000-4000-8000-000000000110',
    'continue', 'Acompañamiento y seguimiento'
  );
  if v_id is null then raise exception 'B05: no se guardó la primera decisión'; end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000187'
    and case_type = 'attendance';
  if v_case.status <> 'resolved' or v_case.requires_decision then
    raise exception 'B05: la decisión no resolvió el caso: %', row_to_json(v_case);
  end if;

  v_id := public.register_academic_decision(
    'e0500000-0000-4000-8000-000000000187',
    'e0500000-0000-4000-8000-000000000110',
    'close_case', 'Cierre tras revisión'
  );
  if v_id is null then raise exception 'B05: no se guardó la segunda decisión'; end if;

  select count(*)::integer into v_count
  from public.academic_decisions
  where student_id = 'e0500000-0000-4000-8000-000000000187';
  if v_count <> 2 then
    raise exception 'B05: se esperaban 2 decisiones, hay %', v_count;
  end if;

  select count(*)::integer into v_count
  from public.attendance
  where student_id = 'e0500000-0000-4000-8000-000000000187';
  if v_count <> 4 then
    raise exception 'B05: la decisión alteró asistencias, hay %', v_count;
  end if;
end;
$$;

-- Integración con B06: el traslado no borra faltas históricas del ciclo.
do $$
declare
  v_case record;
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000001","role":"authenticated"}', true);

  perform public.transfer_student(
    'e0500000-0000-4000-8000-000000000191',
    'e0500000-0000-4000-8000-000000000141'
  );

  if (select group_id from public.enrollments where id = 'e0500000-0000-4000-8000-0000000001ab')
       is distinct from 'e0500000-0000-4000-8000-000000000141'::uuid
     or (select group_id from public.students where id = 'e0500000-0000-4000-8000-000000000191')
       is distinct from 'e0500000-0000-4000-8000-000000000141'::uuid then
    raise exception 'B05: el traslado no sincronizó matrícula y alumno';
  end if;

  select count(*)::integer into v_count
  from public.enrollment_transfers
  where student_id = 'e0500000-0000-4000-8000-000000000191';
  if v_count <> 1 then
    raise exception 'B05: el traslado no dejó historial';
  end if;

  select * into v_case
  from public.cycle_cases('e0500000-0000-4000-8000-000000000110')
  where student_id = 'e0500000-0000-4000-8000-000000000191'
    and case_type = 'attendance';
  if not found or v_case.absences <> 2 or v_case.status <> 'open' then
    raise exception 'B05: el traslado perdió faltas históricas: %', row_to_json(v_case);
  end if;
end;
$$;

-- RLS: lectura solo para dirección/secretaría de la academia y escritura por RPC.
do $$
declare
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  select count(*)::integer into v_count from public.followups;
  if v_count <> 0 then raise exception 'B05: docente leyó followups'; end if;
  select count(*)::integer into v_count from public.academic_decisions;
  if v_count <> 0 then raise exception 'B05: docente leyó decisiones'; end if;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  select count(*)::integer into v_count from public.followups;
  if v_count <> 2 then raise exception 'B05: secretaría no leyó sus followups: %', v_count; end if;
  select count(*)::integer into v_count from public.academic_decisions;
  if v_count <> 2 then raise exception 'B05: secretaría no leyó las decisiones: %', v_count; end if;

  begin
    insert into public.followups (academy_id, student_id, cycle_id, channel, note)
    values (
      'e0500000-0000-4000-8000-000000000100',
      'e0500000-0000-4000-8000-000000000187',
      'e0500000-0000-4000-8000-000000000110',
      'call', 'Inserción directa prohibida'
    );
    raise exception 'B05: secretaría insertó un followup directamente';
  exception when insufficient_privilege then
    null;
  end;

  perform set_config('request.jwt.claims', '{"sub":"e0500000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  select count(*)::integer into v_count from public.followups;
  if v_count <> 0 then raise exception 'B05: admin B leyó followups de A'; end if;
  select count(*)::integer into v_count from public.academic_decisions;
  if v_count <> 0 then raise exception 'B05: admin B leyó decisiones de A'; end if;
end;
$$;

select 'B05 OK: deuda vencida 120/320 y sin alerta para la excepción futura' as result;

rollback;
