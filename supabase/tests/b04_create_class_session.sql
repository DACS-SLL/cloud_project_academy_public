-- B04 - Contrato de create_class_session.
-- Requiere B01, B02 y 20261120100000_b04_create_class_session.sql.
-- Ejecutar localmente o en SQL Editor; el ROLLBACK no deja datos.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', 'b0400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'b04.teacher@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Teacher B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0400000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b04.cashier@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Cashier B04"}', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b0400000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'b04.admin@test.local', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Admin B04"}', '', '', '', '')
on conflict (id) do nothing;

insert into public.academies (id, name)
values
  ('b0400000-0000-4000-8000-000000000010', 'B04 Academia'),
  ('b0400000-0000-4000-8000-000000000060', 'B04 Academia ajena')
on conflict (id) do nothing;

insert into public.memberships (academy_id, user_id, role)
values
  ('b0400000-0000-4000-8000-000000000010', 'b0400000-0000-4000-8000-000000000001', 'teacher'),
  ('b0400000-0000-4000-8000-000000000010', 'b0400000-0000-4000-8000-000000000002', 'cashier'),
  ('b0400000-0000-4000-8000-000000000010', 'b0400000-0000-4000-8000-000000000003', 'admin')
on conflict (academy_id, user_id) do nothing;

insert into public.cycles (id, academy_id, name, start_date, end_date, grade)
values (
  'b0400000-0000-4000-8000-000000000020',
  'b0400000-0000-4000-8000-000000000010',
  'Ciclo B04', '2026-11-01', '2027-01-31', '5.º secundaria'
)
on conflict (id) do nothing;

insert into public.cycles (id, academy_id, name, start_date, end_date, grade)
values (
  'b0400000-0000-4000-8000-000000000061',
  'b0400000-0000-4000-8000-000000000060',
  'Ciclo B04 ajeno', '2026-11-01', '2027-01-31', '5.º secundaria'
)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, capacity)
values
  ('b0400000-0000-4000-8000-000000000030', 'b0400000-0000-4000-8000-000000000010', 'b0400000-0000-4000-8000-000000000020', 'Grupo asignado B04', 20),
  ('b0400000-0000-4000-8000-000000000031', 'b0400000-0000-4000-8000-000000000010', 'b0400000-0000-4000-8000-000000000020', 'Grupo no asignado B04', 20)
on conflict (id) do nothing;

insert into public.groups (id, academy_id, cycle_id, name, capacity)
values (
  'b0400000-0000-4000-8000-000000000062',
  'b0400000-0000-4000-8000-000000000060',
  'b0400000-0000-4000-8000-000000000061', 'Grupo ajeno B04', 20
)
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name)
values
  ('b0400000-0000-4000-8000-000000000040', 'b0400000-0000-4000-8000-000000000010', 'Curso asignado B04'),
  ('b0400000-0000-4000-8000-000000000041', 'b0400000-0000-4000-8000-000000000010', 'Curso no asignado B04')
on conflict (id) do nothing;

insert into public.subjects (id, academy_id, name)
values (
  'b0400000-0000-4000-8000-000000000063',
  'b0400000-0000-4000-8000-000000000060', 'Curso ajeno B04'
)
on conflict (id) do nothing;

insert into public.teacher_assignments (id, academy_id, teacher_id, group_id, subject_id)
values (
  'b0400000-0000-4000-8000-000000000050',
  'b0400000-0000-4000-8000-000000000010',
  'b0400000-0000-4000-8000-000000000001',
  'b0400000-0000-4000-8000-000000000030',
  'b0400000-0000-4000-8000-000000000040'
)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0400000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare
  v_session_id uuid;
  v_sqlstate text;
  v_hint text;
  v_message text;
  v_initial_count integer;
  v_valid_count integer;
