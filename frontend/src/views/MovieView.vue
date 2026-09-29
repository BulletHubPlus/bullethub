<script setup lang="ts">
import { ref, watch } from 'vue'
import { api, ApiError } from '@/api/client'
import type { MediaItem, TitleDetails } from '@/api/types'
import AppHeader from '@/components/shell/AppHeader.vue'
import FormAlert from '@/components/ui/FormAlert.vue'
import TitleHero from '@/components/catalog/TitleHero.vue'
import MyListButton from '@/components/catalog/MyListButton.vue'

type Movie = MediaItem & TitleDetails & { kind: 'movie' }

const props = defineProps<{ id: string }>()
const media = ref<Movie | null>(null)
const error = ref<string | null>(null)

watch(
  () => props.id,
  async (id) => {
    media.value = null
    error.value = null
    try {
      media.value = (await api.get<{ media: Movie }>(`/api/catalog/movies/${encodeURIComponent(id)}`)).media
    } catch (e) {
      error.value = e instanceof ApiError && e.status === 404 ? 'Filme não encontrado.' : 'Erro ao carregar.'
    }
  },
  { immediate: true },
)
</script>

<template>
  <AppHeader />
  <main class="pb-24">
    <FormAlert v-if="error" class="wrap mt-10">{{ error }}</FormAlert>
    <TitleHero v-if="media" :title="media" :synopsis="media.synopsis" :duration-seconds="media.duration_seconds">
      <RouterLink :to="`/assistir/${media.id}`" class="btn btn-primary">
        {{ media.progress && !media.progress.completed && media.progress.position ? 'Continuar' : 'Assistir' }}
        <span aria-hidden="true">→</span>
      </RouterLink>
      <MyListButton kind="movie" :id="media.id" :in-list="media.in_my_list" />
    </TitleHero>
    <div v-else-if="!error" class="tile !aspect-auto h-[60vh] rounded-none" />
  </main>
</template>
