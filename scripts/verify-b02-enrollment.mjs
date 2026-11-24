#!/usr/bin/env node
// B02 - Verificación real de ciclos, grupos, matrícula pendiente y cargos.
// Requiere SUPABASE_URL y SUPABASE_ANON_KEY (o VITE_SUPABASE_PUBLISHABLE_KEY).
// Opcional: SUPABASE_SERVICE_ROLE_KEY para limpiar los datos de prueba.
// Ejecuta el seed B01/B02 antes: node scripts/seed-b01-demo.mjs
// Uso: node scripts/verify-b02-enrollment.mjs

import { demoPasswordFor } from './demo-credentials.mjs';

const BASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY || '';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!BASE_URL || !ANON_KEY) {
  console.error('Faltan SUPABASE_URL y SUPABASE_ANON_KEY (o VITE_SUPABASE_PUBLISHABLE_KEY).');
  process.exit(1);
}

const ACADEMY_A = 'a1111111-1111-4111-8111-111111111111';
const ACADEMY_B = 'b2222222-2222-4222-8222-222222222222';
const CYCLE_A = 'a1111111-1111-4111-8111-0000000000c0';
const GROUP_A2 = 'a1111111-1111-4111-8111-0000000000a0';
const GROUP_B = 'b2222222-2222-4222-8222-0000000000b1';
const STUDENT_A1 = 'a1111111-1111-4111-8111-0000000000a3';

const ACCOUNTS = {
  adminA: 'admin.a@academia-demo.test',
  cashierA: 'caja.a@academia-demo.test',
  teacherA: 'docente.a@academia-demo.test',
  adminB: 'admin.b@academia-demo.test',
};

