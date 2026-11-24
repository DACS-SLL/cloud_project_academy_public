-- B05 - Corrección del cálculo de deuda vencida.
-- `balance` queda como el importe vencido con saldo pendiente (lo que F03
-- muestra como deuda vencida). `total_balance` conserva el saldo total de la
-- matrícula, sumando vencido y futuro en un campo separado.
-- Requiere la migración B05 20261122130000.

drop function if exists public.cycle_cases(uuid);

create function public.cycle_cases(p_cycle_id uuid)
returns table (
  case_type text,
  student_id uuid,
  full_name text,
  enrollment_id uuid,
  balance numeric,
  total_balance numeric,
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
      coalesce(
        sum(cb.balance) filter (
          where cb.balance > 0 and cb.effective_due_date < v_today
        ),
        0
      )::numeric(12, 2) as balance,
      coalesce(
        sum(cb.balance) filter (where cb.balance > 0),
        0
      )::numeric(12, 2) as total_balance,
      min(cb.effective_due_date) filter (
        where cb.balance > 0 and cb.effective_due_date < v_today
      ) as due_date,
      true as overdue
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
    having sum(cb.balance) filter (
      where cb.balance > 0 and cb.effective_due_date < v_today
    ) > 0
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
      dc.total_balance,
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
      null::numeric as total_balance,
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
    ac.total_balance,
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

revoke all on function public.cycle_cases(uuid) from public, anon, authenticated;
grant execute on function public.cycle_cases(uuid) to authenticated;
