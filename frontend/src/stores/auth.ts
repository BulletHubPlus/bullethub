import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { api, onSessionChange, refreshSession } from '@/api/client'
import type { User } from '@/api/types'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const deviceId = ref<string | null>(null)
  const bootstrapped = ref(false)

  const isAuthenticated = computed(() => user.value !== null)

  onSessionChange((session) => {
    user.value = session?.user ?? null
    deviceId.value = session?.device_id ?? null
  })

  /** Restores the session from the refresh cookie on first load. */
  async function bootstrap() {
    if (bootstrapped.value) return
    try {
      await refreshSession()
    } finally {
      bootstrapped.value = true
    }
  }

  async function login(email: string, password: string) {
    await api.login(email, password)
  }

  async function logout() {
    await api.logout()
  }

  /** Called when the server drops this device (revoked elsewhere). */
  function forceSignedOut() {
    user.value = null
    deviceId.value = null
  }

  return { user, deviceId, bootstrapped, isAuthenticated, bootstrap, login, logout, forceSignedOut }
})
