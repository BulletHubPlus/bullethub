<script setup lang="ts">
import { ref, watch } from 'vue'
import { api, ApiError } from '@/api/client'
import type { CatalogCard } from '@/api/types'
import AppHeader from '@/components/shell/AppHeader.vue'
import PosterCard from '@/components/catalog/PosterCard.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const props = defineProps<{ kind: string }>()

const titles: Record<string, { title: string; accent: string }> = {
  series: { title: 'Séries', accent: 'temporada após temporada.' },
  animes: { title: 'Animes', accent: 'do shounen ao seinen.' },
  filmes: { title: 'Filmes', accent: 'uma sessão por vez.' },
}

const results = ref<CatalogCard[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

watch(
  () => props.kind,
  async (kind) => {
    loading.value = true
    error.value = null
    try {
      results.value = (await api.get<{ results: CatalogCard[] }>(`/api/catalog/browse/${kind}`)).results
    } catch (e) {
      error.value = e instanceof ApiError && e.status === 404 ? 'Categoria inválida.' : 'Erro ao carregar.'
    } finally {
      loading.value = false
    }
  },
  { immediate: true },
)
</script>

<template>
  <AppHeader />
  <main class="glow-top pb-24">
    <div class="wrap">
      <header class="fade-in pt-16 pb-10">
        <p class="page-kicker">Catálogo</p>
        <h1 class="display mt-6 text-5xl sm:text-7xl">
          {{ titles[kind]?.title ?? 'Catálogo' }}<span class="accent">.</span>
        </h1>
        <p class="lede mt-4">{{ titles[kind]?.accent }}</p>
      </header>

      <FormAlert v-if="error">{{ error }}</FormAlert>

      <div v-if="loading" class="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
        <div v-for="n in 10" :key="n" class="tile" />
      </div>

      <p v-else-if="!results.length" class="lede">Nada publicado por aqui ainda.</p>

      <div v-else class="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
        <PosterCard v-for="item in results" :key="item.type + item.id" :item="item" />
      </div>
    </div>
  </main>
</template>
