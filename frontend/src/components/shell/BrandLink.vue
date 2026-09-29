<script setup lang="ts">
import mark from '@/assets/logo-mark.webp'

/**
 * Two brand treatments:
 *  - `mark` (logged-in shell): just the logo symbol.
 *  - `wordmark` (logged-out: landing, auth): the classic "bullethub." wordmark.
 * The mark image has a black background; `screen` blending drops it on dark surfaces.
 */
withDefaults(defineProps<{ variant?: 'mark' | 'wordmark'; size?: 'sm' | 'md' }>(), {
  variant: 'wordmark',
  size: 'md',
})
</script>

<template>
  <RouterLink to="/" class="inline-flex items-center" aria-label="bullethub, início">
    <img
      v-if="variant === 'mark'"
      :src="mark"
      alt="bullethub"
      class="mix-blend-screen"
      :class="size === 'sm' ? 'h-7' : 'h-9'"
    />
    <span v-else class="wordmark" :class="{ '!text-lg': size === 'sm' }">bullethub<span class="dot">.</span></span>
  </RouterLink>
</template>
