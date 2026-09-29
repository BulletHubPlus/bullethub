<script setup lang="ts">
defineProps<{ kind?: 'error' | 'success' }>()
</script>

<template>
  <div role="alert" class="notice" :class="{ 'is-success': kind === 'success' }">
    <div><slot /></div>
  </div>
</template>
