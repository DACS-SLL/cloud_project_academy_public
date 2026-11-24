-- B01 - Row Level Security por academia y rol.
-- Denegación por defecto: si no existe una política que permita la operación,
-- PostgREST no devuelve ni modifica filas para anon/authenticated.

alter table public.academies enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.groups enable row level security;
alter table public.subjects enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.students enable row level security;
alter table public.guardians enable row level security;
alter table public.charges enable row level security;
alter table public.payments enable row level security;
alter table public.class_sessions enable row level security;
alter table public.attendance enable row level security;

-- Academias: cualquier miembro lee la suya; solo dirección la actualiza.
create policy academies_select_member on public.academies
  for select to authenticated
  using (public.is_member_of(id));

create policy academies_update_admin on public.academies
  for update to authenticated
  using (public.has_academy_role(id, '{admin}'::public.membership_role[]))
  with check (public.has_academy_role(id, '{admin}'::public.membership_role[]));

-- Perfiles: se lee el propio y el de miembros de la misma academia.
create policy profiles_select_self_or_shared on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.memberships m
      where m.user_id = profiles.id
        and m.academy_id in (select public.current_academy_ids())
    )
  );

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Membresías: cada usuario ve las suyas; dirección ve las de su academia.
-- No hay políticas de escritura: las cuentas y roles se asignan con service role.
create policy memberships_select_self_or_admin on public.memberships
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.has_academy_role(academy_id, '{admin}'::public.membership_role[])
  );

-- Grupos y cursos: lectura para miembros; escritura solo dirección.
create policy groups_select_staff_or_assigned_teacher on public.groups
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
    or public.is_teacher_of_group(id)
  );

create policy groups_insert_admin on public.groups
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy groups_update_admin on public.groups
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy groups_delete_admin on public.groups
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy subjects_select_staff_or_assigned_teacher on public.subjects
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
    or public.is_teacher_of_subject(id)
  );

create policy subjects_insert_admin on public.subjects
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy subjects_update_admin on public.subjects
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy subjects_delete_admin on public.subjects
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

-- Asignaciones: dirección las gestiona; el docente solo ve las suyas.
create policy teacher_assignments_select_admin_or_own on public.teacher_assignments
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin}'::public.membership_role[])
    or (
      teacher_id = (select auth.uid())
      and public.has_academy_role(academy_id, '{teacher}'::public.membership_role[])
    )
  );

create policy teacher_assignments_insert_admin on public.teacher_assignments
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy teacher_assignments_update_admin on public.teacher_assignments
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

create policy teacher_assignments_delete_admin on public.teacher_assignments
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin}'::public.membership_role[]));

-- Alumnos: dirección y secretaría ven toda la academia; el docente solo los
-- alumnos de los grupos que tiene asignados.
create policy students_select_staff_or_assigned_teacher on public.students
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
    or (
      public.has_academy_role(academy_id, '{teacher}'::public.membership_role[])
      and exists (
        select 1
        from public.teacher_assignments ta
        where ta.academy_id = students.academy_id
          and ta.group_id = students.group_id
          and ta.teacher_id = (select auth.uid())
      )
    )
  );

create policy students_insert_staff on public.students
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy students_update_staff on public.students
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy students_delete_staff on public.students
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

-- Apoderados: datos privados; solo dirección y secretaría.
create policy guardians_select_staff on public.guardians
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy guardians_insert_staff on public.guardians
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy guardians_update_staff on public.guardians
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy guardians_delete_staff on public.guardians
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

-- Cargos: finanzas privadas; el docente no tiene ninguna política.
create policy charges_select_staff on public.charges
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy charges_insert_staff on public.charges
  for insert to authenticated
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy charges_update_staff on public.charges
  for update to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]))
  with check (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy charges_delete_staff on public.charges
  for delete to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

-- Pagos: solo lectura para dirección y secretaría. La creación, anulación y
-- cálculo de saldo irán por RPC transaccional en B03; no hay INSERT directo.
create policy payments_select_staff on public.payments
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

-- Sesiones: dirección y secretaría ven todas; el docente solo las suyas.
create policy class_sessions_select_staff_or_own on public.class_sessions
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
    or public.is_teacher_of_session(id)
  );

-- Asistencia: lectura para staff y para el docente de la sesión. La escritura
-- irá por RPC en B04; aquí no se permite INSERT/UPDATE/DELETE directo.
create policy attendance_select_staff_or_session_teacher on public.attendance
  for select to authenticated
  using (
    public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
    or public.is_teacher_of_session(session_id)
  );
