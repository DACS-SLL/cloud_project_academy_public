-- B03 - Pagos bancarios, saldo, activación y anulación auditada.
-- Requiere B01/B02. No modifica las migraciones anteriores.

alter table public.payments
  add column paid_at date,
  add column voided_at timestamptz,
  add column voided_by uuid references auth.users (id) on delete set null;

update public.payments
set paid_at = created_at::date
where paid_at is null;

alter table public.payments
  alter column paid_at set not null,
  alter column paid_at set default current_date;

create unique index payments_academy_reference_uidx
  on public.payments (academy_id, reference);
create index payments_charge_status_idx
  on public.payments (charge_id, status);

-- Pago bancario con voucher obligatorio e idempotencia por p_payment_id.
create or replace function public.register_payment(
  p_payment_id uuid,
  p_enrollment_id uuid,
  p_charge_id uuid,
  p_amount numeric,
  p_paid_at date,
  p_method text,
  p_reference text,
  p_voucher_path text
)
returns table (
  payment_id uuid,
  status text,
  amount numeric,
  charge_balance numeric,
  enrollment_status public.enrollment_status,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
  v_charge_amount numeric;
  v_charge_enrollment_id uuid;
  v_charge_type text;
  v_charge_academy_id uuid;
  v_enrollment_status public.enrollment_status;
  v_paid numeric;
  v_balance numeric;
  v_reference text;
  v_voucher_path text;
  v_existing_id uuid;
  v_hint text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select p.*
    into v_payment
  from public.payments p
  where p.id = p_payment_id
  for update;

  select c.amount, c.enrollment_id, c.type, c.academy_id
    into v_charge_amount, v_charge_enrollment_id, v_charge_type, v_charge_academy_id
  from public.charges c
  where c.id = p_charge_id
  for update;

  if v_charge_academy_id is null then
    raise exception 'Cargo no encontrado'
      using errcode = '22023', hint = 'PAYMENT_CHARGE_NOT_FOUND';
  end if;

  if v_charge_enrollment_id <> p_enrollment_id then
    raise exception 'El cargo no pertenece a la matrícula'
      using errcode = '23514', hint = 'PAYMENT_CHARGE_MISMATCH';
  end if;

  if not public.has_academy_role(v_charge_academy_id, '{admin,cashier}'::public.membership_role[]) then
    raise exception 'Sin permiso para registrar pagos'
      using errcode = '42501', hint = 'ACCESS_DENIED';
  end if;

  select e.status
    into v_enrollment_status
  from public.enrollments e
  where e.id = p_enrollment_id
    and e.academy_id = v_charge_academy_id
  for update;

  if v_enrollment_status is null then
    raise exception 'Matrícula no encontrada'
      using errcode = '22023', hint = 'PAYMENT_ENROLLMENT_NOT_FOUND';
  end if;

  v_reference := btrim(coalesce(p_reference, ''));
  v_voucher_path := btrim(coalesce(p_voucher_path, ''));

  if v_payment.id is not null then
    if v_payment.status = 'confirmed'
       and v_payment.charge_id = p_charge_id
       and v_payment.amount = p_amount
       and v_payment.paid_at = p_paid_at
       and v_payment.method = p_method
       and v_payment.reference = v_reference
       and v_payment.voucher_path = v_voucher_path then
      select coalesce(sum(p.amount), 0)
        into v_paid
      from public.payments p
      where p.charge_id = p_charge_id
        and p.status = 'confirmed';

      v_balance := v_charge_amount - v_paid;

      return query
      select
        v_payment.id,
        v_payment.status::text,
        v_payment.amount,
        v_balance,
        v_enrollment_status,
        true;
      return;
    end if;

    raise exception 'El identificador de pago ya existe con otros datos'
      using errcode = '23505', hint = 'PAYMENT_IDEMPOTENCY_CONFLICT';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'El monto debe ser positivo'
      using errcode = '22023', hint = 'PAYMENT_INVALID_AMOUNT';
  end if;

  if p_paid_at is null then
    raise exception 'La fecha de pago es obligatoria'
      using errcode = '22023', hint = 'PAYMENT_INVALID_DATE';
  end if;

  if p_method is null or p_method not in ('bank_transfer', 'bank_deposit') then
    raise exception 'Solo se aceptan transferencia o depósito bancario'
      using errcode = '22023', hint = 'PAYMENT_METHOD_INVALID';
  end if;

  if v_reference = '' then
    raise exception 'La referencia bancaria es obligatoria'
      using errcode = '22023', hint = 'PAYMENT_REFERENCE_REQUIRED';
  end if;

  if v_voucher_path = '' then
    raise exception 'El voucher es obligatorio'
      using errcode = '22023', hint = 'PAYMENT_VOUCHER_REQUIRED';
  end if;

  if split_part(v_voucher_path, '/', 1) <> v_charge_academy_id::text
     or split_part(v_voucher_path, '/', 2) <> p_payment_id::text then
    raise exception 'La ruta del voucher no corresponde a la academia y al pago'
      using errcode = '22023', hint = 'PAYMENT_VOUCHER_PATH_INVALID';
  end if;

  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'vouchers'
      and o.name = v_voucher_path
  ) then
    raise exception 'El objeto del voucher no existe'
      using errcode = '22023', hint = 'PAYMENT_VOUCHER_OBJECT_NOT_FOUND';
  end if;

  select p.id
    into v_existing_id
  from public.payments p
  where p.academy_id = v_charge_academy_id
    and p.reference = v_reference
    and p.id <> p_payment_id;

  if v_existing_id is not null then
    raise exception 'La referencia bancaria ya fue registrada'
      using errcode = '23505', hint = 'PAYMENT_DUPLICATE_REFERENCE';
  end if;

  select coalesce(sum(p.amount), 0)
    into v_paid
  from public.payments p
  where p.charge_id = p_charge_id
    and p.status = 'confirmed';

  v_balance := v_charge_amount - v_paid;

  if p_amount > v_balance then
    raise exception 'El pago excede el saldo del cargo'
      using errcode = '23514', hint = 'PAYMENT_OVERPAY';
  end if;

  begin
    insert into public.payments (
      id, academy_id, charge_id, amount, paid_at, method, reference,
      voucher_path, status, created_by
    )
    values (
      p_payment_id, v_charge_academy_id, p_charge_id, p_amount, p_paid_at,
      p_method, v_reference, v_voucher_path, 'confirmed', (select auth.uid())
    );
  exception
    when unique_violation then
      select p.*
        into v_payment
      from public.payments p
      where p.id = p_payment_id;

      if v_payment.id is not null
         and v_payment.status = 'confirmed'
         and v_payment.charge_id = p_charge_id
         and v_payment.amount = p_amount
         and v_payment.paid_at = p_paid_at
         and v_payment.method = p_method
         and v_payment.reference = v_reference
         and v_payment.voucher_path = v_voucher_path then
        select coalesce(sum(p.amount), 0)
          into v_paid
        from public.payments p
        where p.charge_id = p_charge_id
          and p.status = 'confirmed';

        v_balance := v_charge_amount - v_paid;

        return query
        select
          v_payment.id,
          v_payment.status::text,
          v_payment.amount,
          v_balance,
          v_enrollment_status,
          true;
        return;
      end if;

      raise exception 'La referencia o el pago ya existen'
        using errcode = '23505', hint = 'PAYMENT_DUPLICATE_REFERENCE';
  end;

  if v_charge_type = 'registration'
     and (v_balance - p_amount) = 0
     and v_enrollment_status in ('pending', 'exception') then
    begin
      update public.enrollments e
      set status = 'active'
      where e.id = p_enrollment_id
      returning e.status into v_enrollment_status;
    exception
      when check_violation then
        get stacked diagnostics v_hint = pg_exception_hint;
        if v_hint = 'GROUP_FULL' then
          raise exception 'No hay cupo para activar la matrícula'
            using errcode = '23514', hint = 'PAYMENT_GROUP_FULL';
        end if;
        raise;
    end;
  end if;

  return query
  select
    p_payment_id,
    'confirmed'::text,
    p_amount,
    v_balance - p_amount,
    v_enrollment_status,
    false;
