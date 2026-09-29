<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, ApiError } from '@/api/client'
import type { Device } from '@/api/types'
import AppHeader from '@/components/shell/AppHeader.vue'
import FormAlert from '@/components/ui/FormAlert.vue'

const devices = ref<Device[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

async function load() {
  loading.value = true
  try {
    devices.value = (await api.get<{ devices: Device[] }>('/api/me/devices')).devices
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Erro ao carregar dispositivos.'
  } finally {
    loading.value = false
  }
}

async function revoke(device: Device) {
  if (!confirm(`Desconectar "${device.name}"?`)) return
  try {
    await api.del(`/api/me/devices/${device.id}`)
    devices.value = devices.value.filter((d) => d.id !== device.id)
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Erro ao desconectar.'
  }
}

const fmt = (iso: string | null) =>
  iso ? new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(iso)) : '-'

onMounted(load)
</script>

<template>
  <AppHeader />
  <main class="glow-top pb-24">
    <div class="wrap max-w-[860px]">
      <header class="fade-in pt-20 pb-12">
        <p class="page-kicker">Conta</p>
        <h1 class="display mt-6 text-5xl sm:text-6xl">Dispositivos<span class="accent">.</span></h1>
        <p class="lede mt-4 max-w-[50ch]">
          Onde sua conta está conectada. Desconecte qualquer dispositivo que você não reconheça. Ele sai na hora.
        </p>
      </header>

      <FormAlert v-if="error" class="mb-6">{{ error }}</FormAlert>

      <h2 class="sec-label mb-5"><span class="idx">{{ String(devices.length).padStart(2, '0') }}</span>Conectados</h2>

      <div v-if="loading" class="space-y-3">
        <div v-for="n in 2" :key="n" class="tile !aspect-auto h-[76px]" />
      </div>

      <ul v-else class="space-y-3">
        <li
          v-for="d in devices"
          :key="d.id"
          class="card flex items-center gap-5 px-6 py-5"
          :class="{ 'card-accent': d.current }"
        >
          <div class="min-w-0 flex-1">
            <p class="flex items-center gap-3 font-semibold">
              {{ d.name }}
              <span v-if="d.current" class="kicker !text-[10.5px]">Este dispositivo</span>
            </p>
            <p class="mt-1 truncate text-[13px] text-fg-faint">Último acesso · {{ fmt(d.last_seen_at) }}</p>
          </div>
          <button v-if="!d.current" type="button" class="btn btn-quiet sm" @click="revoke(d)">Desconectar</button>
        </li>
      </ul>
    </div>
  </main>
</template>
