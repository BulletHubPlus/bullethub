<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

/**
 * RF06 watermark: masked e-mail + session code, drawn on a <canvas> (not DOM
 * text, so it can't be Ctrl+F'd or restyled by selector), jumping between 9
 * zones every 20-60 s with random opacity. Sibling of the player, never inside
 * the cross-origin iframe.
 *
 * Tamper detection: removal, hiding or shrinking of the canvas (DevTools, CSS
 * injection, extensions) emits `tampered`; the Watch page pauses and reports
 * it (RF14). A determined attacker can still rewrite the bundle - accepted in
 * the threat model (PRD §7); the code on every frame keeps the leak traceable.
 */
const props = defineProps<{ text: string }>()
const emit = defineEmits<{ tampered: [detail: string] }>()

const wrap = ref<HTMLDivElement | null>(null)
const canvas = ref<HTMLCanvasElement | null>(null)

let moveTimer: number | undefined
let checkTimer: number | undefined
let mutation: MutationObserver | null = null
let resize: ResizeObserver | null = null
let tampered = false

function rand(): number {
  const buf = new Uint32Array(1)
  crypto.getRandomValues(buf)
  return buf[0] / 0xffffffff
}

function draw() {
  const el = canvas.value
  const host = wrap.value
  if (!el || !host) return

  const dpr = window.devicePixelRatio || 1
  const { width, height } = host.getBoundingClientRect()
  el.width = Math.max(1, Math.round(width * dpr))
  el.height = Math.max(1, Math.round(height * dpr))

  const ctx = el.getContext('2d')
  if (!ctx) return
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, width, height)

  const size = 14 + Math.round(rand() * 2)
  ctx.font = `600 ${size}px Inter, system-ui, sans-serif`
  ctx.textBaseline = 'middle'
  const textWidth = ctx.measureText(props.text).width

  // 3×3 grid; pick a cell, then jitter inside it.
  const col = Math.floor(rand() * 3)
  const row = Math.floor(rand() * 3)
  const pad = 24
  const cellW = (width - pad * 2) / 3
  const cellH = (height - pad * 2) / 3
  const x = pad + col * cellW + rand() * Math.max(0, cellW - textWidth)
  const y = pad + row * cellH + cellH / 2 + (rand() - 0.5) * (cellH / 3)

  ctx.globalAlpha = 0.25 + rand() * 0.2
  ctx.fillStyle = '#ffffff'
  ctx.shadowColor = 'rgba(0,0,0,0.6)'
  ctx.shadowBlur = 3
  ctx.fillText(props.text, Math.min(x, width - textWidth - pad), y)
}

function scheduleMove() {
  moveTimer = window.setTimeout(() => {
    draw()
    scheduleMove()
  }, 20_000 + rand() * 40_000)
}

function flag(detail: string) {
  if (tampered) return
  tampered = true
  emit('tampered', detail)
}

// Computed style catches stylesheet injection that MutationObserver can't see.
function inspect() {
  const el = canvas.value
  if (!el || !el.isConnected) return flag('removed')
  const cs = getComputedStyle(el)
  const rect = el.getBoundingClientRect()
  if (cs.display === 'none' || cs.visibility !== 'visible' || Number(cs.opacity) < 0.9) flag('hidden')
  else if (rect.width < 50 || rect.height < 50) flag('shrunk')
}

onMounted(() => {
  draw()
  scheduleMove()

  mutation = new MutationObserver(inspect)
  if (wrap.value?.parentElement) {
    mutation.observe(wrap.value.parentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'hidden'] })
  }
  resize = new ResizeObserver(() => {
    draw()
    inspect()
  })
  if (wrap.value) resize.observe(wrap.value)
  checkTimer = window.setInterval(inspect, 2000)
})

onBeforeUnmount(() => {
  window.clearTimeout(moveTimer)
  window.clearInterval(checkTimer)
  mutation?.disconnect()
  resize?.disconnect()
})
</script>

<template>
  <div ref="wrap" class="pointer-events-none absolute inset-0 z-20" aria-hidden="true">
    <canvas ref="canvas" class="h-full w-full" />
  </div>
</template>
