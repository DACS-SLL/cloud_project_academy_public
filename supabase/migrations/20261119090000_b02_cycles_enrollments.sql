-- B02 - Ciclos, grupos con cupo, matrícula y cargos.
-- La solicitud queda pendiente y no ocupa cupo. Solo una matrícula activa o
-- excepcional cuenta para el cupo. La activación se hará desde la RPC de pago
-- de B03; este bloque deja el modelo, la unicidad y el control transaccional
-- de capacidad listos para esa operación.

create type public.enrollment_status as enum ('pending', 'active', 'exception', 'cancelled');

create table public.cycles (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  start_date date not null,
  end_date date not null,
  grade text not null check (char_length(trim(grade)) > 0),
  warning_absences integer not null default 10 check (warning_absences > 0),
  review_absences integer not null default 15 check (review_absences > 0),
  late_counts_as_absence boolean not null default true,
  created_at timestamptz not null default now(),
  unique (academy_id, name),
  unique (id, academy_id),
  check (end_date > start_date),
  check (review_absences > warning_absences)
);

alter table public.groups
  add column cycle_id uuid;

-- Compatibilidad con los datos de B01: cada academia existente recibe un ciclo
-- de continuidad y sus grupos se asignan a él. El seed de B02 reemplaza estos
-- valores por ciclos demo explícitos.
insert into public.cycles (
  academy_id, name, start_date, end_date, grade,
  warning_absences, review_absences, late_counts_as_absence
)
select
  a.id,
  'Ciclo migrado B01',
  current_date,
  current_date + interval '3 months',
  'Sin grado',
  10,
  15,
  true
from public.academies a
where not exists (
  select 1 from public.cycles c where c.academy_id = a.id
);

update public.groups g
set cycle_id = c.id
from public.cycles c
where c.academy_id = g.academy_id
  and g.cycle_id is null;

alter table public.groups
  alter column cycle_id set not null;

alter table public.groups
  add constraint groups_cycle_academy_fk
  foreign key (cycle_id, academy_id)
  references public.cycles (id, academy_id)
  on delete restrict;

create index groups_cycle_idx on public.groups (cycle_id);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  student_id uuid not null,
  cycle_id uuid not null,
  group_id uuid not null,
  status public.enrollment_status not null default 'pending',
  agreed_registration_price numeric(12, 2) not null check (agreed_registration_price > 0),
  agreed_monthly_price numeric(12, 2) not null check (agreed_monthly_price > 0),
  exception_reason text,
  exception_due_date date,
  authorized_by uuid references auth.users (id) on delete set null,
  authorized_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (student_id, cycle_id),
  unique (id, academy_id),
  foreign key (student_id, academy_id)
    references public.students (id, academy_id) on delete restrict,
  foreign key (cycle_id, academy_id)
    references public.cycles (id, academy_id) on delete restrict,
  foreign key (group_id, academy_id)
    references public.groups (id, academy_id) on delete restrict,
  check (
    status <> 'exception'
    or (char_length(trim(exception_reason)) > 0 and exception_due_date is not null)
  )
);

create index enrollments_academy_group_status_idx
  on public.enrollments (academy_id, group_id, status);
create index enrollments_cycle_idx on public.enrollments (cycle_id);

-- Compatibilidad con B01: los alumnos ya asignados a un grupo quedan con una
-- matrícula activa y precios heredados de sus cargos (o el precio demo 200).
insert into public.enrollments (
  academy_id, student_id, cycle_id, group_id, status,
  agreed_registration_price, agreed_monthly_price
)
select
  s.academy_id,
  s.id,
  g.cycle_id,
  s.group_id,
  'active',
  coalesce(p.registration_price, p.monthly_price, 200),
  coalesce(p.monthly_price, p.registration_price, 200)
from public.students s
join public.groups g
  on g.id = s.group_id
 and g.academy_id = s.academy_id
left join (
  select
    c.student_id,
    c.academy_id,
    max(c.amount) filter (where c.type = 'registration') as registration_price,
    max(c.amount) filter (where c.type = 'monthly') as monthly_price
  from public.charges c
  group by c.student_id, c.academy_id
) p
  on p.student_id = s.id
 and p.academy_id = s.academy_id
where s.group_id is not null
on conflict (student_id, cycle_id) do nothing;

alter table public.charges
  add column enrollment_id uuid;

update public.charges c
set enrollment_id = e.id
from public.enrollments e
where e.student_id = c.student_id
  and e.academy_id = c.academy_id;

alter table public.charges
  alter column enrollment_id set not null;

alter table public.charges
  add constraint charges_enrollment_academy_fk
  foreign key (enrollment_id, academy_id)
  references public.enrollments (id, academy_id)
  on delete restrict;

alter table public.charges
  add constraint charges_enrollment_type_due_unique
  unique (enrollment_id, type, due_date);

create index charges_enrollment_idx on public.charges (enrollment_id);

-- El cargo nace únicamente desde la RPC de matrícula, que fija el precio
-- acordado del ciclo y no permite modificar importes después.
revoke insert on public.charges from authenticated;
drop policy if exists charges_insert_staff on public.charges;

alter table public.cycles enable row level security;
alter table public.enrollments enable row level security;

create policy cycles_select_member on public.cycles
  for select to authenticated
  using (public.is_member_of(academy_id));

create policy cycles_insert_admin on public.cycles
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy cycles_update_admin on public.cycles
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy cycles_delete_admin on public.cycles
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy enrollments_select_staff on public.enrollments
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

grant select, insert, update, delete on public.cycles to authenticated;
grant select on public.enrollments to authenticated;

