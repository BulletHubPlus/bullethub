declare module 'player.js' {
  namespace playerjs {
    class Player {
      constructor(elem: HTMLIFrameElement | string)
      on(event: string, cb: (payload?: any) => void): void
      off(event: string, cb?: (payload?: any) => void): void
      play(): void
      pause(): void
      setCurrentTime(seconds: number): void
      getCurrentTime(cb: (seconds: number) => void): void
      getDuration(cb: (seconds: number) => void): void
      mute(): void
      unmute(): void
      setVolume(volume: number): void
      supports(kind: 'method' | 'event', name: string | string[]): boolean
    }
  }
  export default playerjs
}
