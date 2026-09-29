<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { api, ApiError, getAccessToken } from '@/api/client'
import type { Subscription, User } from '@/api/types'
import { useAuthStore } from '@/stores/auth'
import AppHeader from '@/components/shell/AppHeader.vue'
import FormAlert from '@/components/ui/FormAlert.vue'
import TextField from '@/components/ui/TextField.vue'
import UserAvatar from '@/components/ui/UserAvatar.vue'
import Icon from '@/components/ui/Icon.vue'
import { useInstallPrompt } from '@/composables/useInstallPrompt'

interface MeResponse {
  user: User
  account: { cpf_masked: string | null }
  subscription: Subscription | null
}

const auth = useAuthStore()
const pwa = useInstallPrompt()
const router = useRouter()
const me = ref<MeResponse | null>(null)
const error = ref<string | null>(null)
const exporting = ref(false)
const confirmDelete = ref(false)
const password = ref('')
const deleteError = ref<string[] | undefined>()
const deleting = ref(false)

const statusLabel: Record<Subscription['status'], string> = {
  trialing: 'em teste',
  active: 'ativo',
  past_due: 'pagamento pendente',
  canceled: 'cancelado',
}

onMounted(async () => {
  try {
    me.value = await api.get<MeResponse>('/api/me')
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Erro ao carregar a conta.'
  }
})

const fmtDate = (iso: string) => new Intl.DateTimeFormat('pt-BR', { dateStyle: 'long' }).format(new Date(iso))

// The file comes from the API with auth, so it's fetched and saved as a blob.
async function exportData() {
  exporting.value = true
  try {
    const res = await fetch('/api/me/export', { headers: { authorization: `Bearer ${getAccessToken()}` } })
    if (!res.ok) throw new Error()
    const url = URL.createObjectURL(await res.blob())
    const a = Object.assign(document.createElement('a'), { href: url, download: 'bullethub-meus-dados.json' })
    a.click()
    URL.revokeObjectURL(url)
  } catch {
    error.value = 'Não foi possível gerar o arquivo agora.'
  } finally {
    exporting.value = false
  }
}

async function deleteAccount() {
  deleting.value = true
  deleteError.value = undefined
  try {
    await api.del<void>('/api/me', { password: password.value })
    auth.forceSignedOut()
    await router.replace({ name: 'home' })
  } catch (e) {
    deleteError.value = [e instanceof ApiError ? e.message : 'Não foi possível excluir agora.']
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <AppHeader />
  <main class="glow-top pb-24">
    <div class="wrap max-w-[860px]">
      <header class="fade-in flex flex-wrap items-center gap-5 pt-20 pb-12">
        <UserAvatar :name="me?.user.name" :email="me?.user.email" :size="72" />
        <div class="min-w-0">
          <p class="page-kicker">Conta</p>
          <h1 class="display mt-2 text-4xl sm:text-5xl">{{ me?.user.name ?? 'Minha conta' }}</h1>
          <p class="mt-1 truncate text-sm text-fg-faint">{{ me?.user.email }}</p>
        </div>
      </header>

      <FormAlert v-if="error" class="mb-6">{{ error }}</FormAlert>

      <template v-if="me">
        <h2 class="sec-label mb-5"><span class="idx">01</span>Dados</h2>
        <dl class="card grid grid-cols-[auto_1fr] gap-x-8 gap-y-3 p-6 text-sm">
          <dt class="text-fg-faint">Nome</dt><dd>{{ me.user.name }}</dd>
          <dt class="text-fg-faint">E-mail</dt>
          <dd>{{ me.user.email }} <span v-if="!me.user.confirmed" class="text-accent-hi">· não confirmado</span></dd>
          <dt class="text-fg-faint">CPF</dt><dd class="tabular-nums">{{ me.account.cpf_masked ?? '-' }}</dd>
        </dl>

        <h2 class="sec-label mt-12 mb-5"><span class="idx">02</span>Plano</h2>
        <div class="card card-accent p-6 text-sm">
          <template v-if="me.subscription">
            <p class="display text-3xl">{{ me.subscription.plan.name }}</p>
            <p class="mt-2 text-muted-fg">
              {{ me.subscription.plan.max_streams }} {{ me.subscription.plan.max_streams === 1 ? 'tela' : 'telas simultâneas' }}
              · {{ statusLabel[me.subscription.status] }} · até {{ fmtDate(me.subscription.current_period_end) }}
            </p>
          </template>
          <p v-else class="text-muted-fg">Sem plano ativo. O pagamento online chega em breve.</p>
        </div>

        <h2 class="sec-label mt-12 mb-5"><span class="idx">03</span>Acesso</h2>
        <RouterLink
          to="/conta/dispositivos"
          class="card flex items-center gap-4 p-6 text-sm transition hover:border-[var(--accent-dim)]"
        >
          <span class="grid size-10 place-items-center rounded-lg border border-line text-fg-faint">
            <Icon name="devices" :size="18" />
          </span>
          <span class="flex-1">
            <span class="block font-semibold">Dispositivos conectados</span>
            <span class="block text-xs text-fg-faint">Veja e desconecte onde sua conta está aberta.</span>
          </span>
          <span aria-hidden="true" class="text-fg-faint">→</span>
        </RouterLink>

        <template v-if="!pwa.installed.value">
          <h2 class="sec-label mt-12 mb-5"><span class="idx">04</span>App</h2>
          <div class="card flex flex-wrap items-center justify-between gap-4 p-6 text-sm">
            <div>
              <p class="font-semibold">Instalar o bullethub</p>
              <p v-if="pwa.isIOS" class="mt-1 text-fg-faint">No Safari, toque em Compartilhar → “Adicionar à Tela de Início”.</p>
              <p v-else class="mt-1 text-fg-faint">Abre em tela cheia, com ícone na tela inicial, como um app.</p>
            </div>
            <button v-if="pwa.canPrompt.value" type="button" class="btn btn-primary sm" @click="pwa.install">Instalar</button>
          </div>
        </template>

        <h2 class="sec-label mt-12 mb-5"><span class="idx">05</span>Privacidade</h2>
        <div class="card space-y-6 p-6 text-sm">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <p class="font-semibold">Baixar meus dados</p>
              <p class="mt-1 text-fg-faint">Tudo o que guardamos sobre você, em JSON (LGPD, art. 18).</p>
            </div>
            <button type="button" class="btn btn-quiet sm" :disabled="exporting" @click="exportData">
              {{ exporting ? 'Gerando…' : 'Baixar' }}
            </button>
          </div>

          <div class="border-t border-border pt-6">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div>
                <p class="font-semibold">Excluir conta</p>
                <p class="mt-1 max-w-[52ch] text-fg-faint">
                  Apaga nome, e-mail, dispositivos e histórico. CPF e registros de cobrança ficam guardados pelo prazo fiscal
                  (5 anos) e depois são descartados. Não dá para desfazer.
                </p>
              </div>
              <button v-if="!confirmDelete" type="button" class="btn btn-quiet sm" @click="confirmDelete = true">Excluir…</button>
            </div>

            <form v-if="confirmDelete" class="mt-6 max-w-sm space-y-4" @submit.prevent="deleteAccount">
              <TextField v-model="password" label="Confirme sua senha" type="password" autocomplete="current-password" :errors="deleteError" />
              <div class="flex gap-3">
                <button type="submit" class="btn btn-primary sm" :disabled="deleting || !password">Excluir definitivamente</button>
                <button type="button" class="btn-ghost text-sm" @click="confirmDelete = false">Cancelar</button>
              </div>
            </form>
          </div>
        </div>
      </template>
    </div>
  </main>
</template>
