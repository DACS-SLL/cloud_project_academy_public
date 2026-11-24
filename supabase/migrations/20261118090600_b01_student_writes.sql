-- B01 - Endurecimiento de creación y borrado de alumnos.
-- Un alumno puede crearse sin grupo, pero no puede nacer asignado a un grupo
-- por INSERT directo. La asignación/traslado pasa por transfer_student(),
-- que exige dirección y valida academia y cupo. El borrado directo se bloquea;
-- una baja lógica/administrativa se definirá en B02 con trazabilidad.

revoke insert on public.students from authenticated;
grant insert (academy_id, full_name, document_id, school, grade)
  on public.students to authenticated;

revoke delete on public.students from authenticated;
drop policy if exists students_delete_staff on public.students;

drop policy if exists students_insert_staff on public.students;
create policy students_insert_staff on public.students
  for insert to authenticated
  with check (
    group_id is null
    and public.has_academy_role(academy_id, '{admin,cashier}'::public.membership_role[])
  );
