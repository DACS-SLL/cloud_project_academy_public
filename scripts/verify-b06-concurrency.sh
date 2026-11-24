#!/usr/bin/env bash
set -Eeuo pipefail

# Prueba de concurrencia B06: ejecutar solo contra el contenedor local dedicado.
readonly CONTAINER="supabase_db_cloud_project_academy_b06_test"
readonly ACADEMY="b0660000-0000-4000-8000-000000000100"
readonly CYCLE="b0660000-0000-4000-8000-000000000110"
readonly SOURCE="b0660000-0000-4000-8000-000000000130"
readonly DEST="b0660000-0000-4000-8000-000000000131"
readonly ADMIN="b0660000-0000-4000-8000-000000000001"
readonly STUDENT1="b0660000-0000-4000-8000-000000000160"
readonly STUDENT2="b0660000-0000-4000-8000-000000000161"
readonly ENROLLMENT1="b0660000-0000-4000-8000-000000000170"
readonly ENROLLMENT2="b0660000-0000-4000-8000-000000000171"
readonly OCCUPANT="b0660000-0000-4000-8000-000000000162"
readonly TEMP_DIR="$(mktemp -d)"

cleanup_fixtures() {
  docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null 2>&1 <<'SQL' || true
delete from public.enrollment_transfers
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or enrollment_id in ('b0660000-0000-4000-8000-000000000170','b0660000-0000-4000-8000-000000000171','b0660000-0000-4000-8000-000000000172')
   or student_id in ('b0660000-0000-4000-8000-000000000160','b0660000-0000-4000-8000-000000000161','b0660000-0000-4000-8000-000000000162');
delete from public.enrollments
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or id in ('b0660000-0000-4000-8000-000000000170','b0660000-0000-4000-8000-000000000171','b0660000-0000-4000-8000-000000000172')
   or student_id in ('b0660000-0000-4000-8000-000000000160','b0660000-0000-4000-8000-000000000161','b0660000-0000-4000-8000-000000000162');
delete from public.students
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or id in ('b0660000-0000-4000-8000-000000000160','b0660000-0000-4000-8000-000000000161','b0660000-0000-4000-8000-000000000162');
delete from public.groups
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or id in ('b0660000-0000-4000-8000-000000000130','b0660000-0000-4000-8000-000000000131');
delete from public.cycles
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or id = 'b0660000-0000-4000-8000-000000000110';
delete from public.memberships
where academy_id = 'b0660000-0000-4000-8000-000000000100'
   or user_id = 'b0660000-0000-4000-8000-000000000001';
delete from public.academies where id = 'b0660000-0000-4000-8000-000000000100';
delete from auth.users where id = 'b0660000-0000-4000-8000-000000000001';
SQL
  rm -rf "$TEMP_DIR"
}
trap cleanup_fixtures EXIT

if ! command -v docker >/dev/null || ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "ERROR: no se encuentra el contenedor local requerido: $CONTAINER" >&2
  exit 2
fi
if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != true ]]; then
  echo "ERROR: el contenedor $CONTAINER no está en ejecución" >&2
  exit 2
fi

psql_local() {
  docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

# Limpia cualquier resto de una ejecución interrumpida antes de reservar los IDs.
cleanup_fixtures
mkdir -p "$TEMP_DIR"

psql_local <<'SQL'
insert into auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
  raw_app_meta_data,raw_user_meta_data,confirmation_token,recovery_token,email_change_token_new,email_change
) values (
  '00000000-0000-0000-0000-000000000000','b0660000-0000-4000-8000-000000000001',
  'authenticated','authenticated','b06.concurrent.admin@test.local','x',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}','','','',''
);
insert into public.academies (id,name) values ('b0660000-0000-4000-8000-000000000100','B06 concurrencia local');
insert into public.memberships (academy_id,user_id,role)
values ('b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000001','admin');
insert into public.cycles (id,academy_id,name,start_date,end_date,grade)
values ('b0660000-0000-4000-8000-000000000110','b0660000-0000-4000-8000-000000000100',
        'Ciclo concurrencia B06','2026-11-01','2027-01-31','5.º secundaria');
insert into public.groups (id,academy_id,cycle_id,name,capacity) values
 ('b0660000-0000-4000-8000-000000000130','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000110','Origen concurrencia',3),
 ('b0660000-0000-4000-8000-000000000131','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000110','Destino última vacante',2);
insert into public.students (id,academy_id,group_id,full_name) values
 ('b0660000-0000-4000-8000-000000000160','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000130','Alumno concurrente 1'),
 ('b0660000-0000-4000-8000-000000000161','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000130','Alumno concurrente 2'),
 ('b0660000-0000-4000-8000-000000000162','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000131','Ocupante destino');
insert into public.enrollments (id,academy_id,student_id,cycle_id,group_id,status,agreed_registration_price,agreed_monthly_price) values
 ('b0660000-0000-4000-8000-000000000170','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000160','b0660000-0000-4000-8000-000000000110','b0660000-0000-4000-8000-000000000130','active',100,50),
 ('b0660000-0000-4000-8000-000000000171','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000161','b0660000-0000-4000-8000-000000000110','b0660000-0000-4000-8000-000000000130','active',100,50),
 ('b0660000-0000-4000-8000-000000000172','b0660000-0000-4000-8000-000000000100','b0660000-0000-4000-8000-000000000162','b0660000-0000-4000-8000-000000000110','b0660000-0000-4000-8000-000000000131','active',100,50);
