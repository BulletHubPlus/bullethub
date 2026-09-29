<script setup lang="ts">
import { useAuthStore } from '@/stores/auth'
import HomeView from './HomeView.vue'
import LandingView from './LandingView.vue'

// "/" is the public landing page for visitors and the catalog home for subscribers.
const auth = useAuthStore()
</script>

<template>
  <HomeView v-if="auth.isAuthenticated" />
  <LandingView v-else />
</template>