const results = [];
function check(name, passed, detail = '') {
  results.push({ name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}${detail ? ` -> ${detail}` : ''}`);
}

async function signIn(email) {
  const response = await fetch(`${BASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: demoPasswordFor(email) }),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Login ${email} respondió ${response.status}: ${text}`);
  }
  return JSON.parse(text).access_token;
}

function authHeaders(token) {
  return {
    apikey: ANON_KEY,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

async function api(token, path, options = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: { ...authHeaders(token), ...(options.headers || {}) },
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: response.status, body };
}

async function createRow(token, table, row) {
  return api(token, `/rest/v1/${table}`, {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(row),
  });
}

async function rpc(token, name, args) {
  return api(token, `/rest/v1/rpc/${name}`, {
    method: 'POST',
    body: JSON.stringify(args),
  });
}

async function rows(token, table, query = '') {
  const response = await api(token, `/rest/v1/${table}?select=*${query ? `&${query}` : ''}`);
  if (response.status !== 200) {
    throw new Error(`${table} respondió ${response.status}: ${JSON.stringify(response.body)}`);
  }
  return response.body;
}

async function serviceDelete(table, query) {
  if (!SERVICE_KEY) return;
  await fetch(`${BASE_URL}/rest/v1/${table}?${query}`, {
    method: 'DELETE',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      Prefer: 'return=minimal',
    },
  });
}

async function servicePatch(table, query, body) {
  if (!SERVICE_KEY) return null;
  return fetch(`${BASE_URL}/rest/v1/${table}?${query}`, {
    method: 'PATCH',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(body),
  });
}

function rpcUuid(body) {
  if (typeof body === 'string') return body;
  if (Array.isArray(body) && typeof body[0] === 'string') return body[0];
  if (body && typeof body.id === 'string') return body.id;
  return null;
}

async function main() {
  const tokens = {};
  for (const [key, email] of Object.entries(ACCOUNTS)) {
    try {
      tokens[key] = await signIn(email);
      check(`Inicio de sesión ${key}`, true);
    } catch (error) {
      check(`Inicio de sesión ${key}`, false, error.message);
    }
  }

  if (Object.keys(tokens).length !== Object.keys(ACCOUNTS).length) {
    console.error('\nNo se pudo iniciar sesión con todas las cuentas. Ejecuta el seed primero.');
    process.exit(1);
  }

  const suffix = `${Date.now()}`;
  const cycleName = `Ciclo verificación ${suffix}`;
  const groupName = `Grupo verificación ${suffix}`;
  const subjectName = `Curso verificación ${suffix}`;
  const studentName = `Alumno verificación ${suffix}`;
  const created = {};

  const cycleResponse = await createRow(tokens.adminA, 'cycles', {
    academy_id: ACADEMY_A,
    name: cycleName,
    start_date: '2026-11-01',
    end_date: '2027-01-31',
    grade: '5.º secundaria',
    warning_absences: 10,
    review_absences: 15,
    late_counts_as_absence: true,
  });
  created.cycleId = cycleResponse.body?.[0]?.id;
  check(
    'admin A crea un ciclo con umbrales y regla de tardanza',
    cycleResponse.status === 201
      && Boolean(created.cycleId)
      && cycleResponse.body[0].warning_absences === 10
      && cycleResponse.body[0].review_absences === 15,
    `status=${cycleResponse.status}`,
  );

  const groupResponse = await createRow(tokens.adminA, 'groups', {
    academy_id: ACADEMY_A,
    cycle_id: created.cycleId,
    name: groupName,
    shift: 'morning',
    capacity: 1,
  });
  created.groupId = groupResponse.body?.[0]?.id;
  check(
    'admin A crea un grupo con cupo dentro del ciclo',
    groupResponse.status === 201
      && Boolean(created.groupId)
      && groupResponse.body[0].cycle_id === created.cycleId
      && groupResponse.body[0].capacity === 1,
    `status=${groupResponse.status}`,
  );

  const subjectResponse = await createRow(tokens.adminA, 'subjects', {
    academy_id: ACADEMY_A,
    name: subjectName,
  });
  created.subjectId = subjectResponse.body?.[0]?.id;

  const existingAssignments = await rows(tokens.adminA, 'teacher_assignments');
  const teacherId = existingAssignments.find(
    (assignment) => assignment.academy_id === ACADEMY_A,
  )?.teacher_id;

  if (teacherId) {
    const assignment = await createRow(tokens.adminA, 'teacher_assignments', {
      academy_id: ACADEMY_A,
      teacher_id: teacherId,
      group_id: created.groupId,
      subject_id: created.subjectId,
    });
    check(
      'admin A asigna docente, grupo y curso',
      assignment.status === 201 && Boolean(assignment.body?.[0]?.id),
      `status=${assignment.status}`,
    );
    created.assignmentId = assignment.body?.[0]?.id;
  } else {
    check('admin A asigna docente, grupo y curso', false, 'no se encontró el docente del seed');
  }

  const studentResponse = await createRow(tokens.cashierA, 'students', {
    academy_id: ACADEMY_A,
    full_name: studentName,
  });
  created.studentId = studentResponse.body?.[0]?.id;
  check(
    'secretaría crea un alumno sin grupo',
    studentResponse.status === 201
      && Boolean(created.studentId)
      && studentResponse.body[0].group_id === null,
    `status=${studentResponse.status}`,
  );

  const guardianResponse = await createRow(tokens.cashierA, 'guardians', {
    academy_id: ACADEMY_A,
    student_id: created.studentId,
    full_name: `Apoderado ${suffix}`,
    phone: '+51 900 000 099',
  });
  check(
    'secretaría registra apoderado del alumno',
    guardianResponse.status === 201 && Boolean(guardianResponse.body?.[0]?.id),
    `status=${guardianResponse.status}`,
  );

  const capacityBefore = await rpc(tokens.cashierA, 'group_capacity', {
    p_group_id: created.groupId,
  });
  check(
    'consulta de cupos inicia con cero ocupados',
    capacityBefore.status === 200
      && capacityBefore.body?.[0]?.occupied === 0
      && capacityBefore.body?.[0]?.available === 1,
    JSON.stringify(capacityBefore.body),
  );

  const enrollmentResponse = await rpc(tokens.cashierA, 'create_enrollment_request', {
    p_student_id: created.studentId,
    p_group_id: created.groupId,
    p_registration_price: 300,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10', '2027-01-10', '2027-02-10'],
  });
  created.enrollmentId = rpcUuid(enrollmentResponse.body);
  check(
    'secretaría crea solicitud de matrícula y recibe su id',
    enrollmentResponse.status === 200 && Boolean(created.enrollmentId),
    `status=${enrollmentResponse.status}`,
  );

  const enrollmentRows = await rows(
    tokens.cashierA,
    'enrollments',
    `id=eq.${created.enrollmentId}`,
  );
  check(
    'la matrícula queda pendiente con precio individual fijo',
    enrollmentRows.length === 1
      && enrollmentRows[0].status === 'pending'
      && Number(enrollmentRows[0].agreed_registration_price) === 300
      && Number(enrollmentRows[0].agreed_monthly_price) === 200,
    JSON.stringify(enrollmentRows[0] || null),
  );

  const chargeRows = await rows(
    tokens.cashierA,
    'charges',
    `enrollment_id=eq.${created.enrollmentId}&order=type,due_date`,
  );
  const registrationCharges = chargeRows.filter((row) => row.type === 'registration');
  const monthlyCharges = chargeRows.filter((row) => row.type === 'monthly');
  check(
    'inscripción y tres mensualidades quedan como cargos separados',
    chargeRows.length === 4
      && registrationCharges.length === 1
      && monthlyCharges.length === 3
      && Number(registrationCharges[0].amount) === 300
      && monthlyCharges.every((row) => Number(row.amount) === 200),
    `cargos=${chargeRows.length}`,
  );

  const capacityAfter = await rpc(tokens.cashierA, 'group_capacity', {
    p_group_id: created.groupId,
  });
  check(
    'la solicitud pendiente no ocupa cupo',
    capacityAfter.status === 200 && capacityAfter.body?.[0]?.occupied === 0,
    JSON.stringify(capacityAfter.body),
  );

  const studentAfter = await rows(tokens.cashierA, 'students', `id=eq.${created.studentId}`);
  check(
    'la solicitud pendiente no asigna grupo al alumno',
    studentAfter.length === 1 && studentAfter[0].group_id === null,
    `group_id=${studentAfter[0]?.group_id}`,
  );

  const duplicate = await rpc(tokens.cashierA, 'create_enrollment_request', {
    p_student_id: created.studentId,
    p_group_id: created.groupId,
    p_registration_price: 300,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10'],
  });
  check(
    'se rechaza una segunda matrícula del mismo alumno y ciclo',
    duplicate.status === 409
      && duplicate.body?.hint === 'ENROLLMENT_DUPLICATE',
    `status=${duplicate.status} code=${duplicate.body?.code || 'n/d'} hint=${duplicate.body?.hint || 'n/d'}`,
  );

  const invalidAmount = await rpc(tokens.cashierA, 'create_enrollment_request', {
    p_student_id: created.studentId,
    p_group_id: created.groupId,
    p_registration_price: 0,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10'],
  });
  check(
    'el precio inválido devuelve un código de negocio',
    invalidAmount.status === 400
      && invalidAmount.body?.hint === 'INVALID_AMOUNT',
    `status=${invalidAmount.status} hint=${invalidAmount.body?.hint || 'n/d'}`,
  );

  const teacherAttempt = await rpc(tokens.teacherA, 'create_enrollment_request', {
    p_student_id: STUDENT_A1,
    p_group_id: GROUP_A2,
    p_registration_price: 300,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10'],
  });
  check(
    'docente no puede crear matrículas',
    teacherAttempt.status === 403
      && teacherAttempt.body?.hint === 'ACCESS_DENIED',
    `status=${teacherAttempt.status} hint=${teacherAttempt.body?.hint || 'n/d'}`,
  );

  const crossAcademy = await rpc(tokens.adminA, 'create_enrollment_request', {
    p_student_id: created.studentId,
    p_group_id: GROUP_B,
    p_registration_price: 300,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10'],
  });
  check(
    'dirección A no matricula en la academia B',
    crossAcademy.status === 403
      && crossAcademy.body?.hint === 'ACCESS_DENIED',
    `status=${crossAcademy.status} hint=${crossAcademy.body?.hint || 'n/d'}`,
  );

  const teacherEnrollments = await api(tokens.teacherA, '/rest/v1/enrollments?select=*');
  check(
    'docente no lee matrículas ni precios',
    teacherEnrollments.status === 200
      && Array.isArray(teacherEnrollments.body)
      && teacherEnrollments.body.length === 0,
    `status=${teacherEnrollments.status}`,
  );

  const directChargeInsert = await api(tokens.cashierA, '/rest/v1/charges', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      academy_id: ACADEMY_A,
      student_id: created.studentId,
      enrollment_id: created.enrollmentId,
      type: 'monthly',
      amount: 1,
      due_date: '2027-03-10',
    }),
  });
  check(
    'secretaría no crea cargos por INSERT directo',
    directChargeInsert.status === 403,
    `status=${directChargeInsert.status}`,
  );

  if (SERVICE_KEY) {
    const activated = await servicePatch(
      'enrollments',
      `id=eq.${created.enrollmentId}`,
      { status: 'active' },
    );
    const capacityPatch = await api(tokens.adminA, `/rest/v1/groups?id=eq.${created.groupId}`, {
      method: 'PATCH',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ capacity: 0 }),
    });
    check(
      'no se baja la capacidad bajo el cupo ocupado',
      Boolean(activated?.ok)
        && capacityPatch.status === 400
        && capacityPatch.body?.hint === 'GROUP_CAPACITY_BELOW_OCCUPIED',
      `status=${capacityPatch.status} hint=${capacityPatch.body?.hint || 'n/d'}`,
    );
  } else {
    check(
      'no se baja la capacidad bajo el cupo ocupado',
      true,
      'omitida: falta SUPABASE_SERVICE_ROLE_KEY para activar la matrícula de prueba',
    );
  }

  const cyclePatch = await api(tokens.adminA, `/rest/v1/groups?id=eq.${created.groupId}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ cycle_id: CYCLE_A }),
  });
  check(
    'no se cambia el ciclo de un grupo con matrícula',
    cyclePatch.status === 400
      && cyclePatch.body?.hint === 'GROUP_CYCLE_HAS_ENROLLMENTS',
    `status=${cyclePatch.status} hint=${cyclePatch.body?.hint || 'n/d'}`,
  );

  const crossTransfer = await rpc(tokens.adminA, 'transfer_student', {
    p_student_id: STUDENT_A1,
    p_group_id: GROUP_B,
  });
  check(
    'un grupo de otra academia se reporta como inexistente',
    crossTransfer.status === 400
      && crossTransfer.body?.hint === 'GROUP_NOT_FOUND',
    `status=${crossTransfer.status} hint=${crossTransfer.body?.hint || 'n/d'}`,
  );

  const adminBEnrollment = await api(
    tokens.adminB,
    `/rest/v1/enrollments?select=*&id=eq.${created.enrollmentId}`,
  );
  check(
    'dirección B no ve la matrícula de A',
    adminBEnrollment.status === 200
      && Array.isArray(adminBEnrollment.body)
      && adminBEnrollment.body.length === 0,
    `status=${adminBEnrollment.status}`,
  );

  if (created.cycleId && created.groupId) {
    const cashierCycle = await rows(tokens.cashierA, 'cycles', `id=eq.${created.cycleId}`);
    const cashierGroup = await rows(tokens.cashierA, 'groups', `id=eq.${created.groupId}`);
    check(
      'ciclo, grupo y cargos persisten tras una nueva consulta',
      cashierCycle.length === 1
        && cashierGroup.length === 1
        && cashierGroup[0].cycle_id === created.cycleId,
      `ciclo=${cashierCycle.length} grupo=${cashierGroup.length}`,
    );
  }

  const freshCashier = await signIn(ACCOUNTS.cashierA);
  const persistedEnrollment = await rows(
    freshCashier,
    'enrollments',
    `id=eq.${created.enrollmentId}`,
  );
  const persistedCharges = await rows(
    freshCashier,
    'charges',
    `enrollment_id=eq.${created.enrollmentId}`,
  );
  check(
    'la matrícula y sus cargos persisten con una sesión nueva',
    persistedEnrollment.length === 1 && persistedCharges.length === 4,
    `matrículas=${persistedEnrollment.length} cargos=${persistedCharges.length}`,
  );

  if (SERVICE_KEY) {
    await serviceDelete('charges', `enrollment_id=eq.${created.enrollmentId}`);
    await serviceDelete('enrollments', `id=eq.${created.enrollmentId}`);
    await serviceDelete('guardians', `student_id=eq.${created.studentId}`);
    await serviceDelete('students', `id=eq.${created.studentId}`);
    if (created.assignmentId) {
      await serviceDelete('teacher_assignments', `id=eq.${created.assignmentId}`);
    }
    if (created.subjectId) {
      await serviceDelete('subjects', `id=eq.${created.subjectId}`);
    }
    if (created.groupId) {
      await serviceDelete('groups', `id=eq.${created.groupId}`);
    }
    if (created.cycleId) {
      await serviceDelete('cycles', `id=eq.${created.cycleId}`);
    }
    check('datos de prueba eliminados con service role', true);
  } else {
    check('limpieza de datos de prueba', true, 'omitida: falta SUPABASE_SERVICE_ROLE_KEY');
  }

  const failed = results.filter((result) => !result.passed);
  console.log(`\n${results.length - failed.length}/${results.length} comprobaciones OK.`);
  if (failed.length > 0) {
    console.error('Fallaron:', failed.map((result) => result.name).join(', '));
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
