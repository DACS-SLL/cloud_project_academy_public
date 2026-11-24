-- B06/A04 - traslado, control de cupo e historial append-only.
-- Ejecutar después de B01, B02 y las migraciones B06. Fixtures transaccionales.
begin;

insert into auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
  raw_app_meta_data,raw_user_meta_data,confirmation_token,recovery_token,email_change_token_new,email_change
) values
('00000000-0000-0000-0000-000000000000','b0610000-0000-4000-8000-000000000001','authenticated','authenticated','b06.transfer.admin@test.local','x',now(),now(),now(),'{}','{}','','','',''),
('00000000-0000-0000-0000-000000000000','b0610000-0000-4000-8000-000000000002','authenticated','authenticated','b06.transfer.cashier@test.local','x',now(),now(),now(),'{}','{}','','','',''),
('00000000-0000-0000-0000-000000000000','b0610000-0000-4000-8000-000000000003','authenticated','authenticated','b06.transfer.teacher@test.local','x',now(),now(),now(),'{}','{}','','','',''),
('00000000-0000-0000-0000-000000000000','b0610000-0000-4000-8000-000000000004','authenticated','authenticated','b06.transfer.adminb@test.local','x',now(),now(),now(),'{}','{}','','','','')
on conflict (id) do nothing;

