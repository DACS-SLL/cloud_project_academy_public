-- B01 - Bucket privado de vouchers.
-- Convención de ruta: {academy_id}/{payment_id}/{archivo}
-- El primer segmento se usa para autorizar por academia y rol.
-- Los objetos nunca son públicos; la descarga se hace autenticada o con URL firmada.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'vouchers',
  'vouchers',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy vouchers_select_staff on storage.objects
  for select to authenticated
  using (
    bucket_id = 'vouchers'
    and public.can_access_voucher(name)
  );

create policy vouchers_insert_staff on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'vouchers'
    and public.can_access_voucher(name)
  );

create policy vouchers_update_staff on storage.objects
  for update to authenticated
  using (
    bucket_id = 'vouchers'
    and public.can_access_voucher(name)
  )
  with check (
    bucket_id = 'vouchers'
    and public.can_access_voucher(name)
  );
