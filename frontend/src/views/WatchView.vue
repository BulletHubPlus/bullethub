<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { Channel } from 'phoenix'
import { api, ApiError, getAccessToken } from '@/api/client'
import type { ActiveSession, PlaybackSession } from '@/api/types'
import { getSocket } from '@/composables/useUserChannel'
import { createEngine, type PlayerEngine } from '@/engines/PlayerEngine'
import WatermarkLayer from '@/components/player/WatermarkLayer.vue'

const props = defineProps<{ id: string }>()
const router = useRouter()

type State = 'loading' | 'playing' | 'limit' | 'paywall' | 'unconfirmed' | 'terminated' | 'tampered' | 'error'

const state = ref<State>('loading')
const errorMessage = ref('')
const session = ref<PlaybackSession | null>(null)
const activeSessions = ref<ActiveSession[]>([])
const stage = ref<HTMLDivElement | null>(null)
const surface = ref<HTMLDivElement | null>(null)
const engine = shallowRef<PlayerEngine | null>(null)
const position = ref(0)
const playing = ref(false)
const chromeVisible = ref(true)
const nextCountdown = ref<number | null>(null)

let channel: Channel | null = null
let progressTimer: number | undefined
let countdownTimer: number | undefined
let idleTimer: number | undefined
let playStartedAt: number | null = null
let ttffSent = false

const media = computed(() => session.value?.media ?? null)
const next = computed(() => session.value?.next_media ?? null)
const backTo = computed(() => (media.value?.collection ? `/titulo/${media.value.collection.slug}` : '/'))
const showSkipIntro = computed(() => {
  const end = media.value?.intro_end_seconds
  return !!end && position.value > 1 && position.value < end
})
const resend = ref<'idle' | 'sending' | 'sent' | 'error'>('idle')
const isLocalhost = ['localhost', '127.0.0.1'].includes(window.location.hostname)

async function resendConfirmation() {
  resend.value = 'sending'
  try {
    await api.post('/api/auth/confirm/resend')
    resend.value = 'sent'
  } catch (e) {
    // Already confirmed in another tab: just try to play.
    if (e instanceof ApiError && e.code === 'already_confirmed') return void start()
    resend.value = 'error'
  }
}

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

// ── session lifecycle ────────────────────────────────────────────────

async function start() {
  teardown()
  state.value = 'loading'
  try {
    session.value = await api.post<PlaybackSession>('/api/playback/sessions', { media_id: props.id })
    state.value = 'playing'
    // The stage is rendered by v-if on 'playing'; wait a tick for the element.
    await new Promise((r) => requestAnimationFrame(r))
    await mountPlayer()
  } catch (e) {
    if (!(e instanceof ApiError)) return fail('Não foi possível iniciar a reprodução.')
    if (e.code === 'stream_limit') {
      activeSessions.value = (e.details.active_sessions as ActiveSession[]) ?? []
      state.value = 'limit'
    } else if (e.code === 'subscription_required') state.value = 'paywall'
    else if (e.code === 'email_unconfirmed') state.value = 'unconfirmed'
    else fail(e.status === 404 ? 'Título indisponível.' : e.message)
  }
}

async function mountPlayer() {
  const s = session.value!
  const eng = await createEngine(s.source.engine)
  engine.value = eng

  eng.on('play', () => {
    playing.value = true
    playStartedAt ??= performance.now()
  })
  eng.on('pause', () => {
    playing.value = false
    pushProgress()
  })
  eng.on('timeupdate', ({ seconds }) => {
    position.value = seconds
    if (!ttffSent && playStartedAt !== null && seconds > 0) {
      ttffSent = true
      api.beacon('/api/telemetry', { events: [{ kind: 'ttff', ms: Math.round(performance.now() - playStartedAt), engine: s.source.engine }] })
    }
  })
  eng.on('ended', onEnded)
  eng.on('error', () => fail('Erro na reprodução. Tente de novo.'))

  joinChannel(s.session_id)
  await eng.mount(surface.value!, s.source.url, { captions: await loadCaptions(s) })
  if (s.resume_position > 0) eng.seek(s.resume_position)
  eng.play()

  progressTimer = window.setInterval(() => playing.value && pushProgress(), 10_000)
}

// <track> can't send the bearer token, so the VTT is fetched through the API and
// handed over as a blob: URL. Only the native engine uses these.
let captionUrls: string[] = []
async function loadCaptions(s: PlaybackSession) {
  if (s.source.engine !== 'native' || !s.captions.length) return []
  const tracks = await Promise.all(
    s.captions.map(async (c) => {
      const res = await fetch(`/api/captions/${c.id}`, { headers: { authorization: `Bearer ${getAccessToken()}` } })
      if (!res.ok) return null
      const src = URL.createObjectURL(new Blob([await res.text()], { type: 'text/vtt' }))
      captionUrls.push(src)
      return { srclang: c.srclang, label: c.label, src }
    }),
  )
  return tracks.filter((t) => t !== null)
}

