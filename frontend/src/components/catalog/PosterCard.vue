<script setup lang="ts">
import { computed } from 'vue'
import type { CatalogCard } from '@/api/types'
import { formatDuration, kindLabel } from '@/utils/format'
import { useProgressStore } from '@/stores/progress'
import ProgressBar from './ProgressBar.vue'

const props = defineProps<{ item: CatalogCard }>()

// Bunny Optimizer resizes on the fly; other hosts get the URL untouched.
const thumb = computed(() => {
  const url = props.item.thumbnail_url || props.item.backdrop_url
  return url && url.includes('.b-cdn.net/') ? `${url}?width=640` : url
})

const progressStore = useProgressStore()

const to = computed(() => {
  if (props.item.type === 'progress') return `/assistir/${props.item.id}`
  return props.item.type === 'collection' ? `/titulo/${props.item.slug}` : `/filme/${props.item.id}`
})

const progress = computed(() =>
  props.item.type === 'progress'
    ? progressStore.get(props.item.id, { position: props.item.position ?? 0, completed: false })
    : null,
)
</script>

<template>
  <RouterLink :to="to" class="poster group block focus-visible:outline-offset-4">
    <div class="poster-frame">
      <img
        v-if="item.thumbnail_url"
        :src="thumb!"
        :alt="item.title"
        loading="lazy"
        class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.04]"
      />
      <div v-else class="poster-fallback flex h-full flex-col justify-between p-4">
        <span class="kicker !text-[10px]">{{ kindLabel[item.kind] }}</span>
        <span class="display text-2xl leading-tight">{{ item.title }}</span>
      </div>
      <div v-if="progress" class="absolute inset-x-3 bottom-3">
        <ProgressBar :position="progress.position" :duration="item.duration_seconds" :completed="progress.completed" />
      </div>
    </div>
    <p v-if="item.subtitle" class="mt-3 truncate text-xs font-semibold uppercase tracking-[0.12em] text-fg-faint">{{ item.subtitle }}</p>
    <p class="truncate text-sm font-semibold" :class="item.subtitle ? 'mt-0.5' : 'mt-3'">{{ item.title }}</p>
    <p class="mt-0.5 text-xs text-fg-faint">
      {{ kindLabel[item.kind] }}<template v-if="item.release_year"> · {{ item.release_year }}</template
      ><template v-if="item.duration_seconds"> · {{ formatDuration(item.duration_seconds) }}</template>
    </p>
  </RouterLink>
</template>
