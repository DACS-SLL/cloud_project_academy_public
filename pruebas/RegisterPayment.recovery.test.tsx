// @vitest-environment jsdom
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const api = vi.hoisted(() => ({
  findPayment: vi.fn(),
  registerPayment: vi.fn(),
  uploadVoucher: vi.fn(),
  listCharges: vi.fn(),
  listEnrollments: vi.fn(),
  listPayments: vi.fn(),
  listStudents: vi.fn(),
}))
vi.mock('../src/lib/api', () => api)
vi.mock('../src/lib/session', () => ({
  useSession: () => ({ access: { academy_id: 'ac1', academy_name: 'A', role: 'cashier' } }),
}))

import RegisterPayment from '../src/pages/RegisterPayment'

const ATTEMPT = {
  paymentId: '11111111-1111-4111-8111-111111111111',
  enrollmentId: 'en1',
  chargeId: 'ch1',
  amount: 150,
  paidAt: '2026-11-20',
  method: 'bank_transfer',
  reference: 'REF-1',
  voucherPath: 'ac1/11111111-1111-4111-8111-111111111111/file.png',
}
const KEY = 'f02.paymentAttempt'

beforeEach(() => {
  sessionStorage.clear()
  sessionStorage.setItem(KEY, JSON.stringify(ATTEMPT))
  window.location.hash = '#/pagos/registrar?student=s1'
  api.listStudents.mockResolvedValue([{ id: 's1', full_name: 'Ana Pérez', document_id: '12345678' }])
  api.listEnrollments.mockResolvedValue([{ id: 'en1', student_id: 's1', status: 'pending' }])
  api.listCharges.mockResolvedValue([{ id: 'ch1', enrollment_id: 'en1', student_id: 's1', type: 'registration', amount: 150, due_date: '2026-12-01' }])
  api.listPayments.mockResolvedValue([])
})
afterEach(() => { cleanup(); vi.clearAllMocks() })

describe('recuperación de pago tras perder conexión y recargar', () => {
  it('bloquea el envío mientras la consulta no responde y conserva el mismo p_payment_id', async () => {
    api.findPayment.mockRejectedValue({ message: 'Failed to fetch' }) // sin código ni hint → uncertain
    render(<RegisterPayment />)
    await screen.findByText(/Todavía no podemos confirmar/i)
    expect(api.findPayment).toHaveBeenCalledWith(ATTEMPT.paymentId)
    expect(screen.queryByRole('button', { name: /Confirmar pago/i })).toBeNull() // formulario bloqueado
    expect(JSON.parse(sessionStorage.getItem(KEY)!).paymentId).toBe(ATTEMPT.paymentId) // no se reemplazó
    expect(api.registerPayment).not.toHaveBeenCalled()
    expect(api.uploadVoucher).not.toHaveBeenCalled()
  })

  it('si el servidor no tiene el pago, el reintento reutiliza el mismo p_payment_id', async () => {
    api.findPayment.mockResolvedValue(null)
    api.registerPayment.mockResolvedValue({ payment_id: ATTEMPT.paymentId, status: 'confirmed', amount: 150, charge_balance: 0, enrollment_status: 'active', idempotent: false })
    render(<RegisterPayment />)
    await userEvent.click(await screen.findByRole('button', { name: /Reintentar/i }))
    await waitFor(() => expect(api.registerPayment).toHaveBeenCalledTimes(1))
    expect(api.registerPayment.mock.calls[0][0].paymentId).toBe(ATTEMPT.paymentId)
    expect(api.uploadVoucher).not.toHaveBeenCalled()
    await screen.findByText(/Pago confirmado/i)
    expect(sessionStorage.getItem(KEY)).toBeNull()
  })

  it('si el servidor ya tiene el pago, lo muestra como registrado sin volver a enviarlo', async () => {
    api.findPayment.mockResolvedValue({ id: ATTEMPT.paymentId, status: 'confirmed', amount: '150' })
    render(<RegisterPayment />)
    await screen.findByText(/Este pago ya quedó registrado/i)
    expect(api.registerPayment).not.toHaveBeenCalled()
    expect(sessionStorage.getItem(KEY)).toBeNull()
  })

  it('nunca ofrece descartar ni generar otro p_payment_id: "no encontrado" no lo permite', async () => {
    api.findPayment.mockResolvedValue(null)
    render(<RegisterPayment />)
    await screen.findByRole('button', { name: /Reintentar/i })
    expect(screen.queryByRole('button', { name: /Descartar/i })).toBeNull()
    expect(screen.queryByRole('button', { name: /Confirmar pago/i })).toBeNull()
    expect(JSON.parse(sessionStorage.getItem(KEY)!).paymentId).toBe(ATTEMPT.paymentId)
  })

  it('si el reintento tampoco responde, sigue el mismo p_payment_id y el formulario bloqueado', async () => {
    api.findPayment.mockResolvedValueOnce(null).mockRejectedValue({ message: 'Failed to fetch' })
    api.registerPayment.mockRejectedValue({ message: 'Failed to fetch' })
    render(<RegisterPayment />)
    await userEvent.click(await screen.findByRole('button', { name: /Reintentar/i }))
    await screen.findByText(/Todavía no podemos confirmar/i)
    expect(api.registerPayment.mock.calls[0][0].paymentId).toBe(ATTEMPT.paymentId)
    expect(JSON.parse(sessionStorage.getItem(KEY)!).paymentId).toBe(ATTEMPT.paymentId)
    expect(screen.queryByRole('button', { name: /Confirmar pago/i })).toBeNull()
  })
})
