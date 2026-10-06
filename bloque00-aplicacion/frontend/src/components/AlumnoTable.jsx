export default function AlumnoTable({ ep03, onEdit, onDelete }) {
  if (ep03.length === 0) {
    return (
      <div className="empty-state">
        <div className="icon">🎓</div>
        <p>No hay ep03 registrados aún.</p>
        <p style={{ fontSize: '.85rem', marginTop: '.25rem' }}>
          Usa el formulario de arriba para agregar el primero.
        </p>
      </div>
    )
  }

  return (
    <div className="table-wrapper">
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Nombre</th>
            <th>Apellido</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          {ep03.map((a) => (
            <tr key={a.id}>
              <td><span className="badge">{a.id}</span></td>
              <td>{a.nombre}</td>
              <td>{a.apellido}</td>
              <td>
                <div className="td-actions">
                  <button
                    className="btn btn-ghost btn-sm"
                    onClick={() => onEdit(a)}
                    title="Editar"
                  >
                    ✏️ Editar
                  </button>
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => {
                      if (window.confirm(`¿Eliminar a ${a.nombre} ${a.apellido}?`)) {
                        onDelete(a.id)
                      }
                    }}
                    title="Eliminar"
                  >
                    🗑️ Eliminar
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
