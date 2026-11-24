-- B03+B06 - Recorrido integrado de excepción, pago, traslado y anulación.
-- Requiere B01/B02/B03/B06 aplicadas. Todo el escenario termina en ROLLBACK.
-- Ejecutar: psql "$SUPABASE_DB_URL" -f supabase/tests/b06_payment_exception_integration.sql

begin;

insert into auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
  raw_app_meta_data,raw_user_meta_data,confirmation_token,recovery_token,email_change_token_new,email_change
) values
  ('00000000-0000-0000-0000-000000000000','b0670000-0000-4000-8000-000000000001','authenticated','authenticated','b067.admin@test.local','x',now(),now(),now(),'{}','{}','','','',''),
  ('00000000-0000-0000-0000-000000000000','b0670000-0000-4000-8000-000000000002','authenticated','authenticated','b067.cashier@test.local','x',now(),now(),now(),'{}','{}','','','','');

insert into public.academies (id,name)
values ('b0670000-0000-4000-8000-000000000100','B03+B06 integración') on conflict (id) do nothing;
insert into public.memberships (academy_id,user_id,role) values
  ('b0670000-0000-4000-8000-000000000100','b0670000-0000-4000-8000-000000000001','admin'),
  ('b0670000-0000-4000-8000-000000000100','b0670000-0000-4000-8000-000000000002','cashier')
on conflict (academy_id,user_id) do nothing;
insert into public.cycles (id,academy_id,name,start_date,end_date,grade)
values ('b0670000-0000-4000-8000-000000000110','b0670000-0000-4000-8000-000000000100','Ciclo B03+B06','2026-11-01','2027-01-31','5.º secundaria')
on conflict (id) do nothing;
insert into public.groups (id,academy_id,cycle_id,name,shift,capacity) values
  ('b0670000-0000-4000-8000-000000000130','b0670000-0000-4000-8000-000000000100','b0670000-0000-4000-8000-000000000110','Origen integración','morning',1),
  ('b0670000-0000-4000-8000-000000000131','b0670000-0000-4000-8000-000000000100','b0670000-0000-4000-8000-000000000110','Destino integración','afternoon',1)
on conflict (id) do nothing;
insert into public.students (id,academy_id,full_name)
values ('b0670000-0000-4000-8000-000000000160','b0670000-0000-4000-8000-000000000100','Alumno B03+B06')
on conflict (id) do nothing;

