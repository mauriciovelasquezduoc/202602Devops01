import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import AlumnoForm from '../../components/AlumnoForm'

const onSubmit = vi.fn()
const onCancel = vi.fn()

beforeEach(() => {
  onSubmit.mockReset()
  onCancel.mockReset()
})

describe('AlumnoForm — modo creación (editing=null)', () => {
  it('muestra el título "Nuevo alumno"', () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.getByText(/Nuevo alumno/i)).toBeInTheDocument()
  })

  it('muestra los campos nombre y apellido vacíos', () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.getByLabelText(/nombre/i)).toHaveValue('')
    expect(screen.getByLabelText(/apellido/i)).toHaveValue('')
  })

  it('no muestra el botón Cancelar en modo creación', () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.queryByText(/cancelar/i)).not.toBeInTheDocument()
  })

  it('actualiza el campo nombre al escribir', async () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    const input = screen.getByLabelText(/nombre/i)
    await userEvent.type(input, 'Juan')
    expect(input).toHaveValue('Juan')
  })

  it('actualiza el campo apellido al escribir', async () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    const input = screen.getByLabelText(/apellido/i)
    await userEvent.type(input, 'Pérez')
    expect(input).toHaveValue('Pérez')
  })

  it('llama onSubmit con los datos correctos al enviar', async () => {
    onSubmit.mockResolvedValue(true)
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.type(screen.getByLabelText(/nombre/i), 'Juan')
    await userEvent.type(screen.getByLabelText(/apellido/i), 'Pérez')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))
    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith({ nombre: 'Juan', apellido: 'Pérez' })
    })
  })

  it('limpia el formulario después de un submit exitoso', async () => {
    onSubmit.mockResolvedValue(true)
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.type(screen.getByLabelText(/nombre/i), 'Juan')
    await userEvent.type(screen.getByLabelText(/apellido/i), 'Pérez')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))
    await waitFor(() => {
      expect(screen.getByLabelText(/nombre/i)).toHaveValue('')
      expect(screen.getByLabelText(/apellido/i)).toHaveValue('')
    })
  })

  it('NO llama onSubmit si nombre está vacío', async () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.type(screen.getByLabelText(/apellido/i), 'Pérez')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('NO llama onSubmit si apellido está vacío', async () => {
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.type(screen.getByLabelText(/nombre/i), 'Juan')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('NO limpia el formulario si onSubmit retorna false', async () => {
    onSubmit.mockResolvedValue(false)
    render(<AlumnoForm editing={null} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.type(screen.getByLabelText(/nombre/i), 'Juan')
    await userEvent.type(screen.getByLabelText(/apellido/i), 'Pérez')
    fireEvent.submit(screen.getByRole('button', { name: /agregar/i }).closest('form'))
    await waitFor(() => {
      expect(screen.getByLabelText(/nombre/i)).toHaveValue('Juan')
    })
  })
})

describe('AlumnoForm — modo edición (editing != null)', () => {
  const alumno = { id: 1, nombre: 'Ana', apellido: 'López' }

  it('muestra el título "Editar alumno"', () => {
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.getByText(/Editar alumno/i)).toBeInTheDocument()
  })

  it('precarga los campos con los datos del alumno', () => {
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.getByLabelText(/nombre/i)).toHaveValue('Ana')
    expect(screen.getByLabelText(/apellido/i)).toHaveValue('López')
  })

  it('muestra el botón Cancelar en modo edición', () => {
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    expect(screen.getByText(/cancelar/i)).toBeInTheDocument()
  })

  it('llama onCancel al hacer click en Cancelar', async () => {
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    await userEvent.click(screen.getByText(/cancelar/i))
    expect(onCancel).toHaveBeenCalledTimes(1)
  })

  it('llama onSubmit con los datos actualizados', async () => {
    onSubmit.mockResolvedValue(true)
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    const nombreInput = screen.getByLabelText(/nombre/i)
    await userEvent.clear(nombreInput)
    await userEvent.type(nombreInput, 'Ana María')
    fireEvent.submit(screen.getByRole('button', { name: /guardar/i }).closest('form'))
    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith({ nombre: 'Ana María', apellido: 'López' })
    })
  })

  it('NO limpia el formulario después de editar (editing sigue activo)', async () => {
    onSubmit.mockResolvedValue(true)
    render(<AlumnoForm editing={alumno} onSubmit={onSubmit} onCancel={onCancel} />)
    fireEvent.submit(screen.getByRole('button', { name: /guardar/i }).closest('form'))
    await waitFor(() => {
      // En modo edición el form no se limpia (editing sigue siendo truthy)
      expect(screen.getByLabelText(/nombre/i)).toHaveValue('Ana')
    })
  })
})
