import { http, HttpResponse } from 'msw'

export const ALUMNOS = [
  { id: 1, nombre: 'Juan',   apellido: 'Pérez'  },
  { id: 2, nombre: 'Ana',    apellido: 'López'  },
  { id: 3, nombre: 'Carlos', apellido: 'Soto'   },
]

// Usar rutas relativas para que coincidan con la API del frontend
// El frontend usa axios.create({ baseURL: '/ep03' })
export const handlers = [
  http.get('/ep03',           () => HttpResponse.json(ALUMNOS)),
  http.post('/ep03',          async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json({ id: 99, ...body }, { status: 200 })
  }),
  http.put('/ep03/:id',       async ({ params, request }) => {
    const body = await request.json()
    return HttpResponse.json({ id: Number(params.id), ...body })
  }),
  http.delete('/ep03/:id',    () => new HttpResponse(null, { status: 200 })),
  http.get('/ep03/export',    () =>
    new HttpResponse('Juan,Pérez\nAna,López', {
      headers: { 'Content-Type': 'text/plain' }
    })
  ),
  http.post('/ep03/import',   () => new HttpResponse(null, { status: 200 })),
]
