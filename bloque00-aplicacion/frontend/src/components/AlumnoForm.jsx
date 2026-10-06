import { useState, useEffect } from 'react'

const EMPTY = { nombre: '', apellido: '' }

export default function AlumnoForm({ editing, onSubmit, onCancel }) {
  const [form, setForm] = useState(EMPTY)

  useEffect(() => {
    setForm(editing ? { nombre: editing.nombre, apellido: editing.apellido } : EMPTY)
  }, [editing])

  const handle = (e) => setForm(f => ({ ...f, [e.target.name]: e.target.value }))

  const submit = async (e) => {
    e.preventDefault()
    if (!form.nombre.trim() || !form.apellido.trim()) return
    const ok = await onSubmit(form)
    if (ok && !editing) setForm(EMPTY)
  }

  return (
    <div className="card">
      <div className="card-title">
        {editing ? '✏️ Editar alumno' : '➕ Nuevo alumno'}
      </div>
      <form onSubmit={submit}>
        <div className="form-row">
          <div className="form-group">
            <label htmlFor="nombre">Nombre</label>
            <input
              id="nombre" name="nombre" value={form.nombre}
              onChange={handle} placeholder="Ej: Juan"
              required autoComplete="off"
            />
          </div>
          <div className="form-group">
            <label htmlFor="apellido">Apellido</label>
            <input
              id="apellido" name="apellido" value={form.apellido}
              onChange={handle} placeholder="Ej: Pérez"
              required autoComplete="off"
            />
          </div>
        </div>
        <div className="btn-actions">
          <button type="submit" className="btn btn-primary">
            {editing ? 'Guardar cambios' : 'Agregar alumno'}
          </button>
          {editing && (
            <button type="button" className="btn btn-ghost" onClick={onCancel}>
              Cancelar
            </button>
          )}
        </div>
      </form>
    </div>
  )
}