SQL

occupied=$(psql_local -Atc "select count(*) from public.enrollments where group_id='$DEST' and status in ('active','exception')")
[[ "$occupied" == 1 ]] || { echo "ERROR: destino debe iniciar con exactamente una matrícula activa; tiene $occupied" >&2; exit 1; }

run_transfer() {
  local student_id="$1" output="$2"
  docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -v student_id="$student_id" -v admin_id="$ADMIN" -v dest_id="$DEST" >"$output" 2>&1 <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'admin_id', 'role', 'authenticated')::text, true);
select set_config('b06.student_id', :'student_id', true);
select set_config('b06.dest_id', :'dest_id', true);
do $$
declare v_hint text;
begin
  perform public.transfer_student(current_setting('b06.student_id')::uuid, current_setting('b06.dest_id')::uuid);
  raise notice 'B06_RESULT=SUCCESS';
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  if sqlstate = '23514' and v_hint = 'TRANSFER_GROUP_FULL' then
    raise notice 'B06_RESULT=TRANSFER_GROUP_FULL';
  else
    raise;
  end if;
end;
$$;
commit;
SQL
}

# Inicia dos clientes PostgreSQL distintos antes de esperar a cualquiera.
run_transfer "$STUDENT1" "$TEMP_DIR/transfer1.log" & pid1=$!
run_transfer "$STUDENT2" "$TEMP_DIR/transfer2.log" & pid2=$!
if wait "$pid1"; then
  status1=0
else
  status1=$?
fi
if wait "$pid2"; then
  status2=0
else
  status2=$?
fi
if (( status1 != 0 || status2 != 0 )); then
  cat "$TEMP_DIR/transfer1.log" "$TEMP_DIR/transfer2.log" >&2
  echo "ERROR: conexiones psql finalizaron con estados $status1 y $status2" >&2
  exit 1
fi

successes=$(awk '/B06_RESULT=SUCCESS/ { count++ } END { print count+0 }' "$TEMP_DIR"/transfer1.log "$TEMP_DIR"/transfer2.log)
fulls=$(awk '/B06_RESULT=TRANSFER_GROUP_FULL/ { count++ } END { print count+0 }' "$TEMP_DIR"/transfer1.log "$TEMP_DIR"/transfer2.log)
(( successes == 1 && fulls == 1 )) || {
  cat "$TEMP_DIR"/transfer1.log "$TEMP_DIR"/transfer2.log >&2
  echo "ERROR: resultados esperados: un SUCCESS y un TRANSFER_GROUP_FULL (obtenidos $successes y $fulls)" >&2
  exit 1
}

psql_local -v student1="$STUDENT1" -v student2="$STUDENT2" -v enrollment1="$ENROLLMENT1" -v enrollment2="$ENROLLMENT2" -v dest="$DEST" <<'SQL'
select set_config('b06.student1', :'student1', false);
select set_config('b06.student2', :'student2', false);
select set_config('b06.dest', :'dest', false);
do $$
declare v_occupied integer; v_successes integer; v_failures integer; v_history integer;
begin
  select count(*) into v_occupied from public.enrollments
   where group_id = current_setting('b06.dest')::uuid and status in ('active','exception');
  if v_occupied <> 2 then raise exception 'B06 concurrency: sobrecupo o cupo sin ocupar: %', v_occupied; end if;

  select count(*) into v_successes
  from public.enrollments e join public.students s on s.id=e.student_id
  where e.student_id in (current_setting('b06.student1')::uuid, current_setting('b06.student2')::uuid)
    and e.group_id=current_setting('b06.dest')::uuid and s.group_id=current_setting('b06.dest')::uuid;
  if v_successes <> 1 then raise exception 'B06 concurrency: matrícula/alumno no sincronizados; traslados correctos=%',v_successes; end if;

  select count(*) into v_failures
  from public.enrollments e join public.students s on s.id=e.student_id
  where e.student_id in (current_setting('b06.student1')::uuid, current_setting('b06.student2')::uuid)
    and e.group_id='b0660000-0000-4000-8000-000000000130'::uuid
    and s.group_id='b0660000-0000-4000-8000-000000000130'::uuid;
  if v_failures <> 1 then raise exception 'B06 concurrency: matrícula/alumno del rechazo cambiaron'; end if;

  select count(*) into v_history from public.enrollment_transfers
  where student_id in (current_setting('b06.student1')::uuid, current_setting('b06.student2')::uuid);
  if v_history <> 1 then raise exception 'B06 concurrency: historial esperado=1, actual=%',v_history; end if;
  if exists (
    select 1 from public.enrollment_transfers t join public.enrollments e on e.id=t.enrollment_id
    where t.student_id in (current_setting('b06.student1')::uuid, current_setting('b06.student2')::uuid)
      and (t.from_group_id <> 'b0660000-0000-4000-8000-000000000130'::uuid or t.to_group_id <> e.group_id)
  ) then raise exception 'B06 concurrency: historial no corresponde al traslado exitoso'; end if;
end;
$$;
SQL

echo "OK: dos conexiones concurrentes; una transferencia exitosa, una TRANSFER_GROUP_FULL, sin sobrecupo, matrícula/alumno sincronizados e historial único."
