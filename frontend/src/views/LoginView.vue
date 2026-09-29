<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ApiError } from '@/api/client'
import { useAuthStore } from '@/stores/auth'
import AuthLayout from '@/components/ui/AuthLayout.vue'
import TextField from '@/components/ui/TextField.vue'
import SubmitButton from '@/components/ui/SubmitButton.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)

const notice = computed(() =>
  route.query.motivo === 'sessao-encerrada' ? 'Sua sessão foi encerrada neste dispositivo. Entre novamente.' : null,
)

// Only same-app relative paths; never an absolute URL (open redirect).
function safeNext(): string {
  const next = route.query.next
  return typeof next === 'string' && next.startsWith('/') && !next.startsWith('//') ? next : '/'
}

async function submit() {
  loading.value = true
  error.value = null
  try {
    await auth.login(email.value, password.value)
    await router.replace(safeNext())
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Não foi possível entrar. Tente novamente.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <AuthLayout kicker="Entrar" title="Bem-vindo de volta." subtitle="Entre para continuar assistindo.">
    <form class="space-y-5" novalidate @submit.prevent="submit">
      <FormAlert v-if="notice" kind="success">{{ notice }}</FormAlert>
      <FormAlert v-if="error">{{ error }}</FormAlert>
      <TextField v-model="email" label="E-mail" type="email" autocomplete="email" inputmode="email" placeholder="voce@email.com" />
      <TextField v-model="password" label="Senha" type="password" autocomplete="current-password" />
      <SubmitButton :loading="loading">Entrar</SubmitButton>
      <RouterLink to="/esqueci-senha" class="btn-ghost block text-center text-sm">Esqueci minha senha</RouterLink>
    </form>
    <template #footer>
      Novo por aqui?
      <RouterLink to="/criar-conta" class="font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">Criar conta</RouterLink>
    </template>
  </AuthLayout>
</template>