insert into public.academies (id,name) values
('b0610000-0000-4000-8000-000000000100','B06 Traslados A'),
('b0610000-0000-4000-8000-000000000200','B06 Traslados B') on conflict (id) do nothing;
insert into public.memberships (academy_id,user_id,role) values
('b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000001','admin'),
('b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000002','cashier'),
('b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000003','teacher'),
('b0610000-0000-4000-8000-000000000200','b0610000-0000-4000-8000-000000000004','admin')
on conflict (academy_id,user_id) do nothing;
insert into public.cycles (id,academy_id,name,start_date,end_date,grade) values
('b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000100','Ciclo A B06 T','2026-11-01','2027-01-31','5.º secundaria'),
('b0610000-0000-4000-8000-000000000111','b0610000-0000-4000-8000-000000000100','Ciclo B B06 T','2027-02-01','2027-05-31','5.º secundaria'),
('b0610000-0000-4000-8000-000000000210','b0610000-0000-4000-8000-000000000200','Ciclo externo B06 T','2026-11-01','2027-01-31','5.º secundaria')
on conflict (id) do nothing;
insert into public.groups (id,academy_id,cycle_id,name,capacity) values
('b0610000-0000-4000-8000-000000000130','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000110','Origen B06 T',10),
('b0610000-0000-4000-8000-000000000131','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000110','Destino libre B06 T',5),
('b0610000-0000-4000-8000-000000000132','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000110','Destino lleno B06 T',1),
('b0610000-0000-4000-8000-000000000133','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000111','Destino otro ciclo B06 T',5),
('b0610000-0000-4000-8000-000000000230','b0610000-0000-4000-8000-000000000200','b0610000-0000-4000-8000-000000000210','Destino otra academia B06 T',5)
on conflict (id) do nothing;
insert into public.students (id,academy_id,group_id,full_name) values
('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000130','Alumno activo B06 T'),
('b0610000-0000-4000-8000-000000000161','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000130','Alumno excepción B06 T'),
('b0610000-0000-4000-8000-000000000162','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000132','Ocupante B06 T'),
('b0610000-0000-4000-8000-000000000163','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000130','Alumno ciclo distinto B06 T'),
('b0610000-0000-4000-8000-000000000164','b0610000-0000-4000-8000-000000000100',null,'Alumno pending B06 T'),
('b0610000-0000-4000-8000-000000000165','b0610000-0000-4000-8000-000000000100',null,'Alumno cancelled B06 T'),
('b0610000-0000-4000-8000-000000000260','b0610000-0000-4000-8000-000000000200','b0610000-0000-4000-8000-000000000230','Alumno academia externa B06 T')
on conflict (id) do nothing;
insert into public.enrollments (
 id,academy_id,student_id,cycle_id,group_id,status,agreed_registration_price,agreed_monthly_price,
 exception_reason,exception_due_date,authorized_by,authorized_at
) values
('b0610000-0000-4000-8000-000000000170','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000130','active',100,50,null,null,null,null),
('b0610000-0000-4000-8000-000000000171','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000161','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000130','exception',100,50,'Excepción A03','2026-11-30','b0610000-0000-4000-8000-000000000001',now()),
('b0610000-0000-4000-8000-000000000172','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000162','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000132','active',100,50,null,null,null,null),
('b0610000-0000-4000-8000-000000000173','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000163','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000130','active',100,50,null,null,null,null),
('b0610000-0000-4000-8000-000000000174','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000164','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000130','pending',100,50,null,null,null,null),
('b0610000-0000-4000-8000-000000000175','b0610000-0000-4000-8000-000000000100','b0610000-0000-4000-8000-000000000165','b0610000-0000-4000-8000-000000000110','b0610000-0000-4000-8000-000000000130','cancelled',100,50,null,null,null,null),
('b0610000-0000-4000-8000-000000000270','b0610000-0000-4000-8000-000000000200','b0610000-0000-4000-8000-000000000260','b0610000-0000-4000-8000-000000000210','b0610000-0000-4000-8000-000000000230','active',100,50,null,null,null,null)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0610000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$
declare v_sqlstate text; v_hint text; v_count integer; v_occupied integer;
begin
  -- Traslado active: sincroniza estado y registra todos los datos del evento.
  perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000131');
  if (select group_id from public.enrollments where id='b0610000-0000-4000-8000-000000000170') <> 'b0610000-0000-4000-8000-000000000131'::uuid
     or (select group_id from public.students where id='b0610000-0000-4000-8000-000000000160') <> 'b0610000-0000-4000-8000-000000000131'::uuid
     or not exists (select 1 from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000170' and academy_id='b0610000-0000-4000-8000-000000000100' and student_id='b0610000-0000-4000-8000-000000000160' and cycle_id='b0610000-0000-4000-8000-000000000110' and from_group_id='b0610000-0000-4000-8000-000000000130' and to_group_id='b0610000-0000-4000-8000-000000000131' and transferred_by='b0610000-0000-4000-8000-000000000001' and transferred_at is not null)
     or (select count(*) from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000170') <> 1 then
    raise exception 'A04: traslado active no sincronizó o historial incompleto';
  end if;
  -- No-op al grupo actual no registra un segundo traslado.
  perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000131');
  if (select count(*) from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000170') <> 1 then raise exception 'A04: no-op agregó historial'; end if;
  -- También se permite trasladar estado exception.
  perform public.transfer_student('b0610000-0000-4000-8000-000000000161','b0610000-0000-4000-8000-000000000131');
  if (select status from public.enrollments where id='b0610000-0000-4000-8000-000000000171') <> 'exception'
     or (select count(*) from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000171') <> 1 then raise exception 'A04: no conservó estado exception e historial'; end if;
  select occupied into v_occupied from public.group_capacity('b0610000-0000-4000-8000-000000000131');
  if v_occupied <> 2 then raise exception 'A04: destino no contó active y exception'; end if;

  -- Rol no autorizado: estado e historial siguen intactos.
  perform set_config('request.jwt.claims','{"sub":"b0610000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000130');
    raise exception 'A04: cashier pudo trasladar';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '42501' or v_hint <> 'ACCESS_DENIED' then raise exception 'A04: rol indebido devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  if (select group_id from public.enrollments where id='b0610000-0000-4000-8000-000000000170') <> 'b0610000-0000-4000-8000-000000000131'::uuid
     or (select count(*) from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000170') <> 1 then raise exception 'A04: rechazo de rol alteró datos'; end if;

  perform set_config('request.jwt.claims','{"sub":"b0610000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  -- Grupo lleno: error del trigger B02; rollback del update y ausencia de evento.
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000132');
    raise exception 'A04: se aceptó grupo lleno';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'TRANSFER_GROUP_FULL' then raise exception 'A04: grupo lleno devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  if (select group_id from public.enrollments where id='b0610000-0000-4000-8000-000000000170') <> 'b0610000-0000-4000-8000-000000000131'::uuid
     or (select group_id from public.students where id='b0610000-0000-4000-8000-000000000160') <> 'b0610000-0000-4000-8000-000000000131'::uuid
     or (select count(*) from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000170') <> 1 then raise exception 'A04: error de cupo dejó cambios parciales'; end if;
  select occupied into v_occupied from public.group_capacity('b0610000-0000-4000-8000-000000000132');
  if v_occupied <> 1 then raise exception 'A04: rechazo alteró cupo destino'; end if;

  -- Ciclo distinto: se rechaza sin historia ni cambio.
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000163','b0610000-0000-4000-8000-000000000133');
    raise exception 'A04: se aceptó traslado entre ciclos';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'TRANSFER_CROSS_CYCLE' then raise exception 'A04: ciclo distinto devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  if (select group_id from public.enrollments where id='b0610000-0000-4000-8000-000000000173') <> 'b0610000-0000-4000-8000-000000000130'::uuid
     or exists (select 1 from public.enrollment_transfers where enrollment_id='b0610000-0000-4000-8000-000000000173') then raise exception 'A04: rechazo de ciclo alteró datos'; end if;

  -- Pending/cancelled no cuentan como matrículas trasladables.
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000164','b0610000-0000-4000-8000-000000000131');
    raise exception 'A04: se trasladó una matrícula pending';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'TRANSFER_NO_ACTIVE_ENROLLMENT' then raise exception 'A04: pending devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000165','b0610000-0000-4000-8000-000000000131');
    raise exception 'A04: se trasladó una matrícula cancelled';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '23514' or v_hint <> 'TRANSFER_NO_ACTIVE_ENROLLMENT' then raise exception 'A04: cancelled devolvió %/%',v_sqlstate,v_hint; end if;
  end;

  -- Recursos de otra academia se ocultan con códigos equivalentes a no encontrado.
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000260','b0610000-0000-4000-8000-000000000131');
    raise exception 'A04: se encontró alumno ajeno';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'STUDENT_NOT_FOUND' then raise exception 'A04: alumno ajeno devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000199','b0610000-0000-4000-8000-000000000131');
    raise exception 'A04: se encontró alumno inexistente';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'STUDENT_NOT_FOUND' then raise exception 'A04: alumno inexistente devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000230');
    raise exception 'A04: se encontró grupo ajeno';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'GROUP_NOT_FOUND' then raise exception 'A04: grupo ajeno devolvió %/%',v_sqlstate,v_hint; end if;
  end;
  begin
    perform public.transfer_student('b0610000-0000-4000-8000-000000000160','b0610000-0000-4000-8000-000000000199');
    raise exception 'A04: se encontró grupo inexistente';
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_hint=pg_exception_hint;
    if v_sqlstate <> '22023' or v_hint <> 'GROUP_NOT_FOUND' then raise exception 'A04: grupo inexistente devolvió %/%',v_sqlstate,v_hint; end if;
  end;

  if has_table_privilege('authenticated','public.enrollment_transfers','INSERT') or has_table_privilege('authenticated','public.enrollment_transfers','UPDATE') or has_table_privilege('authenticated','public.enrollment_transfers','DELETE') then raise exception 'A04: permisos directos de escritura'; end if;
  if not has_table_privilege('authenticated','public.enrollment_transfers','SELECT') then raise exception 'A04: falta SELECT'; end if;
  -- La policy limita lectura por academia y rol: admin/cashier ven, docente no.
  perform set_config('request.jwt.claims','{"sub":"b0610000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  select count(*) into v_count from public.enrollment_transfers;
  if v_count <> 2 then raise exception 'A04: admin no ve su historial'; end if;
  perform set_config('request.jwt.claims','{"sub":"b0610000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  select count(*) into v_count from public.enrollment_transfers;
  if v_count <> 2 then raise exception 'A04: cashier no ve historial de su academia'; end if;
  perform set_config('request.jwt.claims','{"sub":"b0610000-0000-4000-8000-000000000003","role":"authenticated"}',true);
  select count(*) into v_count from public.enrollment_transfers;
  if v_count <> 0 then raise exception 'A04: docente ve historial'; end if;
end;
$$;
rollback;
