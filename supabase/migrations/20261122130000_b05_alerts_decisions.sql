-- B05 - Alertas de deuda/faltas, seguimiento y decisión académica.
-- Requiere B01/B02, B03, B04 y B06. No modifica migraciones anteriores.
-- Los casos se calculan desde datos persistidos; no hay tabla de casos ni
-- tareas programadas.

create table public.followups (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  student_id uuid not null,
  cycle_id uuid not null,
  channel text not null check (channel in ('call', 'whatsapp', 'email', 'in_person')),
  note text not null check (char_length(btrim(note)) > 0),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (student_id, academy_id)
    references public.students (id, academy_id) on delete restrict,
  foreign key (cycle_id, academy_id)
    references public.cycles (id, academy_id) on delete restrict
);

create index followups_student_cycle_idx
  on public.followups (academy_id, student_id, cycle_id, created_at desc);

create table public.academic_decisions (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies (id) on delete cascade,
  student_id uuid not null,
  cycle_id uuid not null,
  decision text not null check (decision in ('continue', 'close_case', 'other')),
  reason text not null check (char_length(btrim(reason)) > 0),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (student_id, academy_id)
    references public.students (id, academy_id) on delete restrict,
  foreign key (cycle_id, academy_id)
    references public.cycles (id, academy_id) on delete restrict
);

create index academic_decisions_student_cycle_idx
  on public.academic_decisions (academy_id, student_id, cycle_id, created_at desc);

alter table public.followups enable row level security;
alter table public.academic_decisions enable row level security;

create policy followups_select_staff on public.followups
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

create policy academic_decisions_select_staff on public.academic_decisions
  for select to authenticated
  using (public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[]));

revoke all on table public.followups from public, anon, authenticated;
revoke all on table public.academic_decisions from public, anon, authenticated;
grant select on table public.followups to authenticated;
grant select on table public.academic_decisions to authenticated;

