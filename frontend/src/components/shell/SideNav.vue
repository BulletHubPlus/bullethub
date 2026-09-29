<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/api/client'
import type { Genre } from '@/api/types'
import Icon from '@/components/ui/Icon.vue'
import BrandLink from '@/components/shell/BrandLink.vue'

const open = defineModel<boolean>({ required: true })
const route = useRoute()
const panel = ref<HTMLElement | null>(null)
const genres = ref<Genre[]>([])
let loaded = false

const primary = [
  { to: '/', label: 'Início', exact: true },
  { to: '/tipo/series', label: 'Séries' },
  { to: '/tipo/animes', label: 'Animes' },
  { to: '/tipo/filmes', label: 'Filmes' },
  { to: '/buscar', label: 'Buscar' },
]

function close() {
  open.value = false
}
function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}
const isActive = (to: string, exact?: boolean) => (exact ? route.path === '/' : route.path.startsWith(to))

watch(open, async (isOpen) => {
  document.body.style.overflow = isOpen ? 'hidden' : ''
  if (isOpen) {
    document.addEventListener('keydown', onKey)
    panel.value?.focus()
    if (!loaded) {
      loaded = true
      try {
        genres.value = (await api.get<{ genres: Genre[] }>('/api/catalog/genres?scope=all')).genres
      } catch {
        loaded = false
      }
    }
  } else {
    document.removeEventListener('keydown', onKey)
  }
})
watch(() => route.fullPath, close)
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKey)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <Transition name="scrim">
      <div v-if="open" class="fixed inset-0 z-[60] bg-black/50" @click="close" />
    </Transition>
    <Transition name="drawer">
      <aside
        v-if="open"
        ref="panel"
        tabindex="-1"
        role="navigation"
        aria-label="Menu"
        class="drawer fixed inset-y-0 left-0 z-[61] flex w-[76%] max-w-[280px] flex-col outline-none"
      >
        <!-- top: logo + close -->
        <div class="flex items-center justify-between px-6 pt-5 pb-1">
          <BrandLink />
          <button
            type="button"
            class="grid size-8 place-items-center rounded-full text-fg-faint transition hover:bg-white/5 hover:text-fg"
            aria-label="Fechar menu"
            @click="close"
          >
            <Icon name="close" :size="18" />
          </button>
        </div>

        <nav class="flex-1 overflow-y-auto px-6 pt-5 pb-8">
          <!-- categories: large, typographic, active = accent -->
          <ul class="space-y-1">
            <li v-for="item in primary" :key="item.to">
              <RouterLink
                :to="item.to"
                class="cat-link"
                :class="{ 'is-active': isActive(item.to, item.exact) }"
              >
                {{ item.label }}
              </RouterLink>
            </li>
          </ul>

          <!-- divider + subcategories (genres): medium, muted, no chrome -->
          <template v-if="genres.length">
            <div class="mt-7 mb-4 flex items-center gap-3">
              <span class="text-[10px] font-bold uppercase tracking-[0.2em] text-fg-faint">Gêneros</span>
              <span class="h-px flex-1 bg-gradient-to-r from-line to-transparent" />
            </div>
            <ul class="space-y-0.5">
              <li v-for="g in genres" :key="g.slug">
                <RouterLink
                  :to="{ name: 'search', query: { genero: g.slug } }"
                  class="genre-link"
                  :class="{ 'is-active': route.query.genero === g.slug }"
                >
                  {{ g.name }}
                </RouterLink>
              </li>
            </ul>
          </template>
        </nav>
      </aside>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* dark panel with a soft protection gradient fading into the content on the right */
.drawer {
  background: linear-gradient(90deg, #0a0a0b 0%, #0a0a0b 78%, rgba(6, 6, 6, 0.92) 100%);
  border-right: 1px solid var(--color-line, #2a2f38);
}

.cat-link {
  display: block;
  padding: 5px 0;
  font-family: var(--font-display, 'Bricolage Grotesque'), sans-serif;
  font-size: 23px;
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.15;
  color: rgba(255, 255, 255, 0.6);
  transition: color 0.15s;
}
.cat-link:hover {
  color: #fff;
}
.cat-link.is-active {
  color: #fff;
}
.cat-link.is-active::before {
  content: '';
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-right: 10px;
  vertical-align: middle;
  background: var(--color-accent, #f20024);
  transform: rotate(45deg);
}

.genre-link {
  display: block;
  padding: 5px 0;
  font-size: 14px;
  font-weight: 500;
  color: var(--color-muted-fg, #9aa3b2);
  transition: color 0.15s;
}
.genre-link:hover,
.genre-link.is-active {
  color: #fff;
}

.scrim-enter-active,
.scrim-leave-active {
  transition: opacity 0.2s ease;
}
.scrim-enter-from,
.scrim-leave-to {
  opacity: 0;
}
.drawer-enter-active,
.drawer-leave-active {
  transition: transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
}
.drawer-enter-from,
.drawer-leave-to {
  transform: translateX(-100%);
}
</style>
