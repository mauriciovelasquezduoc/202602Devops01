import { beforeAll, afterEach, afterAll, describe, it, expect } from 'vitest'
import { server } from '../mocks/server'
import {
  getAlumnos, createAlumno, updateAlumno,
  deleteAlumno, exportCSV, importCSV
} from '../../api/alumnos'

beforeAll(() => server.listen({ onUnhandledRequest: 'warn' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('API — ep03.js', () => {
  it('getAlumnos retorna la lista de ep03', async () => {
    const { data } = await getAlumnos()
    expect(data).toHaveLength(3)
    expect(data[0]).toMatchObject({ id: 1, nombre: 'Juan', apellido: 'Pérez' })
  })

  it('createAlumno envía POST y retorna el alumno creado', async () => {
    const { data } = await createAlumno({ nombre: 'Pedro', apellido: 'Soto' })
    expect(data).toMatchObject({ id: 99, nombre: 'Pedro', apellido: 'Soto' })
  })

  it('updateAlumno envía PUT con el id correcto', async () => {
    const { data } = await updateAlumno(1, { nombre: 'Juan', apellido: 'Nuevo' })
    expect(data).toMatchObject({ id: 1, nombre: 'Juan', apellido: 'Nuevo' })
  })

  it('deleteAlumno envía DELETE y retorna 200', async () => {
    const res = await deleteAlumno(1)
    expect(res.status).toBe(200)
  })

  it('exportCSV retorna texto CSV', async () => {
    const { data } = await exportCSV()
    expect(data).toContain('Juan,Pérez')
  })

  it('importCSV envía POST con texto plano', async () => {
    const res = await importCSV('Juan,Pérez\nAna,López')
    expect(res.status).toBe(200)
  })
})
