import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import AlumnoTable from '../../components/AlumnoTable'

const onEdit   = vi.fn()
const onDelete = vi.fn()

const ALUMNOS = [
  { id: 1, nombre: 'Juan',   apellido: 'Pérez' },
  { id: 2, nombre: 'Ana',    apellido: 'López' },
]

beforeEach(() => {
  onEdit.mockReset()
  onDelete.mockReset()
})

describe('AlumnoTable — lista vacía', () => {
  it('muestra el estado vacío cuando no hay ep03', () => {
    render(<AlumnoTable ep03={[]} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.getByText(/No hay ep03 registrados/i)).toBeInTheDocument()
  })

  it('muestra el ícono de estado vacío', () => {
    render(<AlumnoTable ep03={[]} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.getByText('🎓')).toBeInTheDocument()
  })

  it('no renderiza la tabla cuando no hay ep03', () => {
    render(<AlumnoTable ep03={[]} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
})

describe('AlumnoTable — con ep03', () => {
  it('renderiza la tabla con encabezados correctos', () => {
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.getByText('#')).toBeInTheDocument()
    expect(screen.getByText('Nombre')).toBeInTheDocument()
    expect(screen.getByText('Apellido')).toBeInTheDocument()
    expect(screen.getByText('Acciones')).toBeInTheDocument()
  })

  it('muestra todos los ep03 en la tabla', () => {
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.getByText('Juan')).toBeInTheDocument()
    expect(screen.getByText('Pérez')).toBeInTheDocument()
    expect(screen.getByText('Ana')).toBeInTheDocument()
    expect(screen.getByText('López')).toBeInTheDocument()
  })

  it('muestra el id de cada alumno como badge', () => {
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    expect(screen.getByText('1')).toBeInTheDocument()
    expect(screen.getByText('2')).toBeInTheDocument()
  })

  it('llama onEdit con el alumno correcto al hacer click en Editar', () => {
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    const editBtns = screen.getAllByTitle('Editar')
    fireEvent.click(editBtns[0])
    expect(onEdit).toHaveBeenCalledWith(ALUMNOS[0])
  })

  it('llama onDelete con el id correcto al confirmar eliminación', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    const deleteBtns = screen.getAllByTitle('Eliminar')
    fireEvent.click(deleteBtns[0])
    expect(onDelete).toHaveBeenCalledWith(1)
    vi.restoreAllMocks()
  })

  it('NO llama onDelete si el usuario cancela la confirmación', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false)
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    const deleteBtns = screen.getAllByTitle('Eliminar')
    fireEvent.click(deleteBtns[0])
    expect(onDelete).not.toHaveBeenCalled()
    vi.restoreAllMocks()
  })

  it('muestra el mensaje correcto en el confirm de eliminación', () => {
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false)
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    fireEvent.click(screen.getAllByTitle('Eliminar')[0])
    expect(confirmSpy).toHaveBeenCalledWith('¿Eliminar a Juan Pérez?')
    vi.restoreAllMocks()
  })

  it('renderiza el número correcto de filas', () => {
    render(<AlumnoTable ep03={ALUMNOS} onEdit={onEdit} onDelete={onDelete} />)
    const rows = screen.getAllByRole('row')
    // 1 fila de encabezado + 2 filas de datos
    expect(rows).toHaveLength(3)
  })
})
