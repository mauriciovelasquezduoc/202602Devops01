import axios from 'axios'

// El backend está expuesto en localhost:8080 en el host
// En producción cambiar por la URL pública del backend via variable de entorno
//const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

const api = axios.create({ baseURL: `/ep03` })

export const getAlumnos   = ()           => api.get('')
export const createAlumno = (data)       => api.post('', data)
export const updateAlumno = (id, data)   => api.put(`/${id}`, data)
export const deleteAlumno = (id)         => api.delete(`/${id}`)
export const exportCSV    = ()           => api.get('/export', { responseType: 'text' })
export const importCSV    = (csvText)    => api.post('/import', csvText, {
  headers: { 'Content-Type': 'text/plain' }
})
