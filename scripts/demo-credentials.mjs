// Contraseñas de prueba en memoria; ningún valor se incluye en errores o logs.
const fallback = process.env.Q01_DEMO_PASSWORD || '';
let passwords = {};
if (process.env.Q01_DEMO_PASSWORDS_JSON) {
  try { passwords = JSON.parse(process.env.Q01_DEMO_PASSWORDS_JSON); }
  catch { throw new Error('Q01_DEMO_PASSWORDS_JSON no es un objeto JSON válido.'); }
  if (!passwords || typeof passwords !== 'object' || Array.isArray(passwords)
      || Object.values(passwords).some(value => typeof value !== 'string' || !value)) {
    throw new Error('Q01_DEMO_PASSWORDS_JSON debe mapear correos a contraseñas no vacías.');
  }
}
if (!fallback && !Object.keys(passwords).length) {
  throw new Error('Falta Q01_DEMO_PASSWORD o Q01_DEMO_PASSWORDS_JSON para las cuentas de prueba.');
}
export function demoPasswordFor(email) {
  const password = Object.hasOwn(passwords, email) ? passwords[email] : fallback;
  if (!password) throw new Error(`Falta contraseña de prueba para ${email}.`);
  return password;
}
