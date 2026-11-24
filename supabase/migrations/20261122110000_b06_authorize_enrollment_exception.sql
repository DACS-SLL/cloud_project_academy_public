-- B06 - Autorización administrativa de excepciones de matrícula.
-- Conserva los cargos/pagos y delega el control de cupo al guard B02.

create or replace function public.authorize_enrollment_exception(
  p_enrollment_id uuid,
  p_reason text,
  p_due_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_enrollment_id uuid;
  v_academy_id uuid;
  v_status public.enrollment_status;
  v_trigger_message text;
begin
  if v_user_id is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.user_id = v_user_id
      and m.role = 'admin'::public.membership_role
  ) then
    raise exception 'Solo dirección puede autorizar excepciones'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  -- Scope the lookup to an academy where this caller is admin. This gives
  -- inaccessible and nonexistent enrollment ids the same response.
  select e.id, e.academy_id, e.status
    into v_enrollment_id, v_academy_id, v_status
  from public.enrollments e
  where e.id = p_enrollment_id
    and exists (
      select 1
      from public.memberships m
      where m.user_id = v_user_id
        and m.academy_id = e.academy_id
        and m.role = 'admin'::public.membership_role
    )
  for update of e;

  if not found then
    raise exception 'Matrícula no encontrada'
      using errcode = 'P0002', hint = 'ENROLLMENT_NOT_FOUND';
  end if;

  if v_status <> 'pending'::public.enrollment_status then
    raise exception 'Solo una matrícula pendiente puede recibir una excepción'
      using errcode = '23514', hint = 'EXCEPTION_STATUS_INVALID';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'El motivo de excepción es obligatorio'
      using errcode = '22023', hint = 'EXCEPTION_REASON_REQUIRED';
  end if;

  if p_due_date is null then
    raise exception 'La fecha límite de excepción es obligatoria'
      using errcode = '22023', hint = 'EXCEPTION_DUE_DATE_REQUIRED';
  end if;

  begin
    update public.enrollments
    set status = 'exception',
        exception_reason = trim(p_reason),
        exception_due_date = p_due_date,
        authorized_by = v_user_id,
        authorized_at = now()
    where id = v_enrollment_id
      and academy_id = v_academy_id;
  exception when check_violation then
    get stacked diagnostics v_trigger_message = message_text;
    if v_trigger_message = 'Grupo sin cupo' then
      raise exception 'El grupo no tiene vacante'
        using errcode = '23514', hint = 'GROUP_FULL';
    elsif v_trigger_message = 'El grupo no pertenece al ciclo y academia de la matrícula' then
      raise exception 'El grupo de la matrícula no coincide con su ciclo y academia'
        using errcode = '23514', hint = 'ENROLLMENT_CYCLE_MISMATCH';
    else
      raise;
    end if;
  end;

  return v_enrollment_id;
end;
$$;

revoke all on function public.authorize_enrollment_exception(uuid, text, date)
  from public, anon, authenticated;
grant execute on function public.authorize_enrollment_exception(uuid, text, date)
  to authenticated;