-- Valida grupo/ciclo y aplica el cupo cuando la matrícula pasa a ocupar
-- asiento. El bloqueo de la fila del grupo serializa activaciones concurrentes.
create or replace function public.b02_enrollment_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_academy_id uuid;
  v_group_cycle_id uuid;
  v_capacity integer;
  v_occupied integer;
begin
  select g.academy_id, g.cycle_id, g.capacity
    into v_group_academy_id, v_group_cycle_id, v_capacity
  from public.groups g
  where g.id = new.group_id
  for update;

  if v_group_academy_id is null then
    raise exception 'Grupo no encontrado' using errcode = 'P0002';
  end if;

  if v_group_academy_id <> new.academy_id or v_group_cycle_id <> new.cycle_id then
    raise exception 'El grupo no pertenece al ciclo y academia de la matrícula'
      using errcode = '23514';
  end if;

  if new.status in ('active', 'exception') then
    if tg_op = 'INSERT'
       or old.status not in ('active', 'exception')
       or old.group_id is distinct from new.group_id then
      select count(*)::integer
        into v_occupied
      from public.enrollments e
      where e.group_id = new.group_id
        and e.status in ('active', 'exception')
        and e.id is distinct from new.id;

      if v_occupied >= v_capacity then
        raise exception 'Grupo sin cupo' using errcode = '23514';
      end if;

      update public.students s
      set group_id = new.group_id
      where s.id = new.student_id
        and s.academy_id = new.academy_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger b02_on_enrollment_guard
  before insert or update on public.enrollments
  for each row execute function public.b02_enrollment_guard();

-- Consulta de cupos para dirección, secretaría y el docente asignado.
create or replace function public.group_capacity(p_group_id uuid)
returns table (
  group_id uuid,
  capacity integer,
  occupied integer,
  available integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_academy_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada' using errcode = '28000';
  end if;

  select g.academy_id into v_academy_id
  from public.groups g
  where g.id = p_group_id;

  if v_academy_id is null then
    raise exception 'Grupo no encontrado' using errcode = 'P0002';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[])
     and not public.is_teacher_of_group(p_group_id) then
    raise exception 'Sin acceso al grupo' using errcode = '42501';
  end if;

  return query
  select
    g.id,
    g.capacity,
    count(e.id)::integer,
    greatest(g.capacity - count(e.id)::integer, 0)
  from public.groups g
  left join public.enrollments e
    on e.group_id = g.id
   and e.academy_id = g.academy_id
   and e.status in ('active', 'exception')
  where g.id = p_group_id
  group by g.id, g.capacity;
end;
$$;

-- Solicitud de matrícula: crea la matrícula pendiente y sus cargos separados.
-- No ocupa cupo. La activación posterior (B03) cambiará el estado y el trigger
-- de cupo decidirá si el grupo aún tiene asiento.
create or replace function public.create_enrollment_request(
  p_student_id uuid,
  p_group_id uuid,
  p_registration_price numeric,
  p_monthly_price numeric,
  p_registration_due_date date,
  p_monthly_due_dates date[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_academy_id uuid;
  v_cycle_id uuid;
  v_enrollment_id uuid;
  v_due_date date;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada' using errcode = '28000';
  end if;

  select g.academy_id, g.cycle_id
    into v_academy_id, v_cycle_id
  from public.groups g
  where g.id = p_group_id;

  if v_academy_id is null then
    raise exception 'Grupo no encontrado' using errcode = 'P0002';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[]) then
    raise exception 'Solo dirección o secretaría pueden registrar matrículas'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.students s
    where s.id = p_student_id
      and s.academy_id = v_academy_id
  ) then
    raise exception 'Alumno no encontrado en la academia' using errcode = 'P0002';
  end if;

  if p_registration_price is null or p_registration_price <= 0
     or p_monthly_price is null or p_monthly_price <= 0 then
    raise exception 'Los precios deben ser positivos' using errcode = '22023';
  end if;

  if p_registration_due_date is null
     or p_monthly_due_dates is null
     or cardinality(p_monthly_due_dates) = 0 then
    raise exception 'La inscripción y al menos una mensualidad requieren vencimiento'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.enrollments e
    where e.student_id = p_student_id
      and e.cycle_id = v_cycle_id
  ) then
    raise exception 'El alumno ya tiene una matrícula en este ciclo'
      using errcode = '23505';
  end if;

  insert into public.enrollments (
    academy_id, student_id, cycle_id, group_id, status,
    agreed_registration_price, agreed_monthly_price, created_by
  )
  values (
    v_academy_id, p_student_id, v_cycle_id, p_group_id, 'pending',
    p_registration_price, p_monthly_price, (select auth.uid())
  )
  returning id into v_enrollment_id;

  insert into public.charges (
    academy_id, student_id, enrollment_id, type, amount, due_date
  )
  values (
    v_academy_id, p_student_id, v_enrollment_id, 'registration',
    p_registration_price, p_registration_due_date
  );

  foreach v_due_date in array p_monthly_due_dates loop
    insert into public.charges (
      academy_id, student_id, enrollment_id, type, amount, due_date
    )
    values (
      v_academy_id, p_student_id, v_enrollment_id, 'monthly',
      p_monthly_price, v_due_date
    );
  end loop;

  return v_enrollment_id;
end;
$$;

revoke all on function public.group_capacity(uuid) from public, anon, authenticated;
revoke all on function public.create_enrollment_request(uuid, uuid, numeric, numeric, date, date[])
  from public, anon, authenticated;

grant execute on function public.group_capacity(uuid) to authenticated;
grant execute on function public.create_enrollment_request(uuid, uuid, numeric, numeric, date, date[])
  to authenticated;
