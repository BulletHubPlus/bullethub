import { Socket, type Channel } from 'phoenix'
import { getAccessToken, refreshSession } from '@/api/client'

/**
 * One socket per tab, joined to `user:<id>` (PRD §10.2). The access token goes
 * in the Sec-WebSocket-Protocol header via `authToken`, never in the URL.
 */
let socket: Socket | null = null
let channel: Channel | null = null

export interface UserChannelHandlers {
  onDeviceRevoked?: (deviceId: string) => void
  onProgressUpdated?: (payload: { media_id: string; position: number; completed: boolean; device_id: string | null }) => void
  /** Socket refused and refresh failed: this device was revoked or the session died. */
  onAuthLost?: () => void
}

export function connectUserChannel(userId: string, handlers: UserChannelHandlers = {}) {
  disconnectUserChannel()

  socket = new Socket('/socket', {
    // phoenix.js accepts a function here (re-read on every reconnect, so a
    // refreshed access token is picked up); @types/phoenix only declares string.
    authToken: (() => getAccessToken() ?? '') as unknown as string,
    reconnectAfterMs: (tries: number) => [1000, 2000, 5000, 10000][tries - 1] ?? 10000,
  })

  // A revoked device gets its socket dropped server-side and can't reconnect.
  // Try one refresh: if the server rejects it, the session is gone.
  // Throttled: a flapping network must not turn into a refresh storm (each
  // refresh rotates the token).
  let lastRefresh = 0
  socket.onError(() => {
    if (Date.now() - lastRefresh < 30_000) return
    lastRefresh = Date.now()
    refreshSession()
      .then((session) => {
        if (!session) handlers.onAuthLost?.()
      })
      .catch(() => {
        /* network blip: phoenix.js keeps retrying */
      })
  })
  socket.connect()

  channel = socket.channel(`user:${userId}`, {})
  channel.on('device_revoked', ({ device_id }: { device_id: string }) => handlers.onDeviceRevoked?.(device_id))
  channel.on('progress_updated', (p: Parameters<NonNullable<UserChannelHandlers['onProgressUpdated']>>[0]) =>
    handlers.onProgressUpdated?.(p),
  )
  channel.join()
}

/** The tab's socket, shared with the playback channel (one WebSocket per tab). */
export function getSocket(): Socket | null {
  return socket
}

export function disconnectUserChannel() {
  channel?.leave()
  socket?.disconnect()
  channel = null
  socket = null
}
