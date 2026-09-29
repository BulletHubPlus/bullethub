<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { api, ApiError } from '@/api/client'
import AuthLayout from '@/components/ui/AuthLayout.vue'
import TextField from '@/components/ui/TextField.vue'
import SubmitButton from '@/components/ui/SubmitButton.vue'
import FormAlert from '@/components/ui/FormAlert.vue'
import { formatCpf, isValidCpf, onlyDigits } from '@/utils/cpf'

const route = useRoute()

// Plan picked on the landing page. Billing (Fase 3) will charge it; for now it's shown and kept in the URL.
const planNames: Record<string, string> = { basico: 'Básico · 1 tela', padrao: 'Padrão · 2 telas', familia: 'Família · 4 telas' }
const chosenPlan = computed(() => {
  const plan = route.query.plano
  return typeof plan === 'string' ? planNames[plan] : undefined
})

const form = reactive({ name: '', email: '', cpf: '', password: '' })
const fieldErrors = ref<Record<string, string[]>>({})
const error = ref<string | null>(null)
const loading = ref(false)
const done = ref(false)

watch(
  () => form.cpf,
  (value) => {
    const formatted = formatCpf(value)
    if (formatted !== value) form.cpf = formatted
  },
)

async function submit() {
  fieldErrors.value = {}
  error.value = null

  if (!isValidCpf(form.cpf)) {
    fieldErrors.value = { cpf: ['CPF inválido'] }
    return
  }

  loading.value = true
  try {
    await api.post('/api/auth/register', { ...form, cpf: onlyDigits(form.cpf) }, false)
    done.value = true
  } catch (e) {
    if (e instanceof ApiError && e.code === 'validation_failed') fieldErrors.value = e.fields
    else error.value = e instanceof ApiError ? e.message : 'Não foi possível criar a conta.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <AuthLayout kicker="Criar conta" title="Comece a assistir." subtitle="Leva menos de um minuto.">
    <FormAlert v-if="done" kind="success">
      Conta criada. Enviamos um link de confirmação para <strong>{{ form.email }}</strong>.
      <RouterLink to="/entrar" class="mt-2 block font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">Ir para o login</RouterLink>
    </FormAlert>

    <form v-else class="space-y-5" novalidate @submit.prevent="submit">
      <div v-if="chosenPlan" class="card card-accent flex items-center justify-between px-4 py-3 text-sm">
        <span><span class="text-fg-faint">Plano:</span> <strong>{{ chosenPlan }}</strong></span>
        <RouterLink to="/#planos" class="btn-ghost text-xs">Trocar</RouterLink>
      </div>
      <FormAlert v-if="error">{{ error }}</FormAlert>
      <TextField v-model="form.name" label="Nome" autocomplete="name" :errors="fieldErrors.name" />
      <TextField v-model="form.email" label="E-mail" type="email" autocomplete="email" inputmode="email" :errors="fieldErrors.email" />
      <TextField
        v-model="form.cpf"
        label="CPF"
        inputmode="numeric"
        :maxlength="14"
        hint="Usado para nota fiscal. Guardado cifrado e nunca exibido no vídeo."
        :errors="fieldErrors.cpf"
      />
      <TextField
        v-model="form.password"
        label="Senha"
        type="password"
        autocomplete="new-password"
        hint="Mínimo de 12 caracteres."
        :errors="fieldErrors.password"
      />
      <SubmitButton :loading="loading">Criar conta</SubmitButton>
    </form>

    <template #footer>
      Já tem conta?
      <RouterLink to="/entrar" class="font-semibold text-fg underline decoration-border underline-offset-4 hover:decoration-accent">Entrar</RouterLink>
    </template>
  </AuthLayout>
</template>
