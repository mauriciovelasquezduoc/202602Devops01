import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeAll, afterEach, afterAll, describe, it, expect, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from './mocks/server'
import App from '../App'

global.URL.createObjectURL = vi.fn(() => 'blob:mock-url')
global.URL.revokeObjectURL = vi.fn()

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('App — renderizado inicial', () => {
  it('muestra el título principal', async () => {
    render(<App />)
    expect(screen.getByText(/Gestión de Alumnos/i)).toBeInTheDocument()
  })

  it('muestra el subtítulo con el stack tecnológico', () => {
    render(<App />)
    expect(screen.getByText(/Spring Boot/i)).toBeInTheDocument()
  })

  it('muestra el spinner mientras carga', () => {
    render(<App />)
    // El spinner es un div con clase .spinner dentro de .spinner-wrap
    expect(document.querySelector('.spinner')).toBeTruthy()
  })

  it('muestra los ep03 después de cargar', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getByText('Juan')).toBeInTheDocument())
    expect(screen.getByText('Ana')).toBeInTheDocument()
  })

  it('muestra el contador de ep03 en las stats', async () => {
    render(<App />)
    await waitFor(() => {
      const statNums = document.querySelectorAll('.stat-num')
      expect(statNums[0]?.textContent).toBe('3')
    })
  })

  it('muestra el formulario de nuevo alumno', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getByText(/Nuevo alumno/i)).toBeInTheDocument())
  })

  it('muestra el panel CSV', async () => {
    render(<App />)
    await waitFor(() =>
      expect(screen.getByText(/Importar \/ Exportar CSV/i)).toBeInTheDocument()
    )
  })
})

describe('App — alertas', () => {
  it('muestra alerta de error si la carga falla', async () => {
    server.use(http.get('/ep03', () => HttpResponse.error()))
    render(<App />)
    await waitFor(() =>
      expect(screen.getByText((content) => content.includes('Error al cargar'))).toBeInTheDocument(),
      { timeout: 3000 }
    )
  })
})

describe('App — flujo de creación', () => {
  it('crea un alumno y muestra mensaje de éxito', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getByLabelText(/nombre/i)).toBeInTheDocument())

    await userEvent.type(screen.getByLabelText(/nombre/i), 'Pedro')
    await userEvent.type(screen.getByLabelText(/apellido/i), 'Soto')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))

    await waitFor(() =>
      expect(screen.getByText(/creado correctamente/i)).toBeInTheDocument()
    )
  })
})

describe('App — flujo de edición', () => {
  it('activa el modo edición al hacer click en Editar', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getAllByTitle('Editar').length).toBeGreaterThan(0))

    fireEvent.click(screen.getAllByTitle('Editar')[0])
    await waitFor(() =>
      expect(screen.getByText(/Editar alumno/i)).toBeInTheDocument()
    )
  })

  it('cancela la edición al hacer click en Cancelar', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getAllByTitle('Editar').length).toBeGreaterThan(0))

    fireEvent.click(screen.getAllByTitle('Editar')[0])
    await waitFor(() => expect(screen.getByText(/cancelar/i)).toBeInTheDocument())

    await userEvent.click(screen.getByText(/cancelar/i))
    await waitFor(() =>
      expect(screen.getByText(/Nuevo alumno/i)).toBeInTheDocument()
    )
  })

  it('guarda la edición y vuelve al modo creación', async () => {
    render(<App />)
    await waitFor(() => expect(screen.getAllByTitle('Editar').length).toBeGreaterThan(0))

    fireEvent.click(screen.getAllByTitle('Editar')[0])
    await waitFor(() => expect(screen.getByText(/Editar alumno/i)).toBeInTheDocument())

    fireEvent.submit(screen.getByRole('button', { name: /guardar/i }).closest('form'))
    await waitFor(() =>
      expect(screen.getByText(/actualizado correctamente/i)).toBeInTheDocument()
    )
  })
})

describe('App — flujo de eliminación', () => {
  it('elimina un alumno al confirmar', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    render(<App />)
    await waitFor(() => expect(screen.getAllByTitle('Eliminar').length).toBeGreaterThan(0))

    fireEvent.click(screen.getAllByTitle('Eliminar')[0])
    await waitFor(() =>
      expect(screen.getByText(/eliminado/i)).toBeInTheDocument()
    )
    vi.restoreAllMocks()
  })
})