function joinChannel(sessionId: string) {
  const socket = getSocket()
  if (!socket) return fail('Sem conexão em tempo real. Recarregue a página.')

  channel = socket.channel(`playback:${sessionId}`, {})
  channel.on('session_terminated', () => {
    engine.value?.pause()
    teardown(false)
    state.value = 'terminated'
  })
  channel
    .join()
    .receive('error', () => fail('Sessão de reprodução inválida. Tente de novo.'))
}

function pushProgress() {
  if (channel && position.value > 0) channel.push('progress', { position: Math.floor(position.value) })
}

function teardown(sendProgress = true) {
  if (sendProgress) pushProgress()
  window.clearInterval(progressTimer)
  window.clearInterval(countdownTimer)
  nextCountdown.value = null
  channel?.leave()
  channel = null
  engine.value?.destroy()
  engine.value = null
  captionUrls.forEach((u) => URL.revokeObjectURL(u))
  captionUrls = []
  playing.value = false
  playStartedAt = null
  ttffSent = false
}

function fail(message: string) {
  teardown(false)
  errorMessage.value = message
  state.value = 'error'
}

// ── RF07: free a screen ─────────────────────────────────────────────

async function endOther(id: string) {
  await api.del(`/api/playback/sessions/${id}`)
  await start()
}

// ── RF04: autoplay next ─────────────────────────────────────────────

function onEnded() {
  playing.value = false
  pushProgress()
  if (!next.value) return
  nextCountdown.value = 10
  countdownTimer = window.setInterval(() => {
    if (nextCountdown.value === null) return
    nextCountdown.value -= 1
    if (nextCountdown.value <= 0) playNext()
  }, 1000)
}

function playNext() {
  window.clearInterval(countdownTimer)
  nextCountdown.value = null
  if (next.value) router.replace(`/assistir/${next.value.id}`)
}

function cancelNext() {
  window.clearInterval(countdownTimer)
  nextCountdown.value = null
}

function skipIntro() {
  if (media.value?.intro_end_seconds) engine.value?.seek(media.value.intro_end_seconds)
}

// ── watermark tampering (RF14) ──────────────────────────────────────

function onTampered(detail: string) {
  engine.value?.pause()
  channel?.push('event', { kind: 'watermark_tampered', detail })
  teardown(false)
  state.value = 'tampered'
}

// ── chrome: fullscreen of the wrapper (video + watermark), idle hide ─

function toggleFullscreen() {
  if (document.fullscreenElement) void document.exitFullscreen()
  else void stage.value?.requestFullscreen()
}

function poke() {
  chromeVisible.value = true
  window.clearTimeout(idleTimer)
  idleTimer = window.setTimeout(() => (chromeVisible.value = !playing.value), 2500)
}

function onPageHide() {
  if (media.value && position.value > 0) {
    api.beacon(`/api/progress/${media.value.id}`, { position: Math.floor(position.value) }, 'PUT')
  }
}

onMounted(() => {
  window.addEventListener('pagehide', onPageHide)
  void start()
})

watch(() => props.id, () => void start())

onBeforeUnmount(() => {
  window.removeEventListener('pagehide', onPageHide)
  window.clearTimeout(idleTimer)
  teardown()
})

const fmtTitle = computed(() => {
  const m = media.value
  if (!m) return ''
  if (m.kind === 'movie' || !m.collection) return m.title
  return `T${m.season_number}:E${m.position} · ${m.title}`
})
</script>

