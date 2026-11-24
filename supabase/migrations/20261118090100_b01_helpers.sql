-- B01 - Funciones de autorización.
-- Son SECURITY DEFINER para consultar membresías sin recursión de RLS.
-- Todas fijan search_path y exponen solo un booleano o las filas del propio usuario.

create or replace function public.current_academy_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.academy_id
  from public.memberships m
  where m.user_id = (select auth.uid());
$$;

create or replace function public.is_member_of(p_academy_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = (select auth.uid())
      and m.academy_id = p_academy_id
  );
$$;

create or replace function public.has_academy_role(
  p_academy_id uuid,
  p_roles public.membership_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = (select auth.uid())
      and m.academy_id = p_academy_id
      and m.role = any (p_roles)
  );
$$;

create or replace function public.is_teacher_of_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teacher_assignments ta
    join public.memberships m
      on m.academy_id = ta.academy_id
     and m.user_id = (select auth.uid())
     and m.role = 'teacher'::public.membership_role
    where ta.group_id = p_group_id
      and ta.teacher_id = (select auth.uid())
  );
$$;

create or replace function public.is_teacher_of_subject(p_subject_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teacher_assignments ta
    join public.memberships m
      on m.academy_id = ta.academy_id
     and m.user_id = (select auth.uid())
     and m.role = 'teacher'::public.membership_role
    where ta.subject_id = p_subject_id
      and ta.teacher_id = (select auth.uid())
  );
$$;

create or replace function public.is_teacher_of_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.class_sessions cs
    join public.memberships m
      on m.academy_id = cs.academy_id
     and m.user_id = (select auth.uid())
     and m.role = 'teacher'::public.membership_role
    where cs.id = p_session_id
      and cs.teacher_id = (select auth.uid())
  );
$$;

-- El primer segmento del objeto es el academy_id. Solo dirección y secretaría
-- de esa academia pueden leer o subir vouchers; docentes quedan fuera.
create or replace function public.can_access_voucher(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = (select auth.uid())
      and m.role in (
        'admin'::public.membership_role,
        'cashier'::public.membership_role
      )
      and m.academy_id::text = (storage.foldername(p_object_name))[1]
  );
$$;

-- Firma de lectura para el frontend: qué academias y roles tiene la sesión.
create or replace function public.my_access()
returns table (academy_id uuid, academy_name text, role public.membership_role)
language sql
stable
security definer
set search_path = ''
as $$
  select m.academy_id, a.name, m.role
  from public.memberships m
  join public.academies a on a.id = m.academy_id
  where m.user_id = (select auth.uid())
  order by a.name;
$$;
