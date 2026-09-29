<script setup lang="ts">
import { computed } from 'vue'
import type { TitleMetadata } from '@/api/types'
import { kindLabel } from '@/utils/format'
import TitleMeta from './TitleMeta.vue'

/**
 * Detail-page hero: wide backdrop fading into black, vertical poster on the
 * left (desktop), then the ficha técnica. Actions go in the default slot.
 */
const props = defineProps<{
  title: TitleMetadata & { title: string; kind: string; thumbnail_url?: string | null; cast?: string[]; creators?: string[] }
  synopsis?: string | null
  extra?: string | null
  durationSeconds?: number | null
}>()

const backdrop = computed(() => props.title.backdrop_url || props.title.thumbnail_url || null)
const creatorsLabel = computed(() => (props.title.kind === 'anime' ? 'Estúdio' : props.title.kind === 'movie' ? 'Direção' : 'Criação'))
</script>

<template>
  <section class="relative overflow-hidden border-b border-border">
    <img v-if="backdrop" :src="backdrop" alt="" class="absolute inset-0 h-full w-full object-cover opacity-45" />
    <div v-else class="poster-fallback absolute inset-0" />
    <div class="absolute inset-0 bg-gradient-to-r from-bg via-bg/85 to-bg/20" />
    <div class="absolute inset-0 bg-gradient-to-t from-bg to-transparent" />

    <div class="wrap fade-in relative grid gap-10 py-20 md:grid-cols-[220px_minmax(0,1fr)] md:items-end">
      <div class="hidden md:block">
        <div class="overflow-hidden rounded-[var(--radius)] border border-border shadow-2xl" style="aspect-ratio: 2 / 3">
          <img v-if="title.poster_url" :src="title.poster_url" :alt="`Pôster de ${title.title}`" class="h-full w-full object-cover" />
          <div v-else class="poster-fallback flex h-full items-end p-5">
            <span class="display text-2xl leading-tight">{{ title.title }}</span>
          </div>
        </div>
      </div>

      <div class="min-w-0">
        <p class="page-kicker">{{ kindLabel[title.kind] }}</p>
        <h1 class="display mt-5 max-w-[16ch] text-5xl sm:text-7xl">{{ title.title }}</h1>
        <p v-if="title.original_title && title.original_title !== title.title" class="mt-3 text-sm italic text-fg-faint">
          {{ title.original_title }}
        </p>
        <TitleMeta :title="title" :extra="extra" :duration-seconds="durationSeconds" link-genres class="mt-5" />
        <p v-if="synopsis" class="lede mt-5 max-w-[60ch]">{{ synopsis }}</p>

        <div class="mt-8 flex flex-wrap items-center gap-3">
          <slot />
        </div>

        <dl v-if="title.cast?.length || title.creators?.length" class="mt-8 grid max-w-[70ch] gap-2 text-sm">
          <div v-if="title.cast?.length" class="flex gap-3">
            <dt class="shrink-0 text-fg-faint">Elenco</dt>
            <dd class="text-muted-fg">{{ title.cast.join(', ') }}</dd>
          </div>
          <div v-if="title.creators?.length" class="flex gap-3">
            <dt class="shrink-0 text-fg-faint">{{ creatorsLabel }}</dt>
            <dd class="text-muted-fg">{{ title.creators.join(', ') }}</dd>
          </div>
        </dl>
      </div>
    </div>
  </section>
</template>
