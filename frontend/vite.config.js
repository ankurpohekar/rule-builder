import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Requests to /api go to the Rails server, so no CORS setup is needed in development.
// API_URL points the proxy at a different server (default: Rails on port 3000).
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': process.env.API_URL ?? 'http://localhost:3000',
    },
  },
})
