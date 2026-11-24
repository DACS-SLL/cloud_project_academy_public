const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve((request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return json(405, { error: { code: 'METHOD_NOT_ALLOWED', message: 'Usa POST' } })
  }

  // P0: el descarte inmediato abre una ventana entre comprobar el pago y
  // borrar el objeto. Se deshabilita hasta implementar una limpieza
  // transaccional/administrativa que no compita con register_payment.
  return json(501, {
    error: {
      code: 'DISCARD_DEFERRED',
      message: 'Descarte inmediato deshabilitado en P0; el voucher queda para limpieza administrativa',
    },
  })
})
