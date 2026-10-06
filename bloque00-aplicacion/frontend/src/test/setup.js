// Carga los matchers de @testing-library/jest-dom
// Ej: expect(el).toBeInTheDocument(), toHaveValue(), etc.
import '@testing-library/jest-dom'

// Configurar MSW para usar rutas relativas en tests
// El frontend usa axios.create({ baseURL: '/ep03' })
// MSW intercepta basado en la URL completa, así que necesitamos configurarlo
import { setupServer } from 'msw/node'
import { handlers } from './mocks/handlers'

// Servidor MSW para interceptar peticiones HTTP en los tests
// Usar setupServer para entornos Node.js (jsdom en vitest)
export const server = setupServer(...handlers)
