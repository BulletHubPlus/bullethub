<script setup lang="ts">
defineProps<{ loading?: boolean }>()
</script>

<template>
  <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading || undefined">
    <slot />
    <span aria-hidden="true">→</span>
  </button>
</template>
