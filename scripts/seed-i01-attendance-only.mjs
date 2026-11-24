#!/usr/bin/env node
// I01: completa únicamente asistencia histórica de los alumnos ficticios de Academia Norte.
// Uso: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed-i01-attendance-only.mjs [--dry-run]

const BASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const DRY_RUN = process.argv.slice(2).includes('--dry-run');
if (process.argv.slice(2).some((arg) => arg !== '--dry-run')) {
  throw new Error('Argumento no reconocido. Uso: node scripts/seed-i01-attendance-only.mjs [--dry-run]');
}
if (!BASE_URL || !SERVICE_KEY) {
  throw new Error('Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY en el entorno del servidor.');
}

const ACADEMY = 'a1111111-1111-4111-8111-111111111111';
const CYCLE = 'a1111111-1111-4111-8111-0000000000c0';
const GROUP = 'a1111111-1111-4111-8111-0000000000a1';
const SUBJECT = 'a1111111-1111-4111-8111-0000000000a2';
const ASSIGNMENT = 'a1111111-1111-4111-8111-0000000000ad';
const A1 = 'a1111111-1111-4111-8111-0000000000a3';
const A2 = 'a1111111-1111-4111-8111-0000000000a4';
const TARGETS = new Map([[A1, 9], [A2, 14]]);

