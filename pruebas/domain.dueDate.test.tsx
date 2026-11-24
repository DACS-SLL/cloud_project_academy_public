import { describe, expect, it } from 'vitest'
import { chargeView, effectiveDueDate } from '../src/lib/domain'
import type { Charge } from '../src/lib/types'

const reg = { id: 'c1', type: 'registration', amount: 100, due_date: '2026-11-01' } as unknown as Charge
const monthly = { id: 'c2', type: 'monthly', amount: 100, due_date: '2026-11-01' } as unknown as Charge
const exception = { status: 'exception' as const, exception_due_date: '2026-12-15' }

describe('vencimiento efectivo (B05)', () => {
  it('la inscripción excepcional usa exception_due_date', () => {
    expect(effectiveDueDate(reg, exception)).toBe('2026-12-15')
  })
  it('la mensualidad conserva su fecha aunque la matrícula sea excepcional', () => {
    expect(effectiveDueDate(monthly, exception)).toBe('2026-11-01')
  })
  it('una matrícula no excepcional usa la fecha del cargo', () => {
    expect(effectiveDueDate(reg, { status: 'active', exception_due_date: null })).toBe('2026-11-01')
  })
  it('con fecha excepcional futura no se muestra vencida; sin ella, sí', () => {
    const today = '2026-11-23'
    expect(chargeView(reg, [], today, effectiveDueDate(reg, exception)).state).toBe('pending')
    expect(chargeView(reg, [], today).state).toBe('overdue')
  })
  it('un pago parcial deja el saldo y estado parcial', () => {
    const p = [{ charge_id: 'c1', status: 'confirmed', amount: 40 }] as never
    const v = chargeView(reg, p, '2026-11-23', '2026-12-15')
    expect([v.paid, v.balance, v.state]).toEqual([40, 60, 'partial'])
  })
})
