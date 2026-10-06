import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],

  server: {
    port: 3000,
    host: '0.0.0.0',
    proxy: {
      '/ep03': {
        target: process.env.VITE_API_URL || 'http://localhost:8080',
        changeOrigin: true,
      }
    }
  },

  // ── Vitest ────────────────────────────────────────────────────────────────
  test: {
    // Simula el DOM del navegador
    environment: 'jsdom',

    // Carga los matchers de jest-dom globalmente en todos los tests
    setupFiles: ['./src/test/setup.js'],

    // Hace disponibles describe/it/expect sin importar
    globals: true,

    // ── Cobertura ──────────────────────────────────────────────────────────
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      reportsDirectory: './coverage',

      // Archivos que se incluyen en el reporte
      include: ['src/**/*.{js,jsx}'],

      // Excluir archivos que no necesitan cobertura
      exclude: [
        'src/main.jsx',
        'src/index.css',
        'src/test/**',
      ],

      // ── UMBRALES: si no se alcanza el 90% el build FALLA ─────────────────
      thresholds: {
        lines:      90,
        functions:  90,
        branches:   90,
        statements: 90,
      },
    },
  },
})
