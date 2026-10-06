import { useState, useEffect, useCallback } from 'react'
import {
  getAlumnos, createAlumno, updateAlumno,
  deleteAlumno, exportCSV, importCSV
} from '../api/alumnos'

export function useAlumnos() {
  const [ep03,  setAlumnos]  = useState([])
  const [loading,  setLoading]  = useState(false)
  const [error,    setError]    = useState(null)
  const [success,  setSuccess]  = useState(null)

  const notify = (msg, isError = false) => {
    if (isError) { setError(msg);   setTimeout(() => setError(null),   4000) }
    else         { setSuccess(msg); setTimeout(() => setSuccess(null), 3000) }
  }

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const { data } = await getAlumnos()
      setAlumnos(data)
    } catch {
      notify('Error al cargar ep03', true)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  const crear = async (alumno) => {
    try {
      await createAlumno(alumno)
      notify('Alumno creado correctamente')
      load()
      return true
    } catch {
      notify('Error al crear alumno', true)
      return false
    }
  }

  const actualizar = async (id, alumno) => {
    try {
      await updateAlumno(id, alumno)
      notify('Alumno actualizado correctamente')
      load()
      return true
    } catch {
      notify('Error al actualizar alumno', true)
      return false
    }
  }

  const eliminar = async (id) => {
    try {
      await deleteAlumno(id)
      notify('Alumno eliminado')
      load()
    } catch {
      notify('Error al eliminar alumno', true)
    }
  }

  const exportar = async () => {
    try {
      const { data } = await exportCSV()
      const blob = new Blob([data], { type: 'text/csv' })
      const url  = URL.createObjectURL(blob)
      const a    = document.createElement('a')
      a.href = url; a.download = 'ep03.csv'; a.click()
      URL.revokeObjectURL(url)
      notify('CSV exportado')
    } catch {
      notify('Error al exportar', true)
    }
  }

  const importar = async (csvText) => {
    try {
      await importCSV(csvText)
      notify('CSV importado correctamente')
      load()
      return true
    } catch {
      notify('Error al importar CSV', true)
      return false
    }
  }

  return { ep03, loading, error, success, crear, actualizar, eliminar, exportar, importar, reload: load }
}