-- register_payment valida el objeto y la ruta academia/payment_id/archivo.
insert into storage.objects (
  id,bucket_id,name,owner,created_at,updated_at,metadata,is_delete_marker,is_versioned
) values (
  gen_random_uuid(),'vouchers',
  'b0670000-0000-4000-8000-000000000100/b0670000-0000-4000-8000-0000000000d1/v.png',
  null,now(),now(),'{}'::jsonb,false,false
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0670000-0000-4000-8000-000000000002","role":"authenticated"}';

-- Crear la matrícula pending y sus cargos mediante la RPC B02 real.
do $$
declare
  v_enrollment_id uuid;
  v_registration_charge_id uuid;
  v_occupied integer;
begin
  v_enrollment_id := public.create_enrollment_request(
    'b0670000-0000-4000-8000-000000000160',
    'b0670000-0000-4000-8000-000000000130',
    200,150,'2026-11-10',array['2026-12-10']::date[]
  );
  select c.id into v_registration_charge_id
  from public.charges c
  where c.enrollment_id=v_enrollment_id and c.type='registration';
  perform set_config('b067.enrollment_id',v_enrollment_id::text,true);
  perform set_config('b067.registration_charge_id',v_registration_charge_id::text,true);

  select occupied into v_occupied
  from public.group_capacity('b0670000-0000-4000-8000-000000000130');
  if (select status from public.enrollments where id=v_enrollment_id) <> 'pending'
     or (select count(*) from public.charges where enrollment_id=v_enrollment_id) <> 2
     or (select amount from public.charges where id=v_registration_charge_id) <> 200
     or exists (select 1 from public.payments where charge_id=v_registration_charge_id)
     or v_occupied <> 0 then
    raise exception 'B03+B06: RPC no creó matrícula pending con inscripción impaga y sin ocupación';
  end if;
end;
$$;

-- Dirección autoriza excepción; la deuda permanece y el trigger B02 ocupa el grupo.
set local request.jwt.claims = '{"sub":"b0670000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$
declare v_occupied integer; v_enrollment_id uuid := current_setting('b067.enrollment_id')::uuid;
begin
  if public.authorize_enrollment_exception(v_enrollment_id,'Excepción por pago pendiente','2026-12-31') <> v_enrollment_id then
    raise exception 'B03+B06: RPC de excepción devolvió otra matrícula';
  end if;
  select occupied into v_occupied from public.group_capacity('b0670000-0000-4000-8000-000000000130');
  if (select status from public.enrollments where id=v_enrollment_id) <> 'exception'
     or (select exception_reason from public.enrollments where id=v_enrollment_id) <> 'Excepción por pago pendiente'
     or (select exception_due_date from public.enrollments where id=v_enrollment_id) <> '2026-12-31'::date
     or (select authorized_by from public.enrollments where id=v_enrollment_id) <> 'b0670000-0000-4000-8000-000000000001'::uuid
     or (select authorized_at from public.enrollments where id=v_enrollment_id) is null
     or (select group_id from public.students where id='b0670000-0000-4000-8000-000000000160') <> 'b0670000-0000-4000-8000-000000000130'::uuid
     or (select count(*) from public.payments p join public.charges c on c.id=p.charge_id where c.enrollment_id=v_enrollment_id) <> 0
     or v_occupied <> 1 then
    raise exception 'B03+B06: excepción no conservó deuda/autorización o no ocupó cupo';
  end if;
end;
$$;

-- Secretaría registra el pago íntegro de inscripción con voucher existente.
set local request.jwt.claims = '{"sub":"b0670000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$
declare
  v_result record;
  v_enrollment_id uuid := current_setting('b067.enrollment_id')::uuid;
  v_charge_id uuid := current_setting('b067.registration_charge_id')::uuid;
begin
  select * into v_result from public.register_payment(
    'b0670000-0000-4000-8000-0000000000d1',v_enrollment_id,v_charge_id,
    200,'2026-11-21','bank_transfer','B067-INSCRIPCION-001',
    'b0670000-0000-4000-8000-000000000100/b0670000-0000-4000-8000-0000000000d1/v.png'
  );
  if v_result.charge_balance <> 0 or v_result.enrollment_status <> 'active' or v_result.idempotent then
    raise exception 'B03+B06: pago no activó la matrícula excepcional: saldo %, estado %',v_result.charge_balance,v_result.enrollment_status;
  end if;
end;
$$;

-- El estado active conserva los metadatos de autorización excepcional.
do $$
declare v_enrollment_id uuid := current_setting('b067.enrollment_id')::uuid;
begin
  if (select status from public.enrollments where id=v_enrollment_id) <> 'active'
     or (select exception_reason from public.enrollments where id=v_enrollment_id) <> 'Excepción por pago pendiente'
     or (select exception_due_date from public.enrollments where id=v_enrollment_id) <> '2026-12-31'::date
     or (select authorized_by from public.enrollments where id=v_enrollment_id) <> 'b0670000-0000-4000-8000-000000000001'::uuid
     or (select authorized_at from public.enrollments where id=v_enrollment_id) is null
     or (select count(*) from public.payments p join public.charges c on c.id=p.charge_id
         where c.enrollment_id=v_enrollment_id and c.type='registration' and p.status='confirmed' and p.amount=200) <> 1 then
    raise exception 'B03+B06: activación no conservó autorización o relación de pago';
  end if;
end;
$$;

-- Dirección traslada la matrícula vigente y deja historial dentro de la transacción.
set local request.jwt.claims = '{"sub":"b0670000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$
declare v_enrollment_id uuid := current_setting('b067.enrollment_id')::uuid;
begin
  perform public.transfer_student('b0670000-0000-4000-8000-000000000160','b0670000-0000-4000-8000-000000000131');
  if (select group_id from public.enrollments where id=v_enrollment_id) <> 'b0670000-0000-4000-8000-000000000131'::uuid
     or (select group_id from public.students where id='b0670000-0000-4000-8000-000000000160') <> 'b0670000-0000-4000-8000-000000000131'::uuid
     or (select count(*) from public.enrollment_transfers where enrollment_id=v_enrollment_id
         and academy_id='b0670000-0000-4000-8000-000000000100'
         and from_group_id='b0670000-0000-4000-8000-000000000130'
         and to_group_id='b0670000-0000-4000-8000-000000000131'
         and transferred_by='b0670000-0000-4000-8000-000000000001') <> 1
     or (select count(*) from public.charges where enrollment_id=v_enrollment_id) <> 2
     or (select count(*) from public.payments p join public.charges c on c.id=p.charge_id where c.enrollment_id=v_enrollment_id) <> 1 then
    raise exception 'B03+B06: traslado o relaciones de cargos/pagos/historial incorrectos';
  end if;
end;
$$;

-- Anular el pago como dirección: el saldo retorna y la matrícula vuelve a exception.
do $$
declare v_result record; v_enrollment_id uuid := current_setting('b067.enrollment_id')::uuid;
begin
  select * into v_result from public.void_payment('b0670000-0000-4000-8000-0000000000d1','Anulación de integración B03+B06');
  if v_result.status <> 'voided' or v_result.charge_balance <> 200 or v_result.enrollment_status <> 'exception' then
    raise exception 'B03+B06: anulación no restauró deuda/excepción: %/%/%',v_result.status,v_result.charge_balance,v_result.enrollment_status;
  end if;
  if (select status from public.enrollments where id=v_enrollment_id) <> 'exception'
     or (select group_id from public.enrollments where id=v_enrollment_id) <> 'b0670000-0000-4000-8000-000000000131'::uuid
     or (select group_id from public.students where id='b0670000-0000-4000-8000-000000000160') <> 'b0670000-0000-4000-8000-000000000131'::uuid
     or (select exception_reason from public.enrollments where id=v_enrollment_id) <> 'Excepción por pago pendiente'
     or (select exception_due_date from public.enrollments where id=v_enrollment_id) <> '2026-12-31'::date
     or (select authorized_by from public.enrollments where id=v_enrollment_id) <> 'b0670000-0000-4000-8000-000000000001'::uuid
     or (select authorized_at from public.enrollments where id=v_enrollment_id) is null
     or (select count(*) from public.payments p join public.charges c on c.id=p.charge_id
         where p.id='b0670000-0000-4000-8000-0000000000d1' and p.status='voided'
           and p.voided_by='b0670000-0000-4000-8000-000000000001'
           and c.id=current_setting('b067.registration_charge_id')::uuid and c.enrollment_id=v_enrollment_id) <> 1
     or (select count(*) from public.charges where enrollment_id=v_enrollment_id) <> 2
     or (select count(*) from public.enrollment_transfers where enrollment_id=v_enrollment_id) <> 1
     or (select occupied from public.group_capacity('b0670000-0000-4000-8000-000000000131')) <> 1
     or (select occupied from public.group_capacity('b0670000-0000-4000-8000-000000000130')) <> 0 then
    raise exception 'B03+B06: anulación perdió deuda, destino, sincronización o historial';
  end if;
end;
$$;

rollback;
