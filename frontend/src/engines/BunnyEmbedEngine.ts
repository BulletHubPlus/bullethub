import playerjs from 'player.js'
import { Emitter } from './emitter'
import type { EngineEvent, PlayerEngine, TimeUpdate } from './PlayerEngine'

/**
 * Bunny Stream iframe driven through Player.js (ADR-002). MediaCage Basic
 * (anti-download) only works inside this embed.
 *
 * Deliberately NOT allowed on the iframe: `fullscreen` and `picture-in-picture`.
 * Both would take the video out from under the watermark; the Watch page
 * fullscreens the wrapper (video + watermark) instead.
 */
export class BunnyEmbedEngine implements PlayerEngine {
  private iframe: HTMLIFrameElement | null = null
  private player: playerjs.Player | null = null
  private events = new Emitter()

  mount(container: HTMLElement, url: string): Promise<void> {
    // Captions live in the Bunny library; the embed lists them in its own menu.
    const iframe = document.createElement('iframe')
    iframe.src = url
    iframe.title = 'Player'
    iframe.allow = 'autoplay; encrypted-media'
    iframe.referrerPolicy = 'strict-origin-when-cross-origin'
    iframe.className = 'absolute inset-0 h-full w-full border-0'
    container.appendChild(iframe)
    this.iframe = iframe

    return new Promise((resolve) => {
      const player = new playerjs.Player(iframe)
      this.player = player
      player.on('ready', () => {
        player.on('play', () => this.events.emit('play'))
        player.on('pause', () => this.events.emit('pause'))
        player.on('ended', () => this.events.emit('ended'))
        player.on('error', () => this.events.emit('error'))
        player.on('timeupdate', (t: TimeUpdate) => this.events.emit('timeupdate', t))
        this.events.emit('ready')
        resolve()
      })
    })
  }

  play() {
    this.player?.play()
  }

  pause() {
    this.player?.pause()
  }

  seek(seconds: number) {
    this.player?.setCurrentTime(seconds)
  }

  // A no-arg callback is assignable here, so this satisfies both interface overloads.
  on(event: EngineEvent, cb: (t: TimeUpdate) => void) {
    this.events.on(event, cb as (p?: unknown) => void)
  }

  destroy() {
    this.events.clear()
    this.iframe?.remove()
    this.iframe = null
    this.player = null
  }
}
