<script setup lang="ts">
import { ref } from 'vue'
import { api, ApiError } from '@/api/client'
import AuthLayout from '@/components/ui/AuthLayout.vue'
import TextField from '@/components/ui/TextField.vue'
import SubmitButton from '@/components/ui/SubmitButton.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const props = defineProps<{ token: string }>()

const password = ref('')
const loading = ref(false)
const done = ref(false)
const error = ref<string | null>(null)
const fieldErrors = ref<Record<string, string[]>>({})

async function submit() {
  loading.value = true
  error.value = null
  fieldErrors.value = {}
  try {
    await api.post('/api/auth/password/reset', { token: props.token, password: password.value }, false)
    done.value = true
  } catch (e) {
    if (e instanceof ApiError && e.code === 'validation_failed') fieldErrors.value = e.fields
    else error.value = e instanceof ApiError ? e.message : 'Tente novamente.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <AuthLayout kicker="Nova senha" title="Defina sua nova senha." subtitle="Todos os seus dispositivos serão desconectados.">
    <FormAlert v-if="done" kind="success">
      Senha alterada.
      <RouterLink to="/entrar" class="mt-2 block font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">Entrar</RouterLink>
    </FormAlert>
    <form v-else class="space-y-5" novalidate @submit.prevent="submit">
      <FormAlert v-if="error">{{ error }}</FormAlert>
      <TextField
        v-model="password"
        label="Nova senha"
        type="password"
        autocomplete="new-password"
        hint="Mínimo de 12 caracteres."
        :errors="fieldErrors.password"
      />
      <SubmitButton :loading="loading">Salvar</SubmitButton>
    </form>
  </AuthLayout>
</template>
