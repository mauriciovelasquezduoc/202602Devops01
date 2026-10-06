import { renderHook, act, waitFor } from '@testing-library/react'
import { beforeAll, afterEach, afterAll, describe, it, expect, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '../setup'
import { useAlumnos } from '../../hooks/useAlumnos'

global.URL.createObjectURL = vi.fn(() => 'blob:mock-url')
global.URL.revokeObjectURL = vi.fn()

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('useAlumnos — carga inicial', () => {
  it('inicia con loading=true y luego carga los ep03', async () => {
    const { result } = renderHook(() => useAlumnos())
    expect(result.current.loading).toBe(true)
    await waitFor(() => expect(result.current.loading).toBe(false))
    expect(result.current.ep03).toHaveLength(3)
  })

  it('muestra error si la carga falla', async () => {
    server.use(http.get('/ep03', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.error).toBeTruthy(), { timeout: 3000 })
    expect(result.current.error).toMatch(/Error al cargar/i)
  })
})

describe('useAlumnos — crear', () => {
  it('retorna true y muestra mensaje de éxito al crear', async () => {
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.crear({ nombre: 'Pedro', apellido: 'Soto' })
    })
    expect(ok).toBe(true)
    await waitFor(() => expect(result.current.success).toMatch(/creado/i))
  })

  it('retorna false y muestra error si crear falla', async () => {
    server.use(http.post('/ep03', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.crear({ nombre: 'X', apellido: 'Y' })
    })
    expect(ok).toBe(false)
    await waitFor(() => expect(result.current.error).toMatch(/Error al crear/i))
  })
})

describe('useAlumnos — actualizar', () => {
  it('retorna true y muestra mensaje de éxito al actualizar', async () => {
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.actualizar(1, { nombre: 'Juan', apellido: 'Nuevo' })
    })
    expect(ok).toBe(true)
    await waitFor(() => expect(result.current.success).toMatch(/actualizado/i))
  })

  it('retorna false y muestra error si actualizar falla', async () => {
    server.use(http.put('/ep03/:id', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.actualizar(1, { nombre: 'X', apellido: 'Y' })
    })
    expect(ok).toBe(false)
    await waitFor(() => expect(result.current.error).toMatch(/Error al actualizar/i))
  })
})

describe('useAlumnos — eliminar', () => {
  it('muestra mensaje de éxito al eliminar', async () => {
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    await act(async () => { await result.current.eliminar(1) })
    await waitFor(() => expect(result.current.success).toMatch(/eliminado/i))
  })

  it('muestra error si eliminar falla', async () => {
    server.use(http.delete('/ep03/:id', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    await act(async () => { await result.current.eliminar(1) })
    await waitFor(() => expect(result.current.error).toMatch(/Error al eliminar/i))
  })
})

describe('useAlumnos — exportar', () => {
  it('crea y descarga el archivo CSV', async () => {
    const originalCreateElement = document.createElement.bind(document)
    const clickMock = vi.fn()
    const mockAnchor = { href: '', download: '', click: clickMock }
    vi.spyOn(document, 'createElement').mockImplementation((tag) => {
      if (tag === 'a') return mockAnchor
      return originalCreateElement(tag)
    })
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    await act(async () => { await result.current.exportar() })
    expect(clickMock).toHaveBeenCalled()
    await waitFor(() => expect(result.current.success).toMatch(/exportado/i))
    vi.restoreAllMocks()
  })

  it('muestra error si exportar falla', async () => {
    server.use(http.get('/ep03/export', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    await act(async () => { await result.current.exportar() })
    await waitFor(() => expect(result.current.error).toMatch(/Error al exportar/i))
  })
})

describe('useAlumnos — importar', () => {
  it('retorna true y muestra éxito al importar', async () => {
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.importar('Juan,Pérez\nAna,López')
    })
    expect(ok).toBe(true)
    await waitFor(() => expect(result.current.success).toMatch(/importado/i))
  })

  it('retorna false y muestra error si importar falla', async () => {
    server.use(http.post('/ep03/import', () => HttpResponse.error()))
    const { result } = renderHook(() => useAlumnos())
    await waitFor(() => expect(result.current.loading).toBe(false))
    let ok
    await act(async () => {
      ok = await result.current.importar('Juan,Pérez')
    })
    expect(ok).toBe(false)
    await waitFor(() => expect(result.current.error).toMatch(/Error al importar/i))
  })
})
