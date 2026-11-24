#!/usr/bin/env node
// B01-B06 - Seed ficticio de dos academias, tres roles y datos de demo B05.
// Requiere: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (solo servidor).
// Uso: node scripts/seed-b01-demo.mjs
// No sube datos reales ni claves al repositorio.

const BASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!BASE_URL || !SERVICE_KEY) {
  console.error('Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY en el entorno.');
  process.exit(1);
}

const PASSWORD = process.env.Q01_DEMO_PASSWORD || '';
if (PASSWORD.length < 12) {
  console.error('Define Q01_DEMO_PASSWORD con al menos 12 caracteres para la instancia ficticia.');
  process.exit(1);
}

const ACADEMY_A = 'a1111111-1111-4111-8111-111111111111';
const ACADEMY_B = 'b2222222-2222-4222-8222-222222222222';

const CYCLE_A = 'a1111111-1111-4111-8111-0000000000c0';
const CYCLE_B = 'b2222222-2222-4222-8222-0000000000c0';
const GROUP_A = 'a1111111-1111-4111-8111-0000000000a1';
const GROUP_A2 = 'a1111111-1111-4111-8111-0000000000a0';
const GROUP_B = 'b2222222-2222-4222-8222-0000000000b1';
const SUBJECT_A = 'a1111111-1111-4111-8111-0000000000a2';
const SUBJECT_A2 = 'a1111111-1111-4111-8111-0000000000ae';
const SUBJECT_B = 'b2222222-2222-4222-8222-0000000000b2';
const STUDENT_A1 = 'a1111111-1111-4111-8111-0000000000a3';
const STUDENT_A2 = 'a1111111-1111-4111-8111-0000000000a4';
const STUDENT_B1 = 'b2222222-2222-4222-8222-0000000000b3';
const GUARDIAN_A1 = 'a1111111-1111-4111-8111-0000000000a5';
const GUARDIAN_A2 = 'a1111111-1111-4111-8111-0000000000a6';
const GUARDIAN_B1 = 'b2222222-2222-4222-8222-0000000000b5';
const CHARGE_A1 = 'a1111111-1111-4111-8111-0000000000a7';
const CHARGE_A1_M1 = 'a1111111-1111-4111-8111-0000000000c4';
const CHARGE_A1_M2 = 'a1111111-1111-4111-8111-0000000000c5';
const CHARGE_A1_M3 = 'a1111111-1111-4111-8111-0000000000c6';
const CHARGE_A2 = 'a1111111-1111-4111-8111-0000000000a8';
const CHARGE_A2_REG = 'a1111111-1111-4111-8111-0000000000c7';
const CHARGE_A2_M2 = 'a1111111-1111-4111-8111-0000000000c8';
const CHARGE_A2_M3 = 'a1111111-1111-4111-8111-0000000000c9';
const CHARGE_B1 = 'b2222222-2222-4222-8222-0000000000b7';
const CHARGE_B1_M1 = 'b2222222-2222-4222-8222-0000000000c4';
const CHARGE_B1_M2 = 'b2222222-2222-4222-8222-0000000000c5';
const CHARGE_B1_M3 = 'b2222222-2222-4222-8222-0000000000c6';
const PAYMENT_A1 = 'a1111111-1111-4111-8111-0000000000a9';
const PAYMENT_A1_M1 = 'a1111111-1111-4111-8111-0000000000d1';
const PAYMENT_B1 = 'b2222222-2222-4222-8222-0000000000b9';
const SESSION_A1 = 'a1111111-1111-4111-8111-0000000000aa';
const SESSION_B1 = 'b2222222-2222-4222-8222-0000000000ba';
const ATTENDANCE_A1 = 'a1111111-1111-4111-8111-0000000000ab';
const ATTENDANCE_A2 = 'a1111111-1111-4111-8111-0000000000ac';
const ATTENDANCE_B1 = 'b2222222-2222-4222-8222-0000000000bb';
const ASSIGNMENT_A1 = 'a1111111-1111-4111-8111-0000000000ad';
const ASSIGNMENT_B1 = 'b2222222-2222-4222-8222-0000000000bd';

const VOUCHER_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  'base64',
);

