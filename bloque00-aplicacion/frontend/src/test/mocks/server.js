import { setupServer } from 'msw/node'
import { handlers } from './handlers'

// Servidor MSW para interceptar peticiones HTTP en los tests
export const server = setupServer(...handlers)
