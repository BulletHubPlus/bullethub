<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { api, ApiError } from '@/api/client'
import type { CollectionResponse } from '@/api/types'
import { formatDuration, seasonLabel } from '@/utils/format'
import AppHeader from '@/components/shell/AppHeader.vue'
import FormAlert from '@/components/ui/FormAlert.vue'
import ProgressBar from '@/components/catalog/ProgressBar.vue'
import TitleHero from '@/components/catalog/TitleHero.vue'
import MyListButton from '@/components/catalog/MyListButton.vue'
import { useProgressStore } from '@/stores/progress'

const props = defineProps<{ slug: string }>()

const data = ref<CollectionResponse | null>(null)
const error = ref<string | null>(null)
const activeSeason = ref(0)

const season = computed(() => data.value?.seasons[activeSeason.value] ?? null)
const progressStore = useProgressStore()
const progressOf = (m: { id: string; progress?: { position: number; completed: boolean } | null }) =>
  progressStore.get(m.id, m.progress)

// Resume the first unfinished episode in order, else start from the top.
const resumeTarget = computed(() => {
  const all = data.value?.seasons.flatMap((s) => s.media) ?? []
  return all.find((m) => { const p = progressOf(m); return p && !p.completed && p.position > 0 }) ?? all.find((m) => !progressOf(m)?.completed) ?? all[0]
})

watch(
  () => props.slug,
  async (slug) => {
    data.value = null
    error.value = null
    activeSeason.value = 0
    try {
      data.value = await api.get<CollectionResponse>(`/api/catalog/collections/${encodeURIComponent(slug)}`)
    } catch (e) {
      error.value = e instanceof ApiError && e.status === 404 ? 'Título não encontrado.' : 'Erro ao carregar.'
    }
  },
  { immediate: true },
)
</script>

<template>
  <AppHeader />
  <main class="pb-24">
    <FormAlert v-if="error" class="wrap mt-10">{{ error }}</FormAlert>

    <template v-if="data">
      <TitleHero
        :title="data.collection"
        :synopsis="data.collection.description"
        :extra="`${data.seasons.length} temporada${data.seasons.length === 1 ? '' : 's'}`"
      >
        <RouterLink v-if="resumeTarget" :to="`/assistir/${resumeTarget.id}`" class="btn btn-primary">
          {{ progressOf(resumeTarget)?.position ? 'Continuar' : 'Assistir' }} · {{ resumeTarget.title }}
          <span aria-hidden="true">→</span>
        </RouterLink>
        <MyListButton kind="collection" :id="data.collection.id" :in-list="data.collection.in_my_list" />
      </TitleHero>

      <div class="wrap mt-12">
        <div v-if="data.seasons.length > 1" class="mb-8 flex flex-wrap gap-2" role="tablist">
          <button
            v-for="(s, i) in data.seasons"
            :key="s.id"
            type="button"
            role="tab"
            :aria-selected="i === activeSeason"
            class="btn sm"
            :class="i === activeSeason ? 'btn-primary' : 'btn-quiet'"
            @click="activeSeason = i"
          >
            {{ s.title || `${seasonLabel(data.collection.kind)} ${s.number}` }}
          </button>
        </div>

        <h2 v-if="season" class="sec-label mb-6">
          <span class="idx">{{ String(season.number).padStart(2, '0') }}</span>
          {{ season.title || `${seasonLabel(data.collection.kind)} ${season.number}` }}
        </h2>

        <ol v-if="season" class="space-y-3">
          <li v-for="m in season.media" :key="m.id" class="card flex gap-5 p-4 sm:items-center">
            <span class="w-8 shrink-0 pt-1 text-sm font-bold tabular-nums text-accent sm:pt-0">
              {{ String(m.position).padStart(2, '0') }}
            </span>
            <div class="poster-frame hidden w-48 shrink-0 sm:block">
              <img v-if="m.thumbnail_url" :src="m.thumbnail_url" alt="" loading="lazy" class="h-full w-full object-cover" />
              <div v-else class="poster-fallback h-full" />
              <div v-if="progressOf(m)" class="absolute inset-x-2 bottom-2">
                <ProgressBar :position="progressOf(m)!.position" :duration="m.duration_seconds" :completed="progressOf(m)!.completed" />
              </div>
            </div>
            <div class="min-w-0 flex-1">
              <p class="font-semibold">{{ m.title }}</p>
              <p v-if="m.synopsis" class="mt-1 line-clamp-2 text-sm text-muted-fg">{{ m.synopsis }}</p>
              <p class="mt-1 text-xs text-fg-faint">{{ formatDuration(m.duration_seconds) }}</p>
            </div>
            <RouterLink :to="`/assistir/${m.id}`" class="btn btn-primary sm shrink-0" :aria-label="`Assistir ${m.title}`">
              {{ progressOf(m)?.completed ? 'Rever' : progressOf(m)?.position ? 'Continuar' : 'Assistir' }}
            </RouterLink>
          </li>
        </ol>
      </div>
    </template>

    <div v-else-if="!error" class="wrap mt-10 space-y-3">
      <div class="tile !aspect-auto h-72" />
      <div v-for="n in 3" :key="n" class="tile !aspect-auto h-24" />
    </div>
  </main>
</template>
