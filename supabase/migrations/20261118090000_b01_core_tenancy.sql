-- B01 - Núcleo de tenancy, roles y datos mínimos de seguridad.
-- Este esquema es la base de B02-B04. Las columnas de negocio se ampliarán
-- en sus migraciones; aquí solo se fija lo necesario para Auth, aislamiento
-- por academia, denegación de finanzas a docentes y vouchers privados.

create type public.membership_role as enum ('admin', 'cashier', 'teacher');
create type public.attendance_status as enum ('present', 'absent', 'late');

create table public.academies (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  created_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.membership_role not null,
  created_at timestamptz not null default now(),
  unique (academy_id, user_id)
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  shift text not null default 'morning' check (shift in ('morning', 'afternoon', 'night')),
  capacity integer not null default 30 check (capacity > 0),
  created_at timestamptz not null default now(),
  unique (academy_id, name),
  unique (id, academy_id)
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  created_at timestamptz not null default now(),
  unique (academy_id, name),
  unique (id, academy_id)
);

create table public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  group_id uuid not null,
  subject_id uuid not null,
  created_at timestamptz not null default now(),
  unique (teacher_id, group_id, subject_id),
  foreign key (group_id, academy_id) references public.groups (id, academy_id) on delete cascade,
  foreign key (subject_id, academy_id) references public.subjects (id, academy_id) on delete cascade
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  group_id uuid,
  full_name text not null check (char_length(trim(full_name)) > 0),
  document_id text,
  school text,
  grade text,
  created_at timestamptz not null default now(),
  unique (id, academy_id),
  foreign key (group_id, academy_id) references public.groups (id, academy_id) on delete set null (group_id)
);

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  student_id uuid not null,
  full_name text not null check (char_length(trim(full_name)) > 0),
  document_id text,
  phone text,
  created_at timestamptz not null default now(),
  foreign key (student_id, academy_id) references public.students (id, academy_id) on delete cascade
);

create table public.charges (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  student_id uuid not null,
  type text not null check (type in ('registration', 'monthly')),
  amount numeric(12, 2) not null check (amount > 0),
  due_date date not null,
  created_at timestamptz not null default now(),
  unique (id, academy_id),
  foreign key (student_id, academy_id) references public.students (id, academy_id) on delete cascade
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  charge_id uuid not null,
  amount numeric(12, 2) not null check (amount > 0),
  method text not null default 'bank_transfer' check (method in ('bank_transfer', 'bank_deposit')),
  reference text not null check (char_length(trim(reference)) > 0),
  voucher_path text not null check (char_length(trim(voucher_path)) > 0),
  status text not null default 'confirmed' check (status in ('confirmed', 'voided')),
  void_reason text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, academy_id),
  foreign key (charge_id, academy_id) references public.charges (id, academy_id) on delete restrict
);

create table public.class_sessions (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  group_id uuid not null,
  subject_id uuid not null,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  starts_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (id, academy_id),
  foreign key (group_id, academy_id) references public.groups (id, academy_id) on delete cascade,
  foreign key (subject_id, academy_id) references public.subjects (id, academy_id) on delete cascade
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  session_id uuid not null,
  student_id uuid not null,
  status public.attendance_status not null,
  created_at timestamptz not null default now(),
  unique (session_id, student_id),
  foreign key (session_id, academy_id) references public.class_sessions (id, academy_id) on delete cascade,
  foreign key (student_id, academy_id) references public.students (id, academy_id) on delete cascade
);

create index memberships_user_academy_idx on public.memberships (user_id, academy_id);
create index groups_academy_idx on public.groups (academy_id);
create index subjects_academy_idx on public.subjects (academy_id);
create index teacher_assignments_teacher_idx on public.teacher_assignments (teacher_id);
create index teacher_assignments_group_idx on public.teacher_assignments (group_id);
create index students_academy_group_idx on public.students (academy_id, group_id);
create index guardians_academy_student_idx on public.guardians (academy_id, student_id);
create index charges_academy_student_idx on public.charges (academy_id, student_id);
create index payments_academy_charge_idx on public.payments (academy_id, charge_id);
create index class_sessions_academy_teacher_idx on public.class_sessions (academy_id, teacher_id);
create index attendance_session_idx on public.attendance (session_id);

-- Perfil mínimo creado por un proceso privilegiado al dar de alta una cuenta.
create or replace function public.b01_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email, ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger b01_on_auth_user_created
  after insert on auth.users
  for each row execute function public.b01_handle_new_user();
