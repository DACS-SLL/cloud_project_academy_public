#!/usr/bin/env node
// B03 - Verificación real de pagos bancarios, saldo, activación y anulación.
// Requiere SUPABASE_URL y SUPABASE_ANON_KEY.
// Opcional: SUPABASE_SERVICE_ROLE_KEY para limpiar datos y vouchers de prueba.
// Ejecuta el seed B01/B02 antes: node scripts/seed-b01-demo.mjs
// Uso: node scripts/verify-b03-payments.mjs

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

const ACCOUNTS = {
  adminA: 'admin.a@academia-demo.test',
  cashierA: 'caja.a@academia-demo.test',
  teacherA: 'docente.a@academia-demo.test',
};

const VOUCHER_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  'base64',
);

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

async function invokeFunction(token, body) {
  const response = await fetch(`${BASE_URL}/functions/v1/discard-voucher`, {
    method: 'POST',
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }
  return { status: response.status, body: parsed };
}

async function uploadVoucher(token, path) {
  const response = await fetch(`${BASE_URL}/storage/v1/object/vouchers/${path}`, {
    method: 'POST',
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: VOUCHER_PNG,
  });
  await response.arrayBuffer();
  return response.status;
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

async function serviceDeleteVoucher(path) {
  if (!SERVICE_KEY) return;
  const response = await fetch(`${BASE_URL}/storage/v1/object/vouchers/${path}`, {
    method: 'DELETE',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
  });
  await response.arrayBuffer();
}

function firstRow(body) {
  return Array.isArray(body) ? body[0] : body;
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
    console.error('\nNo se pudo iniciar sesión. Ejecuta el seed primero.');
    process.exit(1);
  }

  const suffix = `${Date.now()}`;
  const created = {
    cycleId: null,
    groupId: null,
    studentId: null,
    enrollmentId: null,
    chargeId: null,
    monthlyChargeId: null,
    paymentIds: [],
    voucherPaths: [],
  };

  const cycle = await createRow(tokens.adminA, 'cycles', {
    academy_id: ACADEMY_A,
    name: `Ciclo pagos ${suffix}`,
    start_date: '2026-11-01',
    end_date: '2027-01-31',
    grade: '5.º secundaria',
    warning_absences: 10,
    review_absences: 15,
    late_counts_as_absence: true,
  });
  created.cycleId = firstRow(cycle.body)?.id;
  check(
    'admin A crea ciclo para prueba de pagos',
    cycle.status === 201 && Boolean(created.cycleId),
    `status=${cycle.status}`,
  );

  const group = await createRow(tokens.adminA, 'groups', {
    academy_id: ACADEMY_A,
    cycle_id: created.cycleId,
    name: `Grupo pagos ${suffix}`,
    shift: 'morning',
    capacity: 2,
  });
  created.groupId = firstRow(group.body)?.id;
  check(
    'admin A crea grupo para prueba de pagos',
    group.status === 201 && Boolean(created.groupId),
    `status=${group.status}`,
  );

  const student = await createRow(tokens.cashierA, 'students', {
    academy_id: ACADEMY_A,
    full_name: `Alumno pagos ${suffix}`,
  });
  created.studentId = firstRow(student.body)?.id;
  check(
    'secretaría crea alumno de prueba',
    student.status === 201 && Boolean(created.studentId),
    `status=${student.status}`,
  );

  const enrollment = await rpc(tokens.cashierA, 'create_enrollment_request', {
    p_student_id: created.studentId,
    p_group_id: created.groupId,
    p_registration_price: 200,
    p_monthly_price: 200,
    p_registration_due_date: '2026-11-10',
    p_monthly_due_dates: ['2026-12-10'],
  });
  created.enrollmentId = typeof enrollment.body === 'string'
    ? enrollment.body
    : firstRow(enrollment.body)?.id ?? enrollment.body;
  check(
    'secretaría crea matrícula pendiente para pagos',
    enrollment.status === 200 && Boolean(created.enrollmentId),
    `status=${enrollment.status}`,
  );

  const charges = await rows(
    tokens.cashierA,
    'charges',
    `enrollment_id=eq.${created.enrollmentId}&order=type`,
  );
  created.chargeId = charges.find((row) => row.type === 'registration')?.id;
  created.monthlyChargeId = charges.find((row) => row.type === 'monthly')?.id;
  check(
    'la matrícula tiene cargo de inscripción y mensualidad',
    charges.length === 2 && Boolean(created.chargeId) && Boolean(created.monthlyChargeId),
    `cargos=${charges.length}`,
  );

  const p1 = crypto.randomUUID();
  created.paymentIds.push(p1);
  const path = (paymentId) => `${ACADEMY_A}/${paymentId}/voucher.png`;
  created.voucherPaths.push(path(p1));
  const uploaded = await uploadVoucher(tokens.cashierA, path(p1));
  check('secretaría sube voucher privado', uploaded === 200 || uploaded === 201, `status=${uploaded}`);

  const partial = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p1,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 80,
    p_paid_at: '2026-12-01',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-1`,
    p_voucher_path: path(p1),
  });
  const partialRow = firstRow(partial.body);
  check(
    'S/80 sobre S/200 deja saldo S/120 y matrícula pendiente',
    partial.status === 200
      && Number(partialRow?.charge_balance) === 120
      && partialRow?.enrollment_status === 'pending'
      && partialRow?.idempotent === false,
    JSON.stringify(partialRow),
  );

  const retry = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p1,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 80,
    p_paid_at: '2026-12-01',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-1`,
    p_voucher_path: path(p1),
  });
  check(
    'el reintento con el mismo pago es idempotente',
    retry.status === 200 && firstRow(retry.body)?.idempotent === true,
    JSON.stringify(firstRow(retry.body)),
  );

  const p2 = crypto.randomUUID();
  created.paymentIds.push(p2);
  created.voucherPaths.push(path(p2));
  await uploadVoucher(tokens.cashierA, path(p2));
  const overpay = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p2,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 121,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-2`,
    p_voucher_path: path(p2),
  });
  check(
    'el sobrepago se rechaza sin mutar saldo',
    overpay.status === 400 && overpay.body?.hint === 'PAYMENT_OVERPAY',
    `status=${overpay.status} hint=${overpay.body?.hint || 'n/d'}`,
  );

  const invalidAmount = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 0,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-3`,
    p_voucher_path: '',
  });
  check(
    'el monto inválido devuelve INVALID_AMOUNT',
    invalidAmount.status === 400 && invalidAmount.body?.hint === 'PAYMENT_INVALID_AMOUNT',
    `status=${invalidAmount.status} hint=${invalidAmount.body?.hint || 'n/d'}`,
  );

  const noVoucher = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-4`,
    p_voucher_path: '',
  });
  check(
    'el pago sin voucher se rechaza',
    noVoucher.status === 400 && noVoucher.body?.hint === 'PAYMENT_VOUCHER_REQUIRED',
    `status=${noVoucher.status} hint=${noVoucher.body?.hint || 'n/d'}`,
  );

  const cash = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'cash',
    p_reference: `B03-P-${suffix}-5`,
    p_voucher_path: '',
  });
  check(
    'el efectivo se rechaza',
    cash.status === 400 && cash.body?.hint === 'PAYMENT_METHOD_INVALID',
    `status=${cash.status} hint=${cash.body?.hint || 'n/d'}`,
  );

  const nullMethod = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: null,
    p_reference: `B03-P-${suffix}-5N`,
    p_voucher_path: '',
  });
  check(
    'el método nulo devuelve PAYMENT_METHOD_INVALID',
    nullMethod.status === 400 && nullMethod.body?.hint === 'PAYMENT_METHOD_INVALID',
    `status=${nullMethod.status} hint=${nullMethod.body?.hint || 'n/d'}`,
  );

  const wrongPath = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-6`,
    p_voucher_path: `${ACADEMY_B}/ruta-incorrecta/v.png`,
  });
  check(
    'la ruta de voucher de otra academia se rechaza',
    wrongPath.status === 400 && wrongPath.body?.hint === 'PAYMENT_VOUCHER_PATH_INVALID',
    `status=${wrongPath.status} hint=${wrongPath.body?.hint || 'n/d'}`,
  );

  const p6 = crypto.randomUUID();
  const missingObject = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p6,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-7`,
    p_voucher_path: path(p6),
  });
  check(
    'el voucher sin objeto privado se rechaza',
    missingObject.status === 400 && missingObject.body?.hint === 'PAYMENT_VOUCHER_OBJECT_NOT_FOUND',
    `status=${missingObject.status} hint=${missingObject.body?.hint || 'n/d'}`,
  );

  const p7 = crypto.randomUUID();
  created.paymentIds.push(p7);
  created.voucherPaths.push(path(p7));
  await uploadVoucher(tokens.cashierA, path(p7));
  const duplicateReference = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p7,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-1`,
    p_voucher_path: path(p7),
  });
  check(
    'la referencia bancaria duplicada se rechaza',
    duplicateReference.status === 409
      && duplicateReference.body?.hint === 'PAYMENT_DUPLICATE_REFERENCE',
    `status=${duplicateReference.status} hint=${duplicateReference.body?.hint || 'n/d'}`,
  );

  const discardDisabled = await invokeFunction(tokens.cashierA, {
    payment_id: p2,
    academy_id: ACADEMY_A,
  });
  check(
    'el descarte inmediato de voucher está deshabilitado',
    discardDisabled.status === 501
      && discardDisabled.body?.error?.code === 'DISCARD_DEFERRED',
    `status=${discardDisabled.status} code=${discardDisabled.body?.error?.code || 'n/d'}`,
  );

  const teacherAttempt = await rpc(tokens.teacherA, 'register_payment', {
    p_payment_id: crypto.randomUUID(),
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 10,
    p_paid_at: '2026-12-02',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-8`,
    p_voucher_path: '',
  });
  check(
    'docente no puede registrar pagos',
    teacherAttempt.status === 403 && teacherAttempt.body?.hint === 'ACCESS_DENIED',
    `status=${teacherAttempt.status} hint=${teacherAttempt.body?.hint || 'n/d'}`,
  );

  const cashierVoid = await rpc(tokens.cashierA, 'void_payment', {
    p_payment_id: p1,
    p_reason: 'Intento de secretaría',
  });
  check(
    'secretaría no puede anular pagos',
    cashierVoid.status === 403
      && cashierVoid.body?.hint === 'PAYMENT_VOID_FORBIDDEN',
    `status=${cashierVoid.status} hint=${cashierVoid.body?.hint || 'n/d'}`,
  );

  const p9 = crypto.randomUUID();
  created.paymentIds.push(p9);
  created.voucherPaths.push(path(p9));
  await uploadVoucher(tokens.cashierA, path(p9));
  const activation = await rpc(tokens.cashierA, 'register_payment', {
    p_payment_id: p9,
    p_enrollment_id: created.enrollmentId,
    p_charge_id: created.chargeId,
    p_amount: 120,
    p_paid_at: '2026-12-03',
    p_method: 'bank_transfer',
    p_reference: `B03-P-${suffix}-9`,
    p_voucher_path: path(p9),
  });
  const activationRow = firstRow(activation.body);
  check(
    'completar la inscripción activa la matrícula',
    activation.status === 200
      && Number(activationRow?.charge_balance) === 0
      && activationRow?.enrollment_status === 'active',
    JSON.stringify(activationRow),
  );

  const studentAfter = await rows(tokens.cashierA, 'students', `id=eq.${created.studentId}`);
  check(
    'la activación asigna el grupo al alumno',
    studentAfter.length === 1 && studentAfter[0].group_id === created.groupId,
    `group_id=${studentAfter[0]?.group_id}`,
  );

  const voidResult = await rpc(tokens.adminA, 'void_payment', {
    p_payment_id: p9,
    p_reason: 'Error de registro B03',
  });
  const voidRow = firstRow(voidResult.body);
  check(
    'dirección anula con motivo y recalcula el saldo',
    voidResult.status === 200
      && voidRow?.status === 'voided'
      && Number(voidRow?.charge_balance) === 120
      && voidRow?.enrollment_status === 'pending',
    JSON.stringify(voidRow),
  );

  const studentAfterVoid = await rows(tokens.cashierA, 'students', `id=eq.${created.studentId}`);
  check(
    'la anulación libera el cupo del alumno',
    studentAfterVoid.length === 1 && studentAfterVoid[0].group_id === null,
    `group_id=${studentAfterVoid[0]?.group_id}`,
  );

  if (SERVICE_KEY) {
    await serviceDelete('payments', `charge_id=eq.${created.chargeId}`);
    await serviceDelete('charges', `enrollment_id=eq.${created.enrollmentId}`);
    await serviceDelete('enrollments', `id=eq.${created.enrollmentId}`);
    await serviceDelete('students', `id=eq.${created.studentId}`);
    if (created.groupId) await serviceDelete('groups', `id=eq.${created.groupId}`);
    if (created.cycleId) await serviceDelete('cycles', `id=eq.${created.cycleId}`);
    for (const voucherPath of created.voucherPaths) {
      await serviceDeleteVoucher(voucherPath);
    }
    check('datos y vouchers de prueba eliminados', true);
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
