<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import UserAvatar from '@/components/ui/UserAvatar.vue'
import Icon from '@/components/ui/Icon.vue'

const auth = useAuthStore()
const router = useRouter()
const open = ref(false)
const root = ref<HTMLElement | null>(null)

const firstName = computed(() => auth.user?.name?.trim().split(/\s+/)[0] ?? 'Conta')

function close() {
  open.value = false
}
function onDocClick(e: MouseEvent) {
  if (root.value && !root.value.contains(e.target as Node)) close()
}
function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}
async function logout() {
  close()
  await auth.logout()
  await router.push({ name: 'login' })
}

onMounted(() => {
  document.addEventListener('click', onDocClick)
  document.addEventListener('keydown', onKey)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
  document.removeEventListener('keydown', onKey)
})
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="group flex items-center gap-2.5 rounded-full border border-line py-1 pl-1 pr-2.5 transition hover:border-fg-faint"
      :class="open && '!border-[var(--accent-dim)]'"
      :aria-expanded="open"
      aria-haspopup="menu"
      aria-label="Menu da conta"
      @click="open = !open"
    >
      <UserAvatar :name="auth.user?.name" :email="auth.user?.email" :size="28" />
      <span class="hidden text-left leading-tight sm:block">
        <span class="block text-[13px] font-semibold">{{ firstName }}</span>
        <span class="block text-[10px] font-bold uppercase tracking-[0.16em] text-fg-faint">Assinante</span>
      </span>
      <Icon name="chevron" :size="14" class="text-fg-faint transition group-hover:text-fg" :class="open && 'rotate-180'" />
    </button>

    <Transition name="menu">
      <div
        v-if="open"
        class="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-line bg-surface shadow-2xl"
        role="menu"
      >
        <!-- header strip -->
        <div class="relative overflow-hidden px-4 py-3.5">
          <div class="absolute inset-0 bg-gradient-to-r from-[var(--accent-faint)] to-transparent" aria-hidden="true" />
          <div class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-accent via-[var(--accent-faint)] to-transparent" aria-hidden="true" />
          <div class="relative flex items-center gap-3">
            <UserAvatar :name="auth.user?.name" :email="auth.user?.email" :size="40" />
            <div class="min-w-0">
              <p class="text-[10px] font-bold uppercase tracking-[0.18em] text-accent">Conta</p>
              <p class="truncate text-sm font-semibold">{{ auth.user?.name }}</p>
              <p class="truncate text-xs text-fg-faint">{{ auth.user?.email }}</p>
            </div>
          </div>
        </div>

        <nav class="border-t border-line p-1.5 text-sm">
          <RouterLink to="/conta" class="menu-item" role="menuitem" @click="close">
            <Icon name="user" :size="16" /> Minha conta
          </RouterLink>
          <RouterLink to="/conta/dispositivos" class="menu-item" role="menuitem" @click="close">
            <Icon name="devices" :size="16" /> Dispositivos
          </RouterLink>
          <button type="button" class="menu-item w-full text-left text-accent-hi" role="menuitem" @click="logout">
            <Icon name="logout" :size="16" /> Sair
          </button>
        </nav>

        <!-- footer strip -->
        <div class="flex items-center justify-center border-t border-line bg-gradient-to-r from-[var(--accent-faint)] to-transparent py-1.5">
          <span class="text-[9px] font-bold uppercase tracking-[0.2em] text-fg-faint">bullethub</span>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.menu-item {
  display: flex;
  align-items: center;
  gap: 11px;
  border-radius: 8px;
  padding: 9px 11px;
  color: var(--color-muted-fg, #bcbcbc);
  transition: background 0.15s;
}
.menu-item:hover {
  background: var(--color-surface-2, #1c2027);
  color: #fff;
}
.menu-enter-active,
.menu-leave-active {
  transition:
    opacity 0.14s ease,
    transform 0.14s ease;
}
.menu-enter-from,
.menu-leave-to {
  opacity: 0;
  transform: translateY(-6px) scale(0.98);
}
</style>
