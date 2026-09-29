<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/api/client'
import type { Genre, SearchResponse } from '@/api/types'
import AppHeader from '@/components/shell/AppHeader.vue'
import PosterCard from '@/components/catalog/PosterCard.vue'

const route = useRoute()
const router = useRouter()

const q = ref(typeof route.query.q === 'string' ? route.query.q : '')
const genres = ref<(Genre & { count: number })[]>([])
const result = ref<SearchResponse | null>(null)
const loading = ref(false)
let debounce: number | undefined
let seq = 0

const genre = () => (typeof route.query.genero === 'string' ? route.query.genero : undefined)

async function run() {
  const mine = ++seq
  loading.value = true
  const params = new URLSearchParams()
  if (q.value.trim()) params.set('q', q.value.trim())
  if (genre()) params.set('genero', genre()!)
  const res = await api.get<SearchResponse>(`/api/catalog/search?${params}`)
  if (mine === seq) {
    result.value = res
    loading.value = false
  }
}

// URL is the source of truth, so searches are shareable and back-button friendly.
function sync() {
  router.replace({ query: { ...(q.value.trim() ? { q: q.value.trim() } : {}), ...(genre() ? { genero: genre() } : {}) } })
}

function onInput() {
  window.clearTimeout(debounce)
  debounce = window.setTimeout(sync, 250)
}

function toggleGenre(slug: string) {
  router.replace({ query: { ...route.query, genero: genre() === slug ? undefined : slug } })
}

watch(() => route.fullPath, run)

onMounted(async () => {
  genres.value = (await api.get<{ genres: (Genre & { count: number })[] }>('/api/catalog/genres')).genres
  await run()
})
</script>

<template>
  <AppHeader />
  <main class="glow-top pb-24">
    <div class="wrap pt-16">
      <p class="page-kicker">Buscar</p>
      <label for="search-input" class="sr-only">Buscar por título, elenco ou direção</label>
      <input
        id="search-input"
        v-model="q"
        type="search"
        autocomplete="off"
        autofocus
        placeholder="Títulos, elenco, direção…"
        class="display mt-6 w-full border-0 border-b border-border bg-transparent pb-4 text-4xl text-fg outline-none placeholder:text-fg-faint focus:border-[var(--accent-dim)] sm:text-6xl"
        @input="onInput"
      />

      <div v-if="genres.length" class="mt-8 flex flex-wrap gap-2" role="group" aria-label="Gêneros">
        <button
          v-for="g in genres"
          :key="g.slug"
          type="button"
          class="rounded-md border px-3 py-1.5 text-xs font-semibold transition"
          :class="genre() === g.slug ? 'border-[var(--accent-dim)] bg-[var(--accent-faint)] text-accent-hi' : 'border-border text-muted-fg hover:text-fg'"
          :aria-pressed="genre() === g.slug"
          @click="toggleGenre(g.slug)"
        >
          {{ g.name }} <span class="text-fg-faint">{{ g.count }}</span>
        </button>
      </div>

      <section class="mt-12" aria-live="polite">
        <h2 v-if="result" class="sec-label mb-6">
          <span class="idx">{{ String(result.results.length).padStart(2, '0') }}</span>
          {{ result.genre ? result.genre.name : 'Resultados' }}<template v-if="result.query"> · “{{ result.query }}”</template>
        </h2>
        <p v-if="result && !result.results.length && !loading" class="lede">
          Nada encontrado. Tente outro nome ou tire o filtro de gênero.
        </p>
        <div v-if="result?.results.length" class="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
          <PosterCard v-for="item in result.results" :key="item.type + item.id" :item="item" />
        </div>
      </section>
    </div>
  </main>
</template>
