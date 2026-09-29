<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ position: number; duration: number | null | undefined; completed?: boolean }>()
const pct = computed(() =>
  props.completed ? 100 : props.duration ? Math.min(100, Math.max(2, (props.position / props.duration) * 100)) : 0,
)
</script>

<template>
  <div class="h-[3px] w-full overflow-hidden rounded-full bg-white/15" role="progressbar" :aria-valuenow="Math.round(pct)" aria-valuemin="0" aria-valuemax="100">
    <div class="h-full bg-accent" :style="{ width: `${pct}%` }" />
  </div>
</template>