const USERS = [
  { key: 'adminA', email: 'admin.a@academia-demo.test', fullName: 'Dirección Demo Norte', academy: ACADEMY_A, role: 'admin' },
  { key: 'cashierA', email: 'caja.a@academia-demo.test', fullName: 'Secretaría Demo Norte', academy: ACADEMY_A, role: 'cashier' },
  { key: 'teacherA', email: 'docente.a@academia-demo.test', fullName: 'Docente Demo Norte', academy: ACADEMY_A, role: 'teacher' },
  { key: 'adminB', email: 'admin.b@academia-demo.test', fullName: 'Dirección Demo Sur', academy: ACADEMY_B, role: 'admin' },
  { key: 'cashierB', email: 'caja.b@academia-demo.test', fullName: 'Secretaría Demo Sur', academy: ACADEMY_B, role: 'cashier' },
  { key: 'teacherB', email: 'docente.b@academia-demo.test', fullName: 'Docente Demo Sur', academy: ACADEMY_B, role: 'teacher' },
];

function serviceHeaders(extra = {}) {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
    ...extra,
  };
}

async function request(path, { method = 'GET', body, headers } = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: serviceHeaders(headers),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${method} ${path} respondió ${response.status}: ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

async function listUsers() {
  const users = [];
  for (let page = 1; ; page += 1) {
    const data = await request(`/auth/v1/admin/users?page=${page}&per_page=200`);
    const batch = data?.users ?? [];
    users.push(...batch);
    if (batch.length < 200) break;
  }
  return users;
}

async function ensureUser(user, existingUsers) {
  const found = existingUsers.find(
    (item) => item.email?.toLowerCase() === user.email.toLowerCase(),
  );
  if (found) return found.id;

  const created = await request('/auth/v1/admin/users', {
    method: 'POST',
    body: {
      email: user.email,
      password: PASSWORD,
      email_confirm: true,
      user_metadata: { full_name: user.fullName },
    },
  });
  existingUsers.push(created);
  return created.id;
}

async function upsert(table, rows, onConflict) {
  if (rows.length === 0) return;
  const query = onConflict ? `?on_conflict=${encodeURIComponent(onConflict)}` : '';
  await request(`/rest/v1/${table}${query}`, {
    method: 'POST',
    body: rows,
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
  });
}

async function uploadVoucher(path) {
  const response = await fetch(`${BASE_URL}/storage/v1/object/vouchers/${path}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: VOUCHER_PNG,
  });
  if (!response.ok && response.status !== 409) {
    const text = await response.text();
    throw new Error(`No se pudo subir ${path}: ${response.status} ${text}`);
  }
}

async function main() {
  const existingUsers = await listUsers();
  const userIds = {};
  for (const user of USERS) {
    userIds[user.key] = await ensureUser(user, existingUsers);
  }

  const voucherA = `${ACADEMY_A}/${PAYMENT_A1}/voucher-demo.png`;
  const voucherA1M1 = `${ACADEMY_A}/${PAYMENT_A1_M1}/voucher-demo.png`;
  const voucherB = `${ACADEMY_B}/${PAYMENT_B1}/voucher-demo.png`;
  await uploadVoucher(voucherA);
  await uploadVoucher(voucherA1M1);
  await uploadVoucher(voucherB);

  await upsert('academies', [
    { id: ACADEMY_A, name: 'Academia Demo Norte' },
    { id: ACADEMY_B, name: 'Academia Demo Sur' },
  ], 'id');

  await upsert('profiles', USERS.map((user) => ({
    id: userIds[user.key],
    full_name: user.fullName,
  })), 'id');

  await upsert('memberships', USERS.map((user) => ({
    academy_id: user.academy,
    user_id: userIds[user.key],
    role: user.role,
  })), 'academy_id,user_id');

  await upsert('cycles', [
    {
      id: CYCLE_A,
      academy_id: ACADEMY_A,
      name: 'Ciclo Demo 2026',
      start_date: '2026-11-01',
      end_date: '2027-01-31',
      grade: '5.º secundaria',
      warning_absences: 10,
      review_absences: 15,
      late_counts_as_absence: true,
    },
    {
      id: CYCLE_B,
      academy_id: ACADEMY_B,
      name: 'Ciclo Demo 2026',
      start_date: '2026-11-01',
      end_date: '2027-01-31',
      grade: '5.º secundaria',
      warning_absences: 10,
      review_absences: 15,
      late_counts_as_absence: true,
    },
  ], 'id');

  await upsert('groups', [
    { id: GROUP_A, academy_id: ACADEMY_A, cycle_id: CYCLE_A, name: '5.º B mañana', shift: 'morning', capacity: 2 },
    { id: GROUP_A2, academy_id: ACADEMY_A, cycle_id: CYCLE_A, name: '5.º C mañana', shift: 'morning', capacity: 2 },
    { id: GROUP_B, academy_id: ACADEMY_B, cycle_id: CYCLE_B, name: '5.º A tarde', shift: 'afternoon', capacity: 2 },
  ], 'id');

  await upsert('subjects', [
    { id: SUBJECT_A, academy_id: ACADEMY_A, name: 'Matemática' },
    { id: SUBJECT_A2, academy_id: ACADEMY_A, name: 'Comunicación' },
    { id: SUBJECT_B, academy_id: ACADEMY_B, name: 'Comunicación' },
  ], 'id');

  await upsert('teacher_assignments', [
    { id: ASSIGNMENT_A1, academy_id: ACADEMY_A, teacher_id: userIds.teacherA, group_id: GROUP_A, subject_id: SUBJECT_A },
    { id: ASSIGNMENT_B1, academy_id: ACADEMY_B, teacher_id: userIds.teacherB, group_id: GROUP_B, subject_id: SUBJECT_B },
  ], 'id');

  await upsert('students', [
    { id: STUDENT_A1, academy_id: ACADEMY_A, group_id: GROUP_A, full_name: 'Alumno Ficticio A1', document_id: '00000001', school: 'Colegio Demo', grade: '5.º secundaria' },
    { id: STUDENT_A2, academy_id: ACADEMY_A, group_id: GROUP_A, full_name: 'Alumno Ficticio A2', document_id: '00000002', school: 'Colegio Demo', grade: '5.º secundaria' },
    { id: STUDENT_B1, academy_id: ACADEMY_B, group_id: GROUP_B, full_name: 'Alumno Ficticio B1', document_id: '00000003', school: 'Colegio Demo Sur', grade: '5.º secundaria' },
  ], 'id');

  await upsert('guardians', [
    { id: GUARDIAN_A1, academy_id: ACADEMY_A, student_id: STUDENT_A1, full_name: 'Apoderado Ficticio A1', document_id: '10000001', phone: '+51 900 000 001' },
    { id: GUARDIAN_A2, academy_id: ACADEMY_A, student_id: STUDENT_A2, full_name: 'Apoderado Ficticio A2', document_id: '10000002', phone: '+51 900 000 002' },
    { id: GUARDIAN_B1, academy_id: ACADEMY_B, student_id: STUDENT_B1, full_name: 'Apoderado Ficticio B1', document_id: '10000003', phone: '+51 900 000 003' },
  ], 'id');

  // Alinea matrículas heredadas de B01 con el ciclo demo explícito.
  for (const enrollment of [
    { academy_id: ACADEMY_A, student_id: STUDENT_A1, cycle_id: CYCLE_A, group_id: GROUP_A },
    { academy_id: ACADEMY_A, student_id: STUDENT_A2, cycle_id: CYCLE_A, group_id: GROUP_A },
    { academy_id: ACADEMY_B, student_id: STUDENT_B1, cycle_id: CYCLE_B, group_id: GROUP_B },
  ]) {
    await request(
      `/rest/v1/enrollments?academy_id=eq.${enrollment.academy_id}&student_id=eq.${enrollment.student_id}`,
      {
        method: 'PATCH',
        body: { cycle_id: enrollment.cycle_id, group_id: enrollment.group_id },
        headers: { Prefer: 'return=minimal' },
      },
    );
  }

  const enrollmentPayloads = [
    {
      academy_id: ACADEMY_A,
      student_id: STUDENT_A1,
      cycle_id: CYCLE_A,
      group_id: GROUP_A,
      status: 'active',
      agreed_registration_price: 200,
      agreed_monthly_price: 200,
      exception_reason: null,
      exception_due_date: null,
      authorized_by: null,
      authorized_at: null,
      created_by: userIds.cashierA,
    },
    {
      academy_id: ACADEMY_A,
      student_id: STUDENT_A2,
      cycle_id: CYCLE_A,
      group_id: GROUP_A,
      status: 'exception',
      agreed_registration_price: 200,
      agreed_monthly_price: 200,
      exception_reason: 'Matrícula excepcional demo hasta regularizar inscripción',
      exception_due_date: '2026-11-30',
      authorized_by: userIds.adminA,
      authorized_at: '2026-11-18T12:00:00Z',
      created_by: userIds.cashierA,
    },
    {
      academy_id: ACADEMY_B,
      student_id: STUDENT_B1,
      cycle_id: CYCLE_B,
      group_id: GROUP_B,
      status: 'active',
      agreed_registration_price: 200,
      agreed_monthly_price: 200,
      exception_reason: null,
      exception_due_date: null,
      authorized_by: null,
      authorized_at: null,
      created_by: userIds.cashierB,
    },
  ];

  for (const payload of enrollmentPayloads) {
    const existing = await request(
      `/rest/v1/enrollments?select=id&academy_id=eq.${payload.academy_id}&student_id=eq.${payload.student_id}`,
    );
    if (existing.length > 0) {
      await request(`/rest/v1/enrollments?id=eq.${existing[0].id}`, {
        method: 'PATCH',
        body: payload,
        headers: { Prefer: 'return=minimal' },
      });
    } else {
      await request('/rest/v1/enrollments', {
        method: 'POST',
        body: payload,
        headers: { Prefer: 'return=minimal' },
      });
    }
  }

  const enrollmentRows = await request(
    `/rest/v1/enrollments?select=id,student_id&student_id=in.(${STUDENT_A1},${STUDENT_A2},${STUDENT_B1})`,
  );
  const enrollmentByStudent = Object.fromEntries(
    enrollmentRows.map((row) => [row.student_id, row.id]),
  );

  await upsert('charges', [
    { id: CHARGE_A1, academy_id: ACADEMY_A, student_id: STUDENT_A1, enrollment_id: enrollmentByStudent[STUDENT_A1], type: 'registration', amount: 200, due_date: '2026-11-10' },
    { id: CHARGE_A1_M1, academy_id: ACADEMY_A, student_id: STUDENT_A1, enrollment_id: enrollmentByStudent[STUDENT_A1], type: 'monthly', amount: 200, due_date: '2026-12-10' },
    { id: CHARGE_A1_M2, academy_id: ACADEMY_A, student_id: STUDENT_A1, enrollment_id: enrollmentByStudent[STUDENT_A1], type: 'monthly', amount: 200, due_date: '2027-01-10' },
    { id: CHARGE_A1_M3, academy_id: ACADEMY_A, student_id: STUDENT_A1, enrollment_id: enrollmentByStudent[STUDENT_A1], type: 'monthly', amount: 200, due_date: '2027-02-10' },
    { id: CHARGE_A2_REG, academy_id: ACADEMY_A, student_id: STUDENT_A2, enrollment_id: enrollmentByStudent[STUDENT_A2], type: 'registration', amount: 200, due_date: '2026-11-10' },
    { id: CHARGE_A2, academy_id: ACADEMY_A, student_id: STUDENT_A2, enrollment_id: enrollmentByStudent[STUDENT_A2], type: 'monthly', amount: 200, due_date: '2026-12-10' },
    { id: CHARGE_A2_M2, academy_id: ACADEMY_A, student_id: STUDENT_A2, enrollment_id: enrollmentByStudent[STUDENT_A2], type: 'monthly', amount: 200, due_date: '2027-01-10' },
    { id: CHARGE_A2_M3, academy_id: ACADEMY_A, student_id: STUDENT_A2, enrollment_id: enrollmentByStudent[STUDENT_A2], type: 'monthly', amount: 200, due_date: '2027-02-10' },
    { id: CHARGE_B1, academy_id: ACADEMY_B, student_id: STUDENT_B1, enrollment_id: enrollmentByStudent[STUDENT_B1], type: 'registration', amount: 200, due_date: '2026-11-12' },
    { id: CHARGE_B1_M1, academy_id: ACADEMY_B, student_id: STUDENT_B1, enrollment_id: enrollmentByStudent[STUDENT_B1], type: 'monthly', amount: 200, due_date: '2026-12-12' },
    { id: CHARGE_B1_M2, academy_id: ACADEMY_B, student_id: STUDENT_B1, enrollment_id: enrollmentByStudent[STUDENT_B1], type: 'monthly', amount: 200, due_date: '2027-01-12' },
    { id: CHARGE_B1_M3, academy_id: ACADEMY_B, student_id: STUDENT_B1, enrollment_id: enrollmentByStudent[STUDENT_B1], type: 'monthly', amount: 200, due_date: '2027-02-12' },
  ], 'id');

  await upsert('payments', [
    { id: PAYMENT_A1, academy_id: ACADEMY_A, charge_id: CHARGE_A1, amount: 200, paid_at: '2026-11-10', method: 'bank_transfer', reference: 'DEMO-A-001', voucher_path: voucherA, status: 'confirmed', created_by: userIds.cashierA },
    { id: PAYMENT_A1_M1, academy_id: ACADEMY_A, charge_id: CHARGE_A1_M1, amount: 80, paid_at: '2026-12-05', method: 'bank_transfer', reference: 'DEMO-A-002', voucher_path: voucherA1M1, status: 'confirmed', created_by: userIds.cashierA },
    { id: PAYMENT_B1, academy_id: ACADEMY_B, charge_id: CHARGE_B1, amount: 200, paid_at: '2026-11-12', method: 'bank_deposit', reference: 'DEMO-B-001', voucher_path: voucherB, status: 'confirmed', created_by: userIds.cashierB },
  ], 'id');

  await upsert('class_sessions', [
    { id: SESSION_A1, academy_id: ACADEMY_A, group_id: GROUP_A, subject_id: SUBJECT_A, teacher_id: userIds.teacherA, starts_at: '2026-11-18T13:00:00Z' },
    { id: SESSION_B1, academy_id: ACADEMY_B, group_id: GROUP_B, subject_id: SUBJECT_B, teacher_id: userIds.teacherB, starts_at: '2026-11-18T18:00:00Z' },
  ], 'id');

  // B05/A09: deja 9 faltas históricas en A1 y 14 en A2. La siguiente
  // asistencia ausente en una sesión real alcanza 10 y 15 respectivamente.
  const b05Sessions = Array.from({ length: 13 }, (_, index) => ({
    id: `a1111111-1111-4111-8111-${(0xe0 + index).toString(16).padStart(12, '0')}`,
    academy_id: ACADEMY_A,
    group_id: GROUP_A,
    subject_id: SUBJECT_A,
    teacher_id: userIds.teacherA,
    starts_at: `2026-11-${String(index + 2).padStart(2, '0')}T13:00:00Z`,
  }));
  const b05Attendance = b05Sessions.flatMap((session, index) => {
    const rows = [{
      id: `a1111111-1111-4111-8111-${(0xf0 + index).toString(16).padStart(12, '0')}`,
      academy_id: ACADEMY_A,
      session_id: session.id,
      student_id: STUDENT_A2,
      status: 'absent',
    }];
    if (index < 9) {
      rows.push({
        id: `a1111111-1111-4111-8111-${(0x100 + index).toString(16).padStart(12, '0')}`,
        academy_id: ACADEMY_A,
        session_id: session.id,
        student_id: STUDENT_A1,
        status: 'absent',
      });
    }
    return rows;
  });

  await upsert('class_sessions', b05Sessions, 'id');
  await upsert('attendance', b05Attendance, 'id');

  await upsert('attendance', [
    { id: ATTENDANCE_A1, academy_id: ACADEMY_A, session_id: SESSION_A1, student_id: STUDENT_A1, status: 'present' },
    { id: ATTENDANCE_A2, academy_id: ACADEMY_A, session_id: SESSION_A1, student_id: STUDENT_A2, status: 'absent' },
    { id: ATTENDANCE_B1, academy_id: ACADEMY_B, session_id: SESSION_B1, student_id: STUDENT_B1, status: 'present' },
  ], 'id');

  console.log('Seed B01-B06 completado.');
  console.log('Academias: Academia Demo Norte (A) y Academia Demo Sur (B)');
  console.log('B05: A1 queda con 9 faltas y A2 con 14 para demostrar 10/15.');
  console.log('Contraseña demo recibida por variable de entorno; valor omitido.');
  console.table(USERS.map((user) => ({
    academia: user.academy === ACADEMY_A ? 'A' : 'B',
    rol: user.role,
    correo: user.email,
  })));
  console.log('Voucher demo:');
  console.log(`  A: vouchers/${voucherA}`);
  console.log(`  B: vouchers/${voucherB}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
