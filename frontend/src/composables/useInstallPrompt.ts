import { ref } from 'vue'

/** Chrome/Edge/Android fire `beforeinstallprompt`; iOS Safari needs "Compartilhar → Adicionar à Tela de Início". */
interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const deferred = ref<BeforeInstallPromptEvent | null>(null)
const installed = ref(window.matchMedia('(display-mode: standalone)').matches)

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  deferred.value = e as BeforeInstallPromptEvent
})
window.addEventListener('appinstalled', () => {
  installed.value = true
  deferred.value = null
})

export function useInstallPrompt() {
  const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent)

  async function install() {
    if (!deferred.value) return
    await deferred.value.prompt()
    await deferred.value.userChoice
    deferred.value = null
  }

  return { canPrompt: deferred, installed, isIOS, install }
}
