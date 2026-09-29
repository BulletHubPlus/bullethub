<script setup lang="ts">
import BrandLink from '@/components/shell/BrandLink.vue'
import bg from '@/assets/login-bg.webp'

defineProps<{ kicker?: string; title: string; subtitle?: string }>()
</script>

<template>
  <div class="grid min-h-dvh lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
    <main class="glow-top flex flex-col px-5 py-8 sm:px-12">
      <BrandLink />

      <div class="fade-in my-auto w-full max-w-[400px] py-12 lg:mx-0 mx-auto">
        <p v-if="kicker" class="page-kicker">{{ kicker }}</p>
        <h1 class="display mt-5 text-[2.5rem] sm:text-5xl">{{ title }}</h1>
        <p v-if="subtitle" class="lede mt-4">{{ subtitle }}</p>

        <div class="mt-10">
          <slot />
        </div>

        <div class="mt-8 border-t border-border pt-6 text-sm text-muted-fg">
          <slot name="footer" />
        </div>
      </div>

      <p class="text-xs text-fg-faint">© {{ new Date().getFullYear() }} bullethub</p>
    </main>

    <aside class="relative hidden overflow-hidden border-l border-border lg:block" aria-hidden="true">
      <div class="absolute inset-0 scale-105 bg-cover bg-center opacity-40 grayscale-[35%]" :style="{ backgroundImage: `url(${bg})` }" />
      <div class="absolute inset-0 bg-gradient-to-r from-bg via-bg/70 to-bg/30" />
      <div class="absolute inset-0 bg-gradient-to-t from-bg via-transparent to-bg/60" />
      <div class="absolute inset-x-0 bottom-0 p-14">
        <p class="sec-label"><span class="idx">01</span>Streaming</p>
        <p class="display mt-6 max-w-[14ch] text-6xl">
          Continue de onde <span class="accent">parou.</span>
        </p>
        <p class="lede mt-5 max-w-[42ch]">
          Seu progresso sincroniza entre dispositivos em tempo real.
        </p>
      </div>
    </aside>
  </div>
</template>
