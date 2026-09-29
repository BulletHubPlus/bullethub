<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api, ApiError } from '@/api/client'
import type { CatalogCard, HomeResponse } from '@/api/types'
import { useAuthStore } from '@/stores/auth'
import { kindLabel } from '@/utils/format'
import AppHeader from '@/components/shell/AppHeader.vue'
import FormAlert from '@/components/ui/FormAlert.vue'
import PosterCard from '@/components/catalog/PosterCard.vue'
import TitleMeta from '@/components/catalog/TitleMeta.vue'

const auth = useAuthStore()
const home = ref<HomeResponse | null>(null)
const loadError = ref<string | null>(null)
const resent = ref(false)
const resendError = ref<string | null>(null)

const featured = computed<CatalogCard | null>(() => home.value?.rows[0]?.items[0] ?? null)
const featuredImage = computed(() => featured.value?.backdrop_url || featured.value?.thumbnail_url || null)
const featuredLink = computed(() =>
  featured.value?.type === 'collection' ? `/titulo/${featured.value.slug}` : `/filme/${featured.value?.id}`,
)

onMounted(async () => {
  try {
    home.value = await api.get<HomeResponse>('/api/catalog/home')
  } catch (e) {
    loadError.value = e instanceof ApiError ? e.message : 'Não foi possível carregar o catálogo.'
  }
})

async function resend() {
  resendError.value = null
  try {
    await api.post('/api/auth/confirm/resend')
    resent.value = true
  } catch (e) {
    resendError.value = e instanceof ApiError ? e.message : 'Tente novamente.'
  }
}
</script>

<template>
  <AppHeader />
  <main class="glow-top pb-24">
    <div class="wrap pt-6">
      <FormAlert v-if="auth.user && !auth.user.confirmed" :kind="resent ? 'success' : 'error'">
        <template v-if="resent">Link reenviado para {{ auth.user.email }}.</template>
        <template v-else>
          Confirme seu e-mail para liberar a reprodução.
          <button type="button" class="btn-ghost ml-1 text-fg underline underline-offset-4" @click="resend">
            Reenviar link
          </button>
          <span v-if="resendError" class="ml-2 text-accent-hi">{{ resendError }}</span>
        </template>
      </FormAlert>
      <FormAlert v-if="loadError" class="mt-4">{{ loadError }}</FormAlert>

      <!-- featured -->
      <section
        v-if="featured"
        class="fade-in relative mt-8 overflow-hidden rounded-[var(--radius)] border border-border"
        :class="{ 'poster-fallback': !featuredImage }"
      >
        <img
          v-if="featuredImage"
          :src="featuredImage"
          alt=""
          class="absolute inset-0 h-full w-full object-cover opacity-60"
        />
        <div class="absolute inset-0 bg-gradient-to-r from-bg via-bg/80 to-transparent" />
        <div class="relative flex min-h-[380px] flex-col justify-end p-8 sm:p-12">
          <p class="page-kicker">{{ kindLabel[featured.kind] }} · Em destaque</p>
          <h1 class="display mt-5 max-w-[14ch] text-5xl sm:text-6xl">{{ featured.title }}</h1>
          <TitleMeta :title="featured" :duration-seconds="featured.duration_seconds" class="mt-4" />
          <p v-if="featured.description" class="lede mt-4 line-clamp-3 max-w-[52ch]">{{ featured.description }}</p>
          <div class="mt-8">
            <RouterLink :to="featuredLink" class="btn btn-primary">Ver detalhes <span aria-hidden="true">→</span></RouterLink>
          </div>
        </div>
      </section>

      <header v-else-if="home" class="fade-in pt-14 pb-6">
        <p class="page-kicker">Início</p>
        <h1 class="display mt-6 max-w-[16ch] text-5xl sm:text-7xl">
          Olá, {{ auth.user?.name?.split(' ')[0] }}<span class="accent">.</span>
        </h1>
        <p class="lede mt-5 max-w-[52ch]">
          O catálogo ainda está vazio. Assim que o primeiro título for publicado no painel, ele aparece aqui.
        </p>
      </header>

      <!-- rows -->
      <template v-if="home">
        <section v-if="home.continue_watching.length" class="mt-14" aria-label="Continuar assistindo">
          <h2 class="sec-label mb-5"><span class="idx">00</span>Continuar assistindo</h2>
          <div class="rail">
            <PosterCard v-for="item in home.continue_watching" :key="'p' + item.id" :item="item" />
          </div>
        </section>
        <section v-if="home.my_list.length" class="mt-14" aria-label="Minha lista">
          <h2 class="sec-label mb-5"><span class="idx">★</span>Minha lista</h2>
          <div class="rail">
            <PosterCard v-for="item in home.my_list" :key="'l' + item.id" :item="item" />
          </div>
        </section>

        <section v-for="(row, i) in home.rows" :key="row.id" class="mt-14" :aria-label="row.title">
          <h2 class="sec-label mb-5">
            <span class="idx">{{ String(i + 1).padStart(2, '0') }}</span>
            <RouterLink
              v-if="row.id.startsWith('genero-')"
              :to="{ name: 'search', query: { genero: row.id.slice(7) } }"
              class="hover:text-fg"
            >
              {{ row.title }} →
            </RouterLink>
            <template v-else>{{ row.title }}</template>
          </h2>
          <div class="rail">
            <PosterCard v-for="item in row.items" :key="item.type + item.id" :item="item" />
          </div>
        </section>
      </template>

      <!-- loading -->
      <template v-else-if="!loadError">
        <div class="tile mt-8 !aspect-auto h-[380px]" />
        <section v-for="n in 2" :key="n" class="mt-14">
          <div class="mb-5 h-3 w-40 rounded bg-card" />
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
            <div v-for="k in 5" :key="k" class="tile" :class="{ 'hidden sm:block': k > 2, 'hidden lg:block': k > 3 }" />
          </div>
        </section>
      </template>
    </div>
  </main>
</template>
