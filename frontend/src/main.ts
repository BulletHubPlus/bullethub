import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './styles/main.css'

createApp(App).use(createPinia()).use(router).mount('#app')

// PWA: only in production builds (Vite dev serves modules the SW shouldn't cache).
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => void navigator.serviceWorker.register('/sw.js', { scope: '/' }))
}
