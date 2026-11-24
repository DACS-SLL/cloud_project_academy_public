#!/usr/bin/env node
// B01 - Verificación de roles, aislamiento por academia y Storage privado.
// Requiere SUPABASE_URL y SUPABASE_ANON_KEY (o VITE_SUPABASE_PUBLISHABLE_KEY).
// Ejecuta el seed ficticio antes: node scripts/seed-b01-demo.mjs
// Uso: node scripts/verify-b01-isolation.mjs

import { demoPasswordFor } from './demo-credentials.mjs';

const BASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY || '';

if (!BASE_URL || !ANON_KEY) {
  console.error('Faltan SUPABASE_URL y SUPABASE_ANON_KEY (o VITE_SUPABASE_PUBLISHABLE_KEY).');
  process.exit(1);
}

const ACADEMY_A = 'a1111111-1111-4111-8111-111111111111';
const ACADEMY_B = 'b2222222-2222-4222-8222-222222222222';
const GROUP_A = 'a1111111-1111-4111-8111-0000000000a1';
const GROUP_A2 = 'a1111111-1111-4111-8111-0000000000a0';
const STUDENT_A1 = 'a1111111-1111-4111-8111-0000000000a3';
const CHARGE_A1 = 'a1111111-1111-4111-8111-0000000000a7';
const PAYMENT_A1 = 'a1111111-1111-4111-8111-0000000000a9';
const PAYMENT_B1 = 'b2222222-2222-4222-8222-0000000000b9';
const VOUCHER_A = `${ACADEMY_A}/${PAYMENT_A1}/voucher-demo.png`;
const VOUCHER_B = `${ACADEMY_B}/${PAYMENT_B1}/voucher-demo.png`;