begin
  -- Capturar el baseline con un rol staff que puede leer todas las sesiones
  -- de la academia; un conteo bajo teacher podría ocultar una inserción ajena.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000002","role":"authenticated"}',
    true
  );
  select count(*)::integer into v_initial_count
  from public.class_sessions
  where group_id in (
    'b0400000-0000-4000-8000-000000000030',
    'b0400000-0000-4000-8000-000000000031'
  );

  -- Sin JWT: la función debe fallar antes de consultar o insertar recursos.
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó una llamada sin autenticación';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint;
    if v_sqlstate <> '28000' or v_hint <> 'SESSION_REQUIRED' then
      raise exception 'B04: llamada sin autenticación produjo % / %, se esperaba 28000 / SESSION_REQUIRED', v_sqlstate, v_hint;
    end if;
  end;

  -- Un cashier pertenece a la academia, pero no está autorizado para esta RPC.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000002","role":"authenticated"}',
    true
  );
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó a un usuario cashier';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: llamada cashier produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Dirección tampoco puede crear sesiones en esta versión.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó a un usuario admin';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: llamada admin produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  if (select count(*)::integer from public.class_sessions where group_id in (
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000031'
  )) <> v_initial_count then
    raise exception 'B04: llamadas sin rol autorizado insertaron sesiones';
  end if;

  -- Restaurar la identidad docente para las pruebas de creación autorizada.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  -- Atribución del teacher_id desde auth.uid() y creación válida dentro de ciclo.
  v_session_id := public.create_class_session(
    'b0400000-0000-4000-8000-000000000030',
    'b0400000-0000-4000-8000-000000000040',
    '2026-11-20 10:00:00-05'
  );

  if not exists (
    select 1 from public.class_sessions cs
    where cs.id = v_session_id
      and cs.academy_id = 'b0400000-0000-4000-8000-000000000010'
      and cs.group_id = 'b0400000-0000-4000-8000-000000000030'
      and cs.subject_id = 'b0400000-0000-4000-8000-000000000040'
      and cs.teacher_id = auth.uid()
      and cs.starts_at = '2026-11-20 10:00:00-05'::timestamptz
  ) then
    raise exception 'B04: sesión válida no persistió con los datos derivados correctos';
  end if;

  -- Reintento exacto: la primera llamada creó la sesión; la segunda debe
  -- fallar con el error estable y dejar una única fila para esa combinación.
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó una sesión duplicada';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23505' or v_hint <> 'SESSION_DUPLICATE' then
      raise exception 'B04: duplicado produjo % / %, se esperaba 23505 / SESSION_DUPLICATE', v_sqlstate, v_hint;
    end if;
  end;

  if (select count(*)::integer from public.class_sessions cs
      where cs.academy_id = 'b0400000-0000-4000-8000-000000000010'
        and cs.group_id = 'b0400000-0000-4000-8000-000000000030'
        and cs.subject_id = 'b0400000-0000-4000-8000-000000000040'
        and cs.starts_at = '2026-11-20 10:00:00-05'::timestamptz) <> 1 then
    raise exception 'B04: el reintento dejó cero o más de una sesión';
  end if;

  -- Las fechas inclusivas del ciclo se interpretan como fecha civil en Lima.
  perform public.create_class_session(
    'b0400000-0000-4000-8000-000000000030',
    'b0400000-0000-4000-8000-000000000040',
    '2026-11-01 00:00:00-05'
  );
  perform public.create_class_session(
    'b0400000-0000-4000-8000-000000000030',
    'b0400000-0000-4000-8000-000000000040',
    '2027-01-31 23:59:59-05'
  );
  if not exists (
    select 1 from public.class_sessions cs
    where cs.group_id = 'b0400000-0000-4000-8000-000000000030'
      and cs.starts_at = '2026-11-01 00:00:00-05'::timestamptz
      and cs.teacher_id = auth.uid()
  ) or not exists (
    select 1 from public.class_sessions cs
    where cs.group_id = 'b0400000-0000-4000-8000-000000000030'
      and cs.starts_at = '2027-01-31 23:59:59-05'::timestamptz
      and cs.teacher_id = auth.uid()
  ) then
    raise exception 'B04: se rechazó o no persistió un límite inclusivo del ciclo';
  end if;

  -- Tomar el total como staff para que el control vea toda inserción en la academia.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000002","role":"authenticated"}',
    true
  );
  select count(*)::integer into v_valid_count
  from public.class_sessions
  where group_id in (
    'b0400000-0000-4000-8000-000000000030',
    'b0400000-0000-4000-8000-000000000031'
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  -- Grupo no asignado (curso correcto).
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000031',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó grupo no asignado';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: grupo no asignado produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Curso no asignado (grupo correcto).
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000041',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó curso no asignado';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: curso no asignado produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Los ids de grupos de otra academia no se distinguen de recursos inexistentes.
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000062',
      'b0400000-0000-4000-8000-000000000040',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó grupo de otra academia';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: grupo de otra academia produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- Un curso ajeno tampoco permite averiguar si el id existe fuera de la academia.
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000063',
      '2026-11-20 10:00:00-05'
    );
    raise exception 'B04: se aceptó curso de otra academia';
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_hint = pg_exception_hint,
      v_message = message_text;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED'
       or v_message <> 'Sin acceso a los recursos solicitados' then
      raise exception 'B04: curso de otra academia produjo % / %, se esperaba 42501 / ACCESS_DENIED', v_sqlstate, v_hint;
    end if;
  end;

  -- El instante cae el 1 de febrero en Lima, fuera del ciclo que termina el 31 de enero.
  begin
    perform public.create_class_session(
      'b0400000-0000-4000-8000-000000000030',
      'b0400000-0000-4000-8000-000000000040',
      '2027-02-01 00:00:00-05'
    );
    raise exception 'B04: se aceptó una fecha fuera del ciclo';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'SESSION_OUTSIDE_CYCLE' then
      raise exception 'B04: fecha fuera del ciclo produjo % / %, se esperaba 23514 / SESSION_OUTSIDE_CYCLE', v_sqlstate, v_hint;
    end if;
  end;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0400000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );
  if (select count(*)::integer from public.class_sessions
      where group_id in (
        'b0400000-0000-4000-8000-000000000030',
        'b0400000-0000-4000-8000-000000000031'
      )) <> v_valid_count then
    raise exception 'B04: una llamada rechazada dejó una sesión insertada';
  end if;
end;
$$;

rollback;