end;
$$;

-- Anulación auditada: solo dirección. Si la inscripción vuelve a tener saldo,
-- la matrícula activa vuelve a pending y libera cupo, salvo que conserve la
-- autorización excepcional.
create or replace function public.void_payment(
  p_payment_id uuid,
  p_reason text
)
returns table (
  payment_id uuid,
  status text,
  charge_balance numeric,
  enrollment_status public.enrollment_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
  v_charge_amount numeric;
  v_charge_type text;
  v_charge_enrollment_id uuid;
  v_enrollment_status public.enrollment_status;
  v_exception_reason text;
  v_paid numeric;
  v_balance numeric;
  v_reason text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sesión no autenticada'
      using errcode = '28000', hint = 'SESSION_REQUIRED';
  end if;

  select p.*
    into v_payment
  from public.payments p
  where p.id = p_payment_id
  for update;

  if v_payment.id is null then
    raise exception 'Pago no encontrado'
      using errcode = '22023', hint = 'PAYMENT_NOT_FOUND';
  end if;

  if not public.has_academy_role(v_payment.academy_id, '{admin}'::public.membership_role[]) then
    raise exception 'Solo dirección puede anular pagos'
      using errcode = '42501', hint = 'PAYMENT_VOID_FORBIDDEN';
  end if;

  if v_payment.status = 'voided' then
    raise exception 'El pago ya está anulado'
      using errcode = '23514', hint = 'PAYMENT_ALREADY_VOIDED';
  end if;

  v_reason := btrim(coalesce(p_reason, ''));

  if v_reason = '' then
    raise exception 'El motivo de anulación es obligatorio'
      using errcode = '22023', hint = 'PAYMENT_VOID_REASON_REQUIRED';
  end if;

  select c.amount, c.type, c.enrollment_id
    into v_charge_amount, v_charge_type, v_charge_enrollment_id
  from public.charges c
  where c.id = v_payment.charge_id
  for update;

  select e.status, e.exception_reason
    into v_enrollment_status, v_exception_reason
  from public.enrollments e
  where e.id = v_charge_enrollment_id
  for update;

  update public.payments
  set status = 'voided',
      void_reason = v_reason,
      voided_at = now(),
      voided_by = (select auth.uid())
  where id = p_payment_id;

  select coalesce(sum(p.amount), 0)
    into v_paid
  from public.payments p
  where p.charge_id = v_payment.charge_id
    and p.status = 'confirmed';

  v_balance := v_charge_amount - v_paid;

  if v_charge_type = 'registration'
     and v_balance > 0
     and v_enrollment_status = 'active' then
    if v_exception_reason is not null then
      update public.enrollments e
      set status = 'exception'
      where e.id = v_charge_enrollment_id
      returning e.status into v_enrollment_status;
    else
      update public.enrollments e
      set status = 'pending'
      where e.id = v_charge_enrollment_id
      returning e.status into v_enrollment_status;

      update public.students s
      set group_id = null
      where s.id = (
        select e.student_id
        from public.enrollments e
        where e.id = v_charge_enrollment_id
      );
    end if;
  end if;

  return query
  select
    p_payment_id,
    'voided'::text,
    v_balance,
    v_enrollment_status;
end;
$$;

revoke all on function public.register_payment(uuid, uuid, uuid, numeric, date, text, text, text)
  from public, anon, authenticated;
revoke all on function public.void_payment(uuid, text) from public, anon, authenticated;

grant execute on function public.register_payment(uuid, uuid, uuid, numeric, date, text, text, text)
  to authenticated;
grant execute on function public.void_payment(uuid, text) to authenticated;