<template>
  <div class="min-h-dvh bg-black">
    <!-- player -->
    <div
      v-if="state === 'playing'"
      ref="stage"
      class="relative h-dvh w-full overflow-hidden bg-black"
      @mousemove="poke"
      @touchstart.passive="poke"
    >
      <div ref="surface" class="absolute inset-0" />
      <WatermarkLayer v-if="session" :text="session.watermark.text" @tampered="onTampered" />

      <!-- top bar -->
      <div
        class="pointer-events-none absolute inset-x-0 top-0 z-30 bg-gradient-to-b from-black/80 to-transparent px-5 pb-12 pt-5 transition-opacity duration-300 sm:px-8"
        :class="chromeVisible ? 'opacity-100' : 'opacity-0'"
      >
        <div class="pointer-events-auto flex items-center gap-4">
          <RouterLink :to="backTo" class="btn btn-quiet sm !border-white/20 !bg-black/40" aria-label="Voltar">←</RouterLink>
          <div class="min-w-0">
            <p v-if="media?.collection" class="truncate text-xs font-semibold uppercase tracking-[0.14em] text-fg-faint">
              {{ media.collection.title }}
            </p>
            <p class="truncate font-semibold">{{ fmtTitle }}</p>
          </div>
          <button type="button" class="btn btn-quiet sm ml-auto !border-white/20 !bg-black/40" @click="toggleFullscreen">
            Tela cheia
          </button>
        </div>
      </div>

      <!-- skip intro -->
      <button
        v-if="showSkipIntro"
        type="button"
        class="btn btn-primary absolute bottom-24 right-6 z-30 !bg-black/60 backdrop-blur"
        @click="skipIntro"
      >
        Pular abertura
      </button>

      <!-- next up -->
      <div
        v-if="nextCountdown !== null && next"
        class="card card-accent absolute bottom-24 right-6 z-30 w-80 p-5 shadow-2xl"
        role="status"
      >
        <p class="kicker !text-[10.5px]">
          A seguir<template v-if="!reducedMotion"> em {{ nextCountdown }}s</template>
        </p>
        <p class="mt-3 font-semibold">{{ next.title }}</p>
        <div class="mt-4 flex gap-3">
          <button type="button" class="btn btn-primary sm flex-1" @click="playNext">Assistir agora</button>
          <button type="button" class="btn btn-quiet sm" @click="cancelNext">Cancelar</button>
        </div>
      </div>
    </div>

    <!-- non-playing states -->
    <div v-else class="glow-top flex min-h-dvh items-center justify-center px-5">
      <div class="w-full max-w-lg">
        <RouterLink :to="backTo" class="btn-ghost block w-fit text-sm">← Voltar</RouterLink>

        <div v-if="state === 'loading'" class="mt-10 text-muted-fg">Preparando o vídeo…</div>

        <template v-else-if="state === 'limit'">
          <p class="page-kicker mt-10">Limite de telas</p>
          <h1 class="display mt-5 text-4xl">Todas as telas do seu plano estão em uso.</h1>
          <p class="lede mt-4">Encerre uma delas para assistir aqui.</p>
          <ul class="mt-8 space-y-3">
            <li v-for="s in activeSessions" :key="s.id" class="card flex items-center gap-4 p-4">
              <div class="min-w-0 flex-1">
                <p class="font-semibold">{{ s.device_name || 'Dispositivo' }}</p>
                <p class="truncate text-xs text-fg-faint">{{ s.media_title }}</p>
              </div>
              <button type="button" class="btn btn-primary sm" @click="endOther(s.id)">Encerrar esta tela</button>
            </li>
          </ul>
        </template>

        <template v-else-if="state === 'paywall'">
          <p class="page-kicker mt-10">Assinatura</p>
          <h1 class="display mt-5 text-4xl">Você ainda não tem um plano ativo.</h1>
          <p class="lede mt-4">O pagamento online chega em breve. Enquanto isso, fale com o suporte para liberar o acesso.</p>
        </template>

        <template v-else-if="state === 'unconfirmed'">
          <p class="page-kicker mt-10">Confirmação</p>
          <h1 class="display mt-5 text-4xl">Confirme seu e-mail para assistir.</h1>
          <p class="lede mt-4">Enviamos um link quando você criou a conta. Não achou? Reenvie abaixo e confira também o spam.</p>
          <div class="mt-8 flex flex-wrap items-center gap-4">
            <button type="button" class="btn btn-primary" :disabled="resend === 'sending'" @click="resendConfirmation">
              {{ resend === 'sent' ? 'Link reenviado' : 'Reenviar link' }}
            </button>
            <button v-if="resend === 'sent'" type="button" class="btn-ghost text-sm" @click="start">Já confirmei, assistir</button>
          </div>
          <p v-if="resend === 'error'" class="field-error mt-3">Não foi possível reenviar agora. Tente em instantes.</p>
          <!-- Dev only: e-mails don't leave the machine; Swoosh keeps them in a local mailbox. -->
          <a v-if="isLocalhost" href="/dev/mailbox" target="_blank" class="mt-6 block text-sm text-fg-faint underline">
            Dev: abrir a caixa de e-mails local
          </a>
        </template>

        <template v-else-if="state === 'terminated'">
          <p class="page-kicker mt-10">Sessão encerrada</p>
          <h1 class="display mt-5 text-4xl">Esta tela foi encerrada em outro dispositivo.</h1>
          <button type="button" class="btn btn-primary mt-8" @click="start">Assistir aqui de novo</button>
        </template>

        <template v-else-if="state === 'tampered'">
          <p class="page-kicker mt-10">Reprodução pausada</p>
          <h1 class="display mt-5 text-4xl">A marca d'água do player foi alterada.</h1>
          <p class="lede mt-4">Recarregue a página para continuar assistindo.</p>
        </template>

        <template v-else-if="state === 'error'">
          <p class="page-kicker mt-10">Erro</p>
          <h1 class="display mt-5 text-4xl">{{ errorMessage }}</h1>
          <button type="button" class="btn btn-quiet mt-8" @click="start">Tentar de novo</button>
        </template>
      </div>
    </div>
  </div>
</template>
