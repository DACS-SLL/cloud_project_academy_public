import { describe, expect, it, vi } from 'vitest'

// Servidor simulado: el caso de deuda ya se resolvió, así que `cycle_cases` no trae al alumno,
// pero el contacto sigue en `followups` y el alumno en `students`.
const tables: Record<string, unknown[]> = {
  followups: [
    { id: 'f1', student_id: 's1', cycle_id: 'c1', channel: 'call', note: 'Acordó pagar el viernes', created_by: 'u1', created_at: '2026-11-20T15:00:00Z' },
  ],
  students: [{ id: 's1', full_name: 'Alumno Ficticio Uno' }],
}

vi.mock('../src/lib/supabase', () => {
  const query = (table: string) => {
    const result = { data: tables[table], error: null }
    const chain = {
      select: () => chain,
      eq: () => chain,
      in: () => chain,
      order: () => chain,
      then: (ok: (v: typeof result) => unknown) => Promise.resolve(result).then(ok),
    }
    return chain
  }
  return { supabase: { from: query }, isSupabaseConfigured: true }
})

import { listFollowups } from '../src/lib/api'

describe('historial de contactos (B05)', () => {
  it('conserva el nombre del alumno aunque su caso ya no esté en cycle_cases', async () => {
    const list = await listFollowups('c1')
    expect(list).toHaveLength(1)
    expect(list[0].student_name).toBe('Alumno Ficticio Uno')
  })
})
