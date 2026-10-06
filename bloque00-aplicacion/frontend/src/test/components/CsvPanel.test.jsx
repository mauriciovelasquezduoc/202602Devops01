import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import CsvPanel from '../../components/CsvPanel'

const onExport = vi.fn()
const onImport = vi.fn()

beforeEach(() => {
  onExport.mockReset()
  onImport.mockReset()
})

describe('CsvPanel — estado inicial (cerrado)', () => {
  it('muestra el título del panel', () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    expect(screen.getByText(/Importar \/ Exportar CSV/i)).toBeInTheDocument()
  })

  it('muestra el botón "Mostrar" cuando está cerrado', () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    expect(screen.getByText('Mostrar')).toBeInTheDocument()
  })

  it('no muestra el textarea cuando está cerrado', () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })

  it('no muestra los botones de importar/exportar cuando está cerrado', () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    // El título contiene "Importar" pero los botones de acción no deben estar
    expect(screen.queryByText(/⬆️ Importar/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/⬇️ Exportar todos/i)).not.toBeInTheDocument()
  })
})

describe('CsvPanel — panel abierto', () => {
  it('abre el panel al hacer click en "Mostrar"', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    expect(screen.getByRole('textbox')).toBeInTheDocument()
  })

  it('cambia el botón a "Ocultar" cuando está abierto', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    expect(screen.getByText('Ocultar')).toBeInTheDocument()
  })

  it('cierra el panel al hacer click en "Ocultar"', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.click(screen.getByText('Ocultar'))
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })

  it('muestra la instrucción de formato CSV', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    expect(screen.getByText(/nombre,apellido/i)).toBeInTheDocument()
  })

  it('el botón Importar está deshabilitado cuando el textarea está vacío', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    expect(screen.getByText(/⬆️ Importar/i)).toBeDisabled()
  })

  it('el botón Importar se habilita al escribir en el textarea', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.type(screen.getByRole('textbox'), 'Juan,Pérez')
    expect(screen.getByText(/⬆️ Importar/i)).not.toBeDisabled()
  })

  it('llama onImport con el texto del textarea al hacer click en Importar', async () => {
    onImport.mockResolvedValue(true)
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.type(screen.getByRole('textbox'), 'Juan,Pérez')
    await userEvent.click(screen.getByText(/⬆️ Importar/i))
    expect(onImport).toHaveBeenCalledWith('Juan,Pérez')
  })

  it('limpia el textarea después de un import exitoso', async () => {
    onImport.mockResolvedValue(true)
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.type(screen.getByRole('textbox'), 'Juan,Pérez')
    await userEvent.click(screen.getByText(/⬆️ Importar/i))
    await waitFor(() => {
      expect(screen.getByRole('textbox')).toHaveValue('')
    })
  })

  it('NO limpia el textarea si el import falla', async () => {
    onImport.mockResolvedValue(false)
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.type(screen.getByRole('textbox'), 'Juan,Pérez')
    await userEvent.click(screen.getByText(/⬆️ Importar/i))
    await waitFor(() => {
      expect(screen.getByRole('textbox')).toHaveValue('Juan,Pérez')
    })
  })

  it('NO llama onImport si el textarea está vacío (solo espacios)', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.type(screen.getByRole('textbox'), '   ')
    fireEvent.click(screen.getByText(/⬆️ Importar/i))
    expect(onImport).not.toHaveBeenCalled()
  })

  it('llama onExport al hacer click en "Exportar todos"', async () => {
    render(<CsvPanel onExport={onExport} onImport={onImport} />)
    await userEvent.click(screen.getByText('Mostrar'))
    await userEvent.click(screen.getByText(/⬇️ Exportar todos/i))
    expect(onExport).toHaveBeenCalledTimes(1)
  })
})
