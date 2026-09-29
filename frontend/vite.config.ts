import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'

// The build lands inside the Phoenix release (priv/static/app) and is served
// by Plug.Static at /app/assets; Phoenix returns index.html for app routes.
// In dev, Vite proxies API and WebSocket to Phoenix so everything stays same-origin.
// BACKEND_PORT lets the proxy follow Phoenix when :4000 is taken (e.g. PORT=4010).
const backend = `localhost:${process.env.BACKEND_PORT ?? '4000'}`

export default defineConfig(({ command }) => ({
  base: command === 'build' ? '/app/' : '/',
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    outDir: '../backend/priv/static/app',
    emptyOutDir: true,
    sourcemap: false,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': `http://${backend}`,
      '/health': `http://${backend}`,
      // Dev-only Phoenix routes: sample video (Fake provider) and the Swoosh mailbox.
      '/dev': `http://${backend}`,
      // Dev-only proxy to the local Phoenix server (loopback); wss is not applicable here.
      // nosemgrep: javascript.lang.security.detect-insecure-websocket.detect-insecure-websocket
      '/socket': { target: `ws://${backend}`, ws: true },
    },
  },
  test: {
    environment: 'jsdom',
  },
}))