const ACCOUNTS = {
  adminA: 'admin.a@academia-demo.test',
  cashierA: 'caja.a@academia-demo.test',
  teacherA: 'docente.a@academia-demo.test',
  adminB: 'admin.b@academia-demo.test',
  cashierB: 'caja.b@academia-demo.test',
  teacherB: 'docente.b@academia-demo.test',
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

async function rows(token, table, query = '') {
  const response = await api(token, `/rest/v1/${table}?select=*${query ? `&${query}` : ''}`);
  if (response.status !== 200) {
    throw new Error(`${table} respondió ${response.status}: ${JSON.stringify(response.body)}`);
  }
  return response.body;
}

async function storageStatus(token, path) {
  const response = await fetch(`${BASE_URL}/storage/v1/object/vouchers/${path}`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
  });
  await response.arrayBuffer();
  return response.status;
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

  const accessA = await api(tokens.cashierA, '/rest/v1/rpc/my_access', {
    method: 'POST',
    body: JSON.stringify({}),
  });
  check(
    'cashier A obtiene su academia y rol por RPC',
    accessA.status === 200
      && Array.isArray(accessA.body)
      && accessA.body.length === 1
      && accessA.body[0].academy_id === ACADEMY_A
      && accessA.body[0].role === 'cashier',
    JSON.stringify(accessA.body),
  );

  const teacherAcademies = await rows(tokens.teacherA, 'academies', 'order=name');
  check(
    'docente A solo ve la academia A',
    teacherAcademies.length === 1 && teacherAcademies[0].id === ACADEMY_A,
    `filas=${teacherAcademies.length}`,
  );

  const teacherGroups = await rows(tokens.teacherA, 'groups');
  check(
    'docente A solo ve su grupo asignado',
    teacherGroups.length === 1 && teacherGroups[0].id === GROUP_A,
    `filas=${teacherGroups.length}`,
  );

  const teacherUnassignedGroup = await rows(tokens.teacherA, 'groups', `id=eq.${GROUP_A2}`);
  check(
    'docente A no ve un grupo no asignado',
    teacherUnassignedGroup.length === 0,
    `filas=${teacherUnassignedGroup.length}`,
  );

  const teacherSubjects = await rows(tokens.teacherA, 'subjects');
  check('docente A solo ve su curso asignado', teacherSubjects.length === 1, `filas=${teacherSubjects.length}`);

  const teacherStudents = await rows(tokens.teacherA, 'students');
  check(
    'docente A solo ve alumnos de su grupo asignado',
    teacherStudents.length === 2
      && teacherStudents.every((row) => row.academy_id === ACADEMY_A && row.group_id === GROUP_A),
    `filas=${teacherStudents.length}`,
  );

  const adminGroups = await rows(tokens.adminA, 'groups');
  check('admin A ve todos los grupos de su academia', adminGroups.length === 2, `filas=${adminGroups.length}`);

  for (const table of ['guardians', 'charges', 'payments']) {
    const response = await api(tokens.teacherA, `/rest/v1/${table}?select=*`);
    check(
      `docente A no lee ${table} (RLS)`,
      response.status === 200 && Array.isArray(response.body) && response.body.length === 0,
      `status=${response.status} filas=${Array.isArray(response.body) ? response.body.length : 'n/d'}`,
    );
  }

  const teacherSessions = await rows(tokens.teacherA, 'class_sessions');
  check(
    'docente A solo ve sus sesiones',
    teacherSessions.length >= 1 && teacherSessions.every((row) => row.academy_id === ACADEMY_A),
    `filas=${teacherSessions.length}`,
  );

  const teacherAttendance = await rows(tokens.teacherA, 'attendance');
  check(
    'docente A solo ve asistencia de sus sesiones',
    teacherAttendance.length >= 1 && teacherAttendance.every((row) => row.academy_id === ACADEMY_A),
    `filas=${teacherAttendance.length}`,
  );

  const adminCrossAcademy = await rows(tokens.adminA, 'academies', `id=eq.${ACADEMY_B}`);
  check('admin A no lee la academia B', adminCrossAcademy.length === 0, `filas=${adminCrossAcademy.length}`);

  const adminCrossGuardians = await rows(tokens.adminA, 'guardians', `academy_id=eq.${ACADEMY_B}`);
  check('admin A no lee apoderados de B', adminCrossGuardians.length === 0, `filas=${adminCrossGuardians.length}`);

  const cashierCrossPayments = await rows(tokens.cashierA, 'payments', `academy_id=eq.${ACADEMY_B}`);
  check('cashier A no lee pagos de B', cashierCrossPayments.length === 0, `filas=${cashierCrossPayments.length}`);

  const adminBOwn = await rows(tokens.adminB, 'academies');
  check(
    'admin B solo ve la academia B',
    adminBOwn.length === 1 && adminBOwn[0].id === ACADEMY_B,
    `filas=${adminBOwn.length}`,
  );

  const cashierPayments = await rows(tokens.cashierA, 'payments', `academy_id=eq.${ACADEMY_A}`);
  check(
    'cashier A lee los pagos de su academia',
    cashierPayments.length >= 1 && cashierPayments.every((row) => row.academy_id === ACADEMY_A),
    `filas=${cashierPayments.length}`,
  );

  const voucherCashier = await storageStatus(tokens.cashierA, VOUCHER_A);
  check('cashier A descarga el voucher de A', voucherCashier === 200, `status=${voucherCashier}`);

  const voucherTeacher = await storageStatus(tokens.teacherA, VOUCHER_A);
  check('docente A no descarga vouchers', voucherTeacher !== 200, `status=${voucherTeacher}`);

  const voucherCross = await storageStatus(tokens.adminA, VOUCHER_B);
  check('admin A no descarga vouchers de B', voucherCross !== 200, `status=${voucherCross}`);

  const cashierGroupPatch = await api(tokens.cashierA, `/rest/v1/students?id=eq.${STUDENT_A1}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ group_id: GROUP_A2 }),
  });
  check(
    'cashier A no cambia students.group_id directamente',
    cashierGroupPatch.status === 403,
    `status=${cashierGroupPatch.status}`,
  );

  const adminGroupPatch = await api(tokens.adminA, `/rest/v1/students?id=eq.${STUDENT_A1}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ group_id: GROUP_A2 }),
  });
  check(
    'admin A no cambia students.group_id directamente',
    adminGroupPatch.status === 403,
    `status=${adminGroupPatch.status}`,
  );

  for (const [role, token] of [['cashier A', tokens.cashierA], ['admin A', tokens.adminA]]) {
    const studentInsert = await api(token, '/rest/v1/students', {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({
        academy_id: ACADEMY_A,
        group_id: GROUP_A,
        full_name: 'Alumno no autorizado',
      }),
    });
    check(
      `${role} no crea alumnos con group_id directamente`,
      studentInsert.status === 403,
      `status=${studentInsert.status}`,
    );

    const studentDelete = await api(token, `/rest/v1/students?id=eq.${STUDENT_A1}`, {
      method: 'DELETE',
      headers: { Prefer: 'return=minimal' },
    });
    check(
      `${role} no elimina alumnos directamente`,
      studentDelete.status === 403,
      `status=${studentDelete.status}`,
    );
  }

  const cashierStudentPatch = await api(tokens.cashierA, `/rest/v1/students?id=eq.${STUDENT_A1}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ full_name: 'Alumno Ficticio A1' }),
  });
  check(
    'cashier A sí edita datos personales del alumno',
    cashierStudentPatch.status === 204,
    `status=${cashierStudentPatch.status}`,
  );

  for (const [role, token] of [['cashier A', tokens.cashierA], ['admin A', tokens.adminA]]) {
    const chargePatch = await api(token, `/rest/v1/charges?id=eq.${CHARGE_A1}`, {
      method: 'PATCH',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ amount: 1 }),
    });
    check(
      `${role} no actualiza cargos directamente`,
      chargePatch.status === 403,
      `status=${chargePatch.status}`,
    );

    const chargeDelete = await api(token, `/rest/v1/charges?id=eq.${CHARGE_A1}`, {
      method: 'DELETE',
      headers: { Prefer: 'return=minimal' },
    });
    check(
      `${role} no elimina cargos directamente`,
      chargeDelete.status === 403,
      `status=${chargeDelete.status}`,
    );
  }

  const cashierTransfer = await api(tokens.cashierA, '/rest/v1/rpc/transfer_student', {
    method: 'POST',
    body: JSON.stringify({ p_student_id: STUDENT_A1, p_group_id: GROUP_A2 }),
  });
  check(
    'cashier A no autoriza traslados por RPC',
    cashierTransfer.status === 403,
    `status=${cashierTransfer.status}`,
  );

  const adminTransferNoop = await api(tokens.adminA, '/rest/v1/rpc/transfer_student', {
    method: 'POST',
    body: JSON.stringify({ p_student_id: STUDENT_A1, p_group_id: GROUP_A }),
  });
  check(
    'admin A puede ejecutar el traslado autorizado',
    adminTransferNoop.status === 204,
    `status=${adminTransferNoop.status}`,
  );

  const anonResponse = await fetch(`${BASE_URL}/rest/v1/academies?select=id`, {
    headers: { apikey: ANON_KEY },
  });
  check(
    'anon no lee tablas directamente',
    anonResponse.status === 401 || anonResponse.status === 403,
    `status=${anonResponse.status}`,
  );

  const failures = results.filter((item) => !item.passed);
  console.log(`\n${results.length - failures.length}/${results.length} comprobaciones OK.`);
  if (failures.length > 0) {
    console.error('Fallaron:');
    for (const failure of failures) console.error(`- ${failure.name}: ${failure.detail}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
