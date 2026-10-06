import { useState } from 'react'

export default function CsvPanel({ onExport, onImport }) {
  const [csvText, setCsvText] = useState('')
  const [open, setOpen]       = useState(false)

  const handleImport = async () => {
    if (!csvText.trim()) return
    const ok = await onImport(csvText.trim())
    if (ok) setCsvText('')
  }

  return (
    <div className="card">
      <div className="card-title" style={{ justifyContent: 'space-between' }}>
        <span>📄 Importar / Exportar CSV</span>
        <button className="btn btn-ghost btn-sm" onClick={() => setOpen(o => !o)}>
          {open ? 'Ocultar' : 'Mostrar'}
        </button>
      </div>

      {open && (
        <>
          <p style={{ fontSize: '.85rem', color: 'var(--text-muted)', marginBottom: '.75rem' }}>
            Formato CSV: <code>nombre,apellido</code> — una fila por línea, sin encabezado.
          </p>

          <textarea
            value={csvText}
            onChange={e => setCsvText(e.target.value)}
            placeholder={"Juan,Pérez\nAna,López\nCarlos,Soto"}
            rows={5}
            style={{
              width: '100%', padding: '.6rem .75rem',
              border: '1.5px solid var(--border)', borderRadius: '6px',
              fontFamily: 'monospace', fontSize: '.88rem', resize: 'vertical',
              outline: 'none', marginBottom: '.75rem'
            }}
          />

          <div className="btn-actions">
            <button className="btn btn-primary" onClick={handleImport} disabled={!csvText.trim()}>
              ⬆️ Importar
            </button>
            <button className="btn btn-ghost" onClick={onExport}>
              ⬇️ Exportar todos
            </button>
          </div>
        </>
      )}
    </div>
  )
}
