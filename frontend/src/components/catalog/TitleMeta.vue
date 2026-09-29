<script setup lang="ts">
import type { TitleMetadata } from '@/api/types'
import { formatDuration } from '@/utils/format'

/** "2024 · [14] · 2 temporadas · Ação, Drama" - ClassInd colours are the official ones. */
defineProps<{ title: TitleMetadata; extra?: string | null; durationSeconds?: number | null; linkGenres?: boolean }>()

const ratingClass: Record<string, string> = {
  L: 'bg-[#0c9447]',
  '10': 'bg-[#0f7dc2]',
  '12': 'bg-[#f8c411] text-black',
  '14': 'bg-[#e67824]',
  '16': 'bg-[#db2827]',
  '18': 'bg-black ring-1 ring-white/40',
}
</script>

<template>
  <p class="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm text-muted-fg">
    <span v-if="title.release_year" class="tabular-nums">{{ title.release_year }}</span>
    <span
      v-if="title.age_rating"
      class="inline-grid h-6 min-w-6 place-items-center rounded px-1 text-xs font-bold text-white"
      :class="ratingClass[title.age_rating]"
      :title="title.age_rating === 'L' ? 'Livre para todos os públicos' : `Não recomendado para menores de ${title.age_rating} anos`"
    >
      {{ title.age_rating }}
    </span>
    <span v-if="durationSeconds">{{ formatDuration(durationSeconds) }}</span>
    <span v-if="extra">{{ extra }}</span>
    <template v-if="title.genres?.length">
      <span class="text-fg-faint" aria-hidden="true">·</span>
      <template v-if="linkGenres">
        <RouterLink
          v-for="g in title.genres"
          :key="g.slug"
          :to="{ name: 'search', query: { genero: g.slug } }"
          class="hover:text-fg hover:underline"
        >
          {{ g.name }}
        </RouterLink>
      </template>
      <span v-else>{{ title.genres.map((g) => g.name).join(', ') }}</span>
    </template>
  </p>
</template>
