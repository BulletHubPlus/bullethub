<script setup lang="ts">
import { ref, watch } from 'vue'
import { api } from '@/api/client'

const props = defineProps<{ kind: 'collection' | 'movie'; id: string; inList: boolean }>()
const saved = ref(props.inList)
const busy = ref(false)

watch(() => props.inList, (v) => (saved.value = v))

// Optimistic toggle; reverts on failure.
async function toggle() {
  busy.value = true
  const next = !saved.value
  saved.value = next
  try {
    const path = `/api/me/list/${props.kind}/${props.id}`
    await (next ? api.put(path) : api.del(path))
  } catch {
    saved.value = !next
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <button type="button" class="btn btn-quiet" :aria-pressed="saved" :disabled="busy" @click="toggle">
    <span aria-hidden="true">{{ saved ? '✓' : '+' }}</span>
    {{ saved ? 'Na minha lista' : 'Minha lista' }}
  </button>
</template>