-- Casos del ciclo calculados desde cargos/pagos y asistencias.
-- La deuda se agrega por matrícula. Una matrícula exception usa su fecha
-- aprobada para el cargo de inscripción; el resto usa el vencimiento del cargo.
create or replace function public.cycle_cases(p_cycle_id uuid)
returns table (
  case_type text,
  student_id uuid,
  full_name text,
  enrollment_id uuid,
  balance numeric,
  due_date date,
  overdue boolean,
  absences integer,
  warning_threshold integer,
  review_threshold integer,
  requires_decision boolean,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_warning_absences integer;
  v_review_absences integer;
  v_late_counts_as_absence boolean;
  v_cycle_end date;
  v_today date := (now() at time zone 'America/Lima')::date;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select c.academy_id, c.warning_absences, c.review_absences,
         c.late_counts_as_absence, c.end_date
    into v_academy_id, v_warning_absences, v_review_absences,
         v_late_counts_as_absence, v_cycle_end
  from public.cycles c
  where c.id = p_cycle_id;

  if v_academy_id is null then
    raise exception 'Ciclo no encontrado'
      using errcode = '22023', hint = 'CYCLE_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[]) then
    raise exception 'Sin acceso a los casos del ciclo'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  return query
  with charge_balances as (
    select
      c.id,
      c.enrollment_id,
      c.amount,
      c.type,
      case
        when e.status = 'exception'::public.enrollment_status
         and c.type = 'registration'
        then e.exception_due_date
        else c.due_date
      end as effective_due_date,
      c.amount - coalesce(
        sum(p.amount) filter (where p.status = 'confirmed'),
        0
      ) as balance
    from public.charges c
    join public.enrollments e
      on e.id = c.enrollment_id
     and e.academy_id = c.academy_id
    left join public.payments p
      on p.charge_id = c.id
     and p.academy_id = c.academy_id
    where e.academy_id = v_academy_id
      and e.cycle_id = p_cycle_id
      and e.status in (
        'pending'::public.enrollment_status,
        'active'::public.enrollment_status,
        'exception'::public.enrollment_status
      )
    group by c.id, c.amount, c.type, e.status, e.exception_due_date, c.due_date
  ),
  debt_cases as (
    select
      e.id as enrollment_id,
      e.student_id,
      s.full_name,
      sum(cb.balance)::numeric(12, 2) as balance,
      min(cb.effective_due_date) filter (where cb.balance > 0) as due_date,
      coalesce(
        bool_or(cb.balance > 0 and cb.effective_due_date < v_today),
        false
      ) as overdue
    from public.enrollments e
    join public.students s
      on s.id = e.student_id
     and s.academy_id = e.academy_id
    join charge_balances cb
      on cb.enrollment_id = e.id
    where e.academy_id = v_academy_id
      and e.cycle_id = p_cycle_id
      and e.status in (
        'pending'::public.enrollment_status,
        'active'::public.enrollment_status,
        'exception'::public.enrollment_status
      )
    group by e.id, e.student_id, s.full_name
    having sum(cb.balance) > 0
  ),
  decisions as (
    select d.student_id
    from public.academic_decisions d
    where d.academy_id = v_academy_id
      and d.cycle_id = p_cycle_id
    group by d.student_id
  ),
  attendance_counts as (
    select
      e.id as enrollment_id,
      e.student_id,
      s.full_name,
      count(a.id)::integer as absences
    from public.enrollments e
    join public.students s
      on s.id = e.student_id
     and s.academy_id = e.academy_id
    join public.attendance a
      on a.student_id = e.student_id
     and a.academy_id = e.academy_id
    join public.class_sessions cs
      on cs.id = a.session_id
     and cs.academy_id = a.academy_id
    join public.groups g
      on g.id = cs.group_id
     and g.academy_id = cs.academy_id
    where e.academy_id = v_academy_id
      and e.cycle_id = p_cycle_id
      and e.status in (
        'active'::public.enrollment_status,
        'exception'::public.enrollment_status
      )
      and g.cycle_id = p_cycle_id
      and (
        a.status = 'absent'::public.attendance_status
        or (
          v_late_counts_as_absence
          and a.status = 'late'::public.attendance_status
        )
      )
    group by e.id, e.student_id, s.full_name
    having count(a.id) >= v_warning_absences
  ),
  attendance_cases as (
    select
      ac.enrollment_id,
      ac.student_id,
      ac.full_name,
      ac.absences,
      (d.student_id is not null) as has_decision
    from attendance_counts ac
    left join decisions d
      on d.student_id = ac.student_id
  ),
  all_cases as (
    select
      'debt'::text as case_type,
      dc.student_id,
      dc.full_name,
      dc.enrollment_id,
      dc.balance,
      dc.due_date,
      dc.overdue,
      null::integer as absences,
      v_warning_absences as warning_threshold,
      v_review_absences as review_threshold,
      false as requires_decision,
      'open'::text as status
    from debt_cases dc
    union all
    select
      'attendance'::text as case_type,
      ac.student_id,
      ac.full_name,
      ac.enrollment_id,
      null::numeric as balance,
      null::date as due_date,
      null::boolean as overdue,
      ac.absences,
      v_warning_absences as warning_threshold,
      v_review_absences as review_threshold,
      (not ac.has_decision and ac.absences >= v_review_absences) as requires_decision,
      case
        when ac.has_decision then 'resolved'
        when ac.absences >= v_review_absences then 'needs_decision'
        when v_cycle_end < v_today then 'resolved'
        else 'open'
      end as status
    from attendance_cases ac
  )
  select
    ac.case_type,
    ac.student_id,
    ac.full_name,
    ac.enrollment_id,
    ac.balance,
    ac.due_date,
    ac.overdue,
    ac.absences,
    ac.warning_threshold,
    ac.review_threshold,
    ac.requires_decision,
    ac.status
  from all_cases ac
  order by ac.case_type, ac.full_name, ac.student_id;
end;
$$;

-- Registra un contacto sin cerrar ni alterar el caso. Solo aplica a casos
-- abiertos; el historial de casos resueltos queda en modo consulta.
create or replace function public.register_followup(
  p_student_id uuid,
  p_cycle_id uuid,
  p_channel text,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_channel text := btrim(coalesce(p_channel, ''));
  v_note text := btrim(coalesce(p_note, ''));
  v_total_cases integer;
  v_open_cases integer;
  v_followup_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select c.academy_id
    into v_academy_id
  from public.cycles c
  where c.id = p_cycle_id;

  if v_academy_id is null then
    raise exception 'Ciclo no encontrado'
      using errcode = '22023', hint = 'CYCLE_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin,cashier}'::public.membership_role[]) then
    raise exception 'Sin acceso al seguimiento del ciclo'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if v_channel not in ('call', 'whatsapp', 'email', 'in_person') then
    raise exception 'El canal de contacto no es válido'
      using errcode = '22023', hint = 'INVALID_FOLLOWUP';
  end if;

  if v_note = '' then
    raise exception 'La nota de seguimiento es obligatoria'
      using errcode = '22023', hint = 'INVALID_FOLLOWUP';
  end if;

  select
    count(*)::integer,
    (count(*) filter (where cc.status <> 'resolved'))::integer
    into v_total_cases, v_open_cases
  from public.cycle_cases(p_cycle_id) cc
  where cc.student_id = p_student_id;

  if v_total_cases = 0 then
    raise exception 'El alumno no tiene un caso en el ciclo'
      using errcode = '22023', hint = 'CASE_NOT_FOUND';
  end if;

  if v_open_cases = 0 then
    raise exception 'El caso ya está resuelto'
      using errcode = '23514', hint = 'CASE_NOT_CLOSABLE';
  end if;

  insert into public.followups (
    academy_id, student_id, cycle_id, channel, note, created_by
  ) values (
    v_academy_id, p_student_id, p_cycle_id, v_channel, v_note, v_user_id
  )
  returning id into v_followup_id;

  return v_followup_id;
end;
$$;

-- Decisión de dirección únicamente cuando el caso de faltas alcanzó el límite.
-- Se permiten varias decisiones para conservar correcciones/revisiones; la
-- existencia de al menos una decisión mantiene el caso resuelto.
create or replace function public.register_academic_decision(
  p_student_id uuid,
  p_cycle_id uuid,
  p_decision text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_academy_id uuid;
  v_decision text := btrim(coalesce(p_decision, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_absences integer;
  v_review_absences integer;
  v_decision_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select c.academy_id
    into v_academy_id
  from public.cycles c
  where c.id = p_cycle_id;

  if v_academy_id is null then
    raise exception 'Ciclo no encontrado'
      using errcode = '22023', hint = 'CYCLE_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_academy_id, '{admin}'::public.membership_role[]) then
    raise exception 'Solo dirección puede registrar decisiones académicas'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  if v_decision not in ('continue', 'close_case', 'other')
     or v_reason = '' then
    raise exception 'La decisión y su motivo son obligatorios'
      using errcode = '22023', hint = 'INVALID_DECISION';
  end if;

  select cc.absences, cc.review_threshold
    into v_absences, v_review_absences
  from public.cycle_cases(p_cycle_id) cc
  where cc.student_id = p_student_id
    and cc.case_type = 'attendance';

  if not found then
    raise exception 'El alumno no tiene un caso de faltas en el ciclo'
      using errcode = '22023', hint = 'CASE_NOT_FOUND';
  end if;

  if v_absences < v_review_absences then
    raise exception 'El caso todavía no alcanzó el límite de revisión'
      using errcode = '23514', hint = 'CASE_NOT_CLOSABLE';
  end if;

  insert into public.academic_decisions (
    academy_id, student_id, cycle_id, decision, reason, created_by
  ) values (
    v_academy_id, p_student_id, p_cycle_id, v_decision, v_reason, v_user_id
  )
  returning id into v_decision_id;

  return v_decision_id;
end;
$$;

revoke all on function public.cycle_cases(uuid) from public, anon, authenticated;
revoke all on function public.register_followup(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.register_academic_decision(uuid, uuid, text, text) from public, anon, authenticated;

grant execute on function public.cycle_cases(uuid) to authenticated;
grant execute on function public.register_followup(uuid, uuid, text, text) to authenticated;
grant execute on function public.register_academic_decision(uuid, uuid, text, text) to authenticated;
