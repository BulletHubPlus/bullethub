/**
 * Strategy interface (PRD §11): the Watch page only talks to this, so the
 * Bunny embed can be swapped for hls.js + Enterprise DRM without touching
 * components.
 */
export type EngineEvent = 'ready' | 'play' | 'pause' | 'ended' | 'timeupdate' | 'error'

export interface TimeUpdate {
  seconds: number
  duration: number
}

export interface CaptionTrack {
  srclang: string
  label: string
  /** Same-origin or blob: URL of a WebVTT file. */
  src: string
}

export interface MountOptions {
  /** Used by engines that render their own <video>; the Bunny embed ships its own tracks. */
  captions?: CaptionTrack[]
}

export interface PlayerEngine {
  /** Renders the player inside `container` and resolves when it can take commands. */
  mount(container: HTMLElement, url: string, opts?: MountOptions): Promise<void>
  play(): void
  pause(): void
  seek(seconds: number): void
  on(event: 'timeupdate', cb: (t: TimeUpdate) => void): void
  on(event: Exclude<EngineEvent, 'timeupdate'>, cb: () => void): void
  destroy(): void
}

export type EngineName = 'bunny' | 'native'

export async function createEngine(name: string): Promise<PlayerEngine> {
  if (name === 'bunny') return new (await import('./BunnyEmbedEngine')).BunnyEmbedEngine()
  if (name === 'native') return new (await import('./NativeEngine')).NativeEngine()
  throw new Error(`unknown player engine: ${name}`)
}
