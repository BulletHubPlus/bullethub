<script setup lang="ts">
import { ref } from 'vue'
import { api, ApiError } from '@/api/client'
import AuthLayout from '@/components/ui/AuthLayout.vue'
import TextField from '@/components/ui/TextField.vue'
import SubmitButton from '@/components/ui/SubmitButton.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const email = ref('')
const loading = ref(false)
const sent = ref(false)
const error = ref<string | null>(null)

async function submit() {
  loading.value = true
  error.value = null
  try {
    await api.post('/api/auth/password/forgot', { email: email.value }, false)
    sent.value = true
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Tente novamente.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <AuthLayout kicker="Recuperar acesso" title="Esqueceu a senha?" subtitle="Enviaremos um link de redefinição para o seu e-mail.">
    <FormAlert v-if="sent" kind="success">
      Se existir uma conta com esse e-mail, você receberá o link em instantes.
    </FormAlert>
    <form v-else class="space-y-5" novalidate @submit.prevent="submit">
      <FormAlert v-if="error">{{ error }}</FormAlert>
      <TextField v-model="email" label="E-mail" type="email" autocomplete="email" inputmode="email" />
      <SubmitButton :loading="loading">Enviar link</SubmitButton>
    </form>
    <template #footer>
      <RouterLink to="/entrar" class="font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">← Voltar ao login</RouterLink>
    </template>
  </AuthLayout>
</template>
