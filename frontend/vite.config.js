import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Requests to /api go to the Rails server, so no CORS setup is needed in development.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:3000',
    },
  },
})
