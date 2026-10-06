import { useState } from 'react'
import { useAlumnos } from './hooks/useAlumnos'
import AlumnoForm  from './components/AlumnoForm'
import AlumnoTable from './components/AlumnoTable'
import CsvPanel    from './components/CsvPanel'

export default function App() {
  const {
    ep03, loading, error, success,
    crear, actualizar, eliminar, exportar, importar
  } = useAlumnos()

  const [editing, setEditing] = useState(null)

  const handleSubmit = async (form) => {
    if (editing) {
      const ok = await actualizar(editing.id, form)
      if (ok) setEditing(null)
      return ok
    }
    return crear(form)
  }

  return (
    <div className="app-wrapper">
      {/* ── Header ── */}
      <header className="app-header">
        <h1>🎓 Gestión de Alumnos</h1>
        <p>Sistema CRUD — Spring Boot + PostgreSQL + React</p>
      </header>

      {/* ── Alertas ── */}
      {error   && <div className="alert alert-error">⚠️ {error}</div>}
      {success && <div className="alert alert-success">✅ {success}</div>}

      {/* ── Stats ── */}
      <div className="stats-bar">
        <div className="stat-card">
          <div className="stat-num">{ep03.length}</div>
          <div className="stat-label">Total ep03</div>
        </div>
        <div className="stat-card">
          <div className="stat-num">
            {new Set(ep03.map(a => a.apellido)).size}
          </div>
          <div className="stat-label">Apellidos únicos</div>
        </div>
      </div>

      {/* ── Formulario ── */}
      <AlumnoForm
        editing={editing}
        onSubmit={handleSubmit}
        onCancel={() => setEditing(null)}
      />

      {/* ── CSV ── */}
      <CsvPanel onExport={exportar} onImport={importar} />

      {/* ── Tabla ── */}
      <div className="card">
        <div className="card-title">
          📋 Lista de ep03
          {loading && <span style={{ fontSize: '.8rem', color: 'var(--text-muted)', marginLeft: 'auto' }}>
            Cargando...
          </span>}
        </div>

        {loading ? (
          <div className="spinner-wrap"><div className="spinner" /></div>
        ) : (
          <AlumnoTable
            ep03={ep03}
            onEdit={setEditing}
            onDelete={eliminar}
          />
        )}
      </div>

      {/* ── Footer ── */}
      <footer style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '.8rem', marginTop: '1rem' }}>
        API: <code>{import.meta.env.VITE_API_URL || 'http://localhost:8080'}/ep03</code>
      </footer>
    </div>
  )
}
