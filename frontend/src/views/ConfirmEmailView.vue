<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, ApiError } from '@/api/client'
import AuthLayout from '@/components/ui/AuthLayout.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const props = defineProps<{ token: string }>()
const state = ref<'loading' | 'ok' | 'error'>('loading')
const message = ref('')

onMounted(async () => {
  try {
    await api.post('/api/auth/confirm', { token: props.token }, false)
    state.value = 'ok'
  } catch (e) {
    state.value = 'error'
    message.value = e instanceof ApiError ? e.message : 'Não foi possível confirmar.'
  }
})
</script>

<template>
  <AuthLayout kicker="Verificação" title="Confirmação de e-mail.">
    <p v-if="state === 'loading'" class="lede">Confirmando…</p>
    <FormAlert v-else-if="state === 'ok'" kind="success">
      E-mail confirmado.
      <RouterLink to="/" class="mt-2 block font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">Continuar</RouterLink>
    </FormAlert>
    <FormAlert v-else>{{ message }}</FormAlert>
  </AuthLayout>
</template>
