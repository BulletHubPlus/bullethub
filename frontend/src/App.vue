<script setup lang="ts">
import { watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useProgressStore } from '@/stores/progress'
import { connectUserChannel, disconnectUserChannel } from '@/composables/useUserChannel'

const auth = useAuthStore()
const progress = useProgressStore()
const router = useRouter()

// Keep the realtime channel tied to the signed-in user.
watch(
  () => auth.user?.id,
  (userId) => {
    if (!userId) {
      disconnectUserChannel()
      return
    }
    const signOut = () => {
      auth.forceSignedOut()
      router.push({ name: 'login', query: { motivo: 'sessao-encerrada' } })
    }
    connectUserChannel(userId, {
      onDeviceRevoked: (deviceId) => {
        if (deviceId === auth.deviceId) signOut()
      },
      onAuthLost: signOut,
      // Other devices' progress updates the UI only; never seeks a running player.
      onProgressUpdated: ({ media_id, position, completed, device_id }) => {
        if (device_id !== auth.deviceId) progress.set(media_id, { position, completed })
      },
    })
  },
)
</script>

<template>
  <RouterView />
</template>