function headers(extra = {}) {
  return { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', ...extra };
}

async function request(path, { method = 'GET', body, extraHeaders } = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: headers(extraHeaders),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${method} ${path} respondió ${response.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

const eq = (value) => `eq.${encodeURIComponent(value)}`;
const inList = (values) => `in.(${values.map(encodeURIComponent).join(',')})`;
async function rows(table, query) {
  const result = [];
  const pageSize = 1000;
  for (let offset = 0; ; offset += pageSize) {
    const page = await request(`/rest/v1/${table}?${query}`, {
      extraHeaders: { Range: `${offset}-${offset + pageSize - 1}` },
    });
    result.push(...page);
    if (page.length < pageSize) return result;
  }
}
function requireOne(label, data, test) {
  if (data.length !== 1 || !test(data[0])) throw new Error(`Validación fallida: ${label}; se esperaba exactamente un registro con los datos de Academia Norte.`);
  return data[0];
}
function assertMatches(label, actual, expected) {
  for (const [key, value] of Object.entries(expected)) {
    if (actual[key] !== value) throw new Error(`Conflicto en ${label} (${key}): existe un dato distinto para el UUID esperado.`);
  }
}

async function main() {
  requireOne('academia', await rows('academies', `select=id,name&id=${eq(ACADEMY)}`),
    (r) => r.id === ACADEMY && r.name === 'Academia Demo Norte');
  const cycle = requireOne('ciclo', await rows('cycles', `select=id,academy_id,name,late_counts_as_absence&id=${eq(CYCLE)}`),
    (r) => r.id === CYCLE && r.academy_id === ACADEMY && r.name === 'Ciclo Demo 2026');
  requireOne('grupo', await rows('groups', `select=id,academy_id,cycle_id,name&id=${eq(GROUP)}`),
    (r) => r.id === GROUP && r.academy_id === ACADEMY && r.cycle_id === CYCLE && r.name === '5.º B mañana');
  requireOne('materia', await rows('subjects', `select=id,academy_id,name&id=${eq(SUBJECT)}`),
    (r) => r.id === SUBJECT && r.academy_id === ACADEMY && r.name === 'Matemática');

  const assignment = requireOne('asignación docente', await rows('teacher_assignments', `select=id,academy_id,teacher_id,group_id,subject_id&id=${eq(ASSIGNMENT)}`),
    (r) => r.id === ASSIGNMENT && r.academy_id === ACADEMY && r.group_id === GROUP && r.subject_id === SUBJECT);
  const teacherMemberships = await rows('memberships', `select=user_id,academy_id,role&user_id=${eq(assignment.teacher_id)}&academy_id=${eq(ACADEMY)}`);
  requireOne('docente de Academia Norte', teacherMemberships,
    (r) => r.user_id === assignment.teacher_id && r.academy_id === ACADEMY && r.role === 'teacher');

  const students = await rows('students', `select=id,academy_id,group_id,full_name&id=${inList([...TARGETS.keys()])}`);
  if (students.length !== 2) throw new Error('Validación fallida: deben existir únicamente los alumnos ficticios A1 y A2 de Academia Norte.');
  for (const id of TARGETS.keys()) {
    const student = students.find((r) => r.id === id);
    const expectedName = id === A1 ? 'Alumno Ficticio A1' : 'Alumno Ficticio A2';
    if (!student || student.academy_id !== ACADEMY || student.group_id !== GROUP || student.full_name !== expectedName) {
      throw new Error(`Validación fallida: el alumno ${id} no coincide con el registro ficticio esperado de Academia Norte.`);
    }
  }

  const enrollments = await rows('enrollments', `select=student_id,academy_id,cycle_id,status&academy_id=${eq(ACADEMY)}&cycle_id=${eq(CYCLE)}&student_id=${inList([...TARGETS.keys()])}`);
  for (const studentId of TARGETS.keys()) {
    const active = enrollments.filter((e) => e.student_id === studentId
      && e.academy_id === ACADEMY && e.cycle_id === CYCLE
      && (e.status === 'active' || e.status === 'exception'));
    if (active.length !== 1) throw new Error(`Validación fallida: ${studentId} debe tener exactamente una matrícula activa o excepcional en el ciclo.`);
  }

  const cycleGroups = await rows('groups', `select=id,academy_id,cycle_id&academy_id=${eq(ACADEMY)}&cycle_id=${eq(CYCLE)}`);
  if (!cycleGroups.some((g) => g.id === GROUP)) throw new Error('El grupo no pertenece al ciclo de Academia Norte esperado.');
  const cycleGroupIds = cycleGroups.map((g) => g.id);

  // El mismo conjunto de sesiones se usa para ambos alumnos: 2 al 14 de noviembre de 2026.
  const candidateSessions = Array.from({ length: 13 }, (_, index) => ({
    id: `a1111111-1111-4111-8111-${(0xe0 + index).toString(16).padStart(12, '0')}`,
    academy_id: ACADEMY,
    group_id: GROUP,
    subject_id: SUBJECT,
    teacher_id: assignment.teacher_id,
    starts_at: `2026-11-${String(index + 2).padStart(2, '0')}T13:00:00Z`,
  }));

  const groupSessions = await rows('class_sessions', `select=id,academy_id,group_id,subject_id,teacher_id,starts_at&academy_id=${eq(ACADEMY)}&group_id=${inList(cycleGroupIds)}`);
  const fixedGroupSessions = groupSessions.filter((s) => s.group_id === GROUP);
  const sessionsByUniqueKey = new Map();
  for (const session of fixedGroupSessions.filter((s) => s.subject_id === SUBJECT)) {
    const key = session.starts_at;
    if (sessionsByUniqueKey.has(key)) throw new Error(`Hay sesiones duplicadas para grupo, materia y fecha ${key}; se aborta sin modificar datos.`);
    sessionsByUniqueKey.set(key, session);
  }
  for (const desired of candidateSessions) {
    const existingId = await rows('class_sessions', `select=id,academy_id,group_id,subject_id,teacher_id,starts_at&id=${eq(desired.id)}`);
    if (existingId.length > 1) throw new Error(`Conflicto: UUID de sesión repetido ${desired.id}.`);
    if (existingId.length === 1) assertMatches(`sesión ${desired.id}`, existingId[0], desired);
    const sameTime = sessionsByUniqueKey.get(desired.starts_at);
    if (sameTime && (sameTime.id !== desired.id || sameTime.teacher_id !== assignment.teacher_id)) {
      throw new Error(`Conflicto de sesión existente para ${desired.starts_at}; no se insertará ni alterará.`);
    }
  }

  const studentFilter = inList([...TARGETS.keys()]);
  const attendances = await rows('attendance', `select=id,academy_id,session_id,student_id,status&academy_id=${eq(ACADEMY)}&student_id=${studentFilter}`);
  const historySessionIds = new Set(groupSessions
    .filter((s) => s.academy_id === ACADEMY && cycleGroupIds.includes(s.group_id))
    .map((s) => s.id));
  const absences = new Map([...TARGETS.keys()].map((id) => [id, 0]));
  for (const attendance of attendances) {
    if (historySessionIds.has(attendance.session_id)
      && (attendance.status === 'absent' || (cycle.late_counts_as_absence && attendance.status === 'late'))) {
      absences.set(attendance.student_id, absences.get(attendance.student_id) + 1);
    }
  }
  for (const [studentId, target] of TARGETS) {
    if (absences.get(studentId) > target) throw new Error(`Conteo incompatible: el alumno ${studentId} ya tiene ${absences.get(studentId)} faltas; el objetivo es ${target}.`);
  }

  const allKnownSessions = new Map(fixedGroupSessions.map((s) => [s.id, s]));
  const toInsertSessions = [];
  for (const session of candidateSessions) {
    if (!allKnownSessions.has(session.id)) {
      const collisionById = await rows('class_sessions', `select=id&id=${eq(session.id)}`);
      if (collisionById.length) throw new Error(`Conflicto de UUID: ${session.id} ya está usado por una sesión no compatible.`);
      toInsertSessions.push(session);
      allKnownSessions.set(session.id, session);
    }
  }

  const attendanceByPair = new Map(attendances.map((a) => [`${a.session_id}:${a.student_id}`, a]));
  const toInsertAttendance = [];
  const usedAttendanceIds = new Set();
  for (const [studentId, target] of TARGETS) {
    let remaining = target - absences.get(studentId);
    for (let index = 0; index < candidateSessions.length && remaining > 0; index += 1) {
      const session = candidateSessions[index];
      const pairKey = `${session.id}:${studentId}`;
      const existing = attendanceByPair.get(pairKey);
      // Nunca se reemplaza una marca existente; si no cuenta como falta, se busca otra sesión.
      if (existing) continue;
      const suffix = studentId === A2 ? 0xf0 + index : 0x100 + index;
      const attendance = {
        id: `a1111111-1111-4111-8111-${suffix.toString(16).padStart(12, '0')}`,
        academy_id: ACADEMY,
        session_id: session.id,
        student_id: studentId,
        status: 'absent',
      };
      if (usedAttendanceIds.has(attendance.id)) throw new Error(`Conflicto interno de UUID de asistencia: ${attendance.id}.`);
      usedAttendanceIds.add(attendance.id);
      const idCollision = await rows('attendance', `select=id&id=${eq(attendance.id)}`);
      if (idCollision.length) throw new Error(`Conflicto de UUID: ${attendance.id} ya está usado por otra asistencia.`);
      toInsertAttendance.push(attendance);
      remaining -= 1;
    }
    if (remaining > 0) throw new Error(`No hay suficientes sesiones históricas disponibles para alcanzar ${target} faltas en ${studentId}.`);
  }

  const neededSessionIds = new Set(toInsertAttendance.map((a) => a.session_id));
  const sessionsToWrite = toInsertSessions.filter((session) => neededSessionIds.has(session.id));

  console.log(`Faltas actuales en sesiones de ${GROUP}: A1=${absences.get(A1)}, A2=${absences.get(A2)}.`);
  console.log(`Plan: ${sessionsToWrite.length} sesiones y ${toInsertAttendance.length} asistencias nuevas.`);
  if (DRY_RUN) {
    console.log('DRY RUN: no se escribió ningún dato.');
    console.table(sessionsToWrite.map(({ id, starts_at }) => ({ tipo: 'sesión', id, starts_at })));
    console.table(toInsertAttendance.map(({ id, session_id, student_id }) => ({ tipo: 'falta', id, session_id, student_id })));
    return;
  }

  if (sessionsToWrite.length) {
    await request('/rest/v1/class_sessions', {
      method: 'POST', body: sessionsToWrite,
      extraHeaders: { Prefer: 'return=minimal' },
    });
  }
  if (toInsertAttendance.length) {
    await request('/rest/v1/attendance', {
      method: 'POST', body: toInsertAttendance,
      extraHeaders: { Prefer: 'return=minimal' },
    });
  }

  // Verificación posterior con lecturas reales: sesiones y asistencias confirmadas desde PostgREST.
  const allGroupSessions = await rows('class_sessions', `select=id,academy_id,group_id&academy_id=${eq(ACADEMY)}&group_id=${inList(cycleGroupIds)}`);
  const finalSessionIds = new Set(allGroupSessions
    .filter((s) => s.academy_id === ACADEMY && cycleGroupIds.includes(s.group_id))
    .map((s) => s.id));
  const requiredSessionIds = [...new Set([...candidateSessions
    .filter((s) => fixedGroupSessions.some((current) => current.id === s.id))
    .map((s) => s.id), ...neededSessionIds])];
  const finalCandidateSessions = requiredSessionIds.length
    ? await rows('class_sessions', `select=id,academy_id,group_id,subject_id&id=${inList(requiredSessionIds)}`)
    : [];
  const candidateIds = new Set(finalCandidateSessions
    .filter((s) => s.academy_id === ACADEMY && s.group_id === GROUP && s.subject_id === SUBJECT)
    .map((s) => s.id));
  if (candidateIds.size !== requiredSessionIds.length) throw new Error('Verificación posterior fallida: faltan sesiones históricas necesarias.');
  const finalAttendance = await rows('attendance', `select=id,academy_id,session_id,student_id,status&academy_id=${eq(ACADEMY)}&student_id=${studentFilter}`);
  const finalCounts = new Map([...TARGETS.keys()].map((id) => [id, 0]));
  for (const a of finalAttendance) {
    if (finalSessionIds.has(a.session_id)
      && (a.status === 'absent' || (cycle.late_counts_as_absence && a.status === 'late'))) {
      finalCounts.set(a.student_id, finalCounts.get(a.student_id) + 1);
    }
  }
  for (const [studentId, target] of TARGETS) {
    if (finalCounts.get(studentId) !== target) {
      throw new Error(`Verificación posterior fallida: ${studentId} tiene ${finalCounts.get(studentId)} faltas; se esperaban ${target}.`);
    }
  }
  console.log(`Verificación final confirmada por PostgREST: A1=${finalCounts.get(A1)}, A2=${finalCounts.get(A2)} faltas.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
