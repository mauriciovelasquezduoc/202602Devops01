import { http, HttpResponse } from 'msw'

export const ALUMNOS = [
  { id: 1, nombre: 'Juan', apellido: 'Pérez' },
  { id: 2, nombre: 'Ana', apellido: 'López' },
  { id: 3, nombre: 'Carlos', apellido: 'Soto' }
]

// Usar rutas relativas para que coincidan con la API del frontend
// El frontend usa axios.create({ baseURL: '/ep02' })
export const handlers = [
  http.get('/ep02', () => HttpResponse.json(ALUMNOS)),
  http.post('/ep02', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json({ id: 99, ...body }, { status: 200 })
  }),
  http.put('/ep02/:id', async ({ params, request }) => {
    const body = await request.json()
    return HttpResponse.json({ id: Number(params.id), ...body })
  }),
  http.delete('/ep02/:id', () => new HttpResponse(null, { status: 200 })),
  http.get(
    '/ep02/export',
    () =>
      new HttpResponse('Juan,Pérez\nAna,López', {
        headers: { 'Content-Type': 'text/plain' }
      })
  ),
  http.post('/ep02/import', () => new HttpResponse(null, { status: 200 }))
]
