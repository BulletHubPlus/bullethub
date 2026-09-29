<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ name?: string | null; email?: string | null; size?: number }>()

const initials = computed(() => {
  const n = props.name?.trim()
  if (n) {
    const p = n.split(/\s+/)
    return (p[0][0] + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase()
  }
  return (props.email?.[0] ?? '?').toUpperCase()
})
</script>

<template>
  <span
    class="grid shrink-0 place-items-center rounded-full font-bold leading-none text-white"
    :style="{
      width: `${size ?? 36}px`,
      height: `${size ?? 36}px`,
      fontSize: `${(size ?? 36) * 0.36}px`,
      background: 'radial-gradient(120% 120% at 30% 20%, #f6121d, #8f0510)',
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.14)',
    }"
    aria-hidden="true"
  >
    {{ initials }}
  </span>
</template>
