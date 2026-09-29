<script setup lang="ts">
import { ref } from 'vue'
import BrandLink from '@/components/shell/BrandLink.vue'
import UserMenu from '@/components/shell/UserMenu.vue'
import SideNav from '@/components/shell/SideNav.vue'
import Icon from '@/components/ui/Icon.vue'

const navOpen = ref(false)
</script>

<template>
  <nav class="site-nav" aria-label="Principal">
    <div class="wrap flex h-[72px] items-center gap-3 sm:gap-5">
      <button
        type="button"
        class="grid size-10 shrink-0 place-items-center rounded-lg text-fg-faint transition hover:bg-surface-2 hover:text-fg"
        aria-label="Abrir menu"
        :aria-expanded="navOpen"
        @click="navOpen = true"
      >
        <Icon name="menu" :size="22" />
      </button>
      <BrandLink variant="mark" />
      <div class="ml-auto flex items-center gap-2 sm:gap-3">
        <RouterLink
          to="/buscar"
          class="grid size-10 place-items-center rounded-lg text-fg-faint transition hover:bg-surface-2 hover:text-fg"
          aria-label="Buscar"
          active-class="!text-fg"
        >
          <Icon name="search" :size="20" />
        </RouterLink>
        <UserMenu />
      </div>
    </div>
    <SideNav v-model="navOpen" />
  </nav>
</template>
