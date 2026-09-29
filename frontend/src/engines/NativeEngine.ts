import { Emitter } from './emitter'
import type { EngineEvent, MountOptions, PlayerEngine, TimeUpdate } from './PlayerEngine'

/**
 * Plain <video> for dev (Fake provider serves /dev/sample.mp4). Same
 * restrictions as the embed: no native fullscreen, PiP, download or casting,
 * so the watermark can't be escaped.
 */
export class NativeEngine implements PlayerEngine {
  private video: HTMLVideoElement | null = null
  private events = new Emitter()

  mount(container: HTMLElement, url: string, opts: MountOptions = {}): Promise<void> {
    const video = document.createElement('video')
    video.crossOrigin = 'anonymous'
    // Portuguese first, if present, is on by default.
    const captions = [...(opts.captions ?? [])].sort((a) => (a.srclang === 'pt-BR' ? -1 : 1))
    captions.forEach((c, i) => {
      const track = document.createElement('track')
      Object.assign(track, { kind: 'subtitles', srclang: c.srclang, label: c.label, src: c.src, default: i === 0 })
      video.appendChild(track)
    })
    video.src = url
    video.controls = true
    video.autoplay = true
    video.playsInline = true
    video.disablePictureInPicture = true
    video.setAttribute('controlsList', 'nofullscreen nodownload noremoteplayback noplaybackrate')
    video.className = 'absolute inset-0 h-full w-full bg-black'
    video.addEventListener('contextmenu', (e) => e.preventDefault())
    container.appendChild(video)
    this.video = video

    video.addEventListener('play', () => this.events.emit('play'))
    video.addEventListener('pause', () => this.events.emit('pause'))
    video.addEventListener('ended', () => this.events.emit('ended'))
    video.addEventListener('error', () => this.events.emit('error'))
    video.addEventListener('timeupdate', () =>
      this.events.emit('timeupdate', { seconds: video.currentTime, duration: video.duration || 0 }),
    )

    return new Promise((resolve) => {
      const ready = () => {
        this.events.emit('ready')
        resolve()
      }
      if (video.readyState >= 1) ready()
      else video.addEventListener('loadedmetadata', ready, { once: true })
    })
  }

  play() {
    void this.video?.play().catch(() => {
      /* autoplay blocked: the user presses play */
    })
  }

  pause() {
    this.video?.pause()
  }

  seek(seconds: number) {
    if (this.video) this.video.currentTime = seconds
  }

  // A no-arg callback is assignable here, so this satisfies both interface overloads.
  on(event: EngineEvent, cb: (t: TimeUpdate) => void) {
    this.events.on(event, cb as (p?: unknown) => void)
  }

  destroy() {
    this.events.clear()
    this.video?.pause()
    this.video?.removeAttribute('src')
    this.video?.load()
    this.video?.remove()
    this.video = null
  }
}
