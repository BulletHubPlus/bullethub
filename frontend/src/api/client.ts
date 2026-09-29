import type { ErrorEnvelope, SessionResponse } from './types'

/**
 * Facade: the only place that talks HTTP (PRD §4). Components and stores never
 * call fetch directly.
 *
 * - Access token lives only in memory (never localStorage) to limit XSS impact.
 * - Refresh token is an HttpOnly cookie scoped to /api/auth; JS can't read it.
 * - On 401, one refresh is attempted and the request retried once.
 * - Refresh is single-flight within the tab and serialized across tabs with the
 *   Web Locks API, because the backend treats a reused refresh token as theft.
 */

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly details: Record<string, unknown>

  constructor(status: number, code: string, message: string, details: Record<string, unknown> = {}) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }

  /** Field errors from a 422 `validation_failed`. */
  get fields(): Record<string, string[]> {
    return (this.details.fields as Record<string, string[]>) ?? {}
  }
}

type SessionListener = (session: SessionResponse | null) => void

let accessToken: string | null = null
let refreshing: Promise<SessionResponse | null> | null = null
const listeners = new Set<SessionListener>()

export function getAccessToken(): string | null {
  return accessToken
}

export function onSessionChange(fn: SessionListener): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

function setSession(session: SessionResponse | null) {
  accessToken = session?.access_token ?? null
  listeners.forEach((fn) => fn(session))
}

async function parseError(res: Response): Promise<ApiError> {
  try {
    const body = (await res.json()) as ErrorEnvelope
    return new ApiError(res.status, body.error.code, body.error.message, body.error.details)
  } catch {
    return new ApiError(res.status, `http_${res.status}`, 'Erro inesperado. Tente novamente.')
  }
}

async function doRefresh(): Promise<SessionResponse | null> {
  const run = async () => {
    const res = await fetch('/api/auth/refresh', { method: 'POST', credentials: 'same-origin' })
    if (!res.ok) return null
    return (await res.json()) as SessionResponse
  }

  const session =
    typeof navigator !== 'undefined' && navigator.locks
      ? await navigator.locks.request('bullethub-refresh', run)
      : await run()

  setSession(session)
  return session
}

/** Single-flight refresh; concurrent callers share the same promise. */
export function refreshSession(): Promise<SessionResponse | null> {
  refreshing ??= doRefresh().finally(() => {
    refreshing = null
  })
  return refreshing
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  body?: unknown
  auth?: boolean
}

export async function request<T>(path: string, opts: RequestOptions = {}, retried = false): Promise<T> {
  const { method = 'GET', body, auth = true } = opts
  const headers: Record<string, string> = { accept: 'application/json' }
  if (body !== undefined) headers['content-type'] = 'application/json'
  if (auth && accessToken) headers.authorization = `Bearer ${accessToken}`

  const res = await fetch(path, {
    method,
    headers,
    credentials: 'same-origin',
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  if (res.status === 401 && auth && !retried) {
    const session = await refreshSession()
    if (session) return request<T>(path, opts, true)
  }

  if (!res.ok) throw await parseError(res)
  if (res.status === 204 || res.status === 202) return undefined as T
  return (await res.json()) as T
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown, auth = true) => request<T>(path, { method: 'POST', body, auth }),
  put: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PUT', body }),
  del: <T>(path: string, body?: unknown) => request<T>(path, { method: 'DELETE', body }),

  async login(email: string, password: string): Promise<SessionResponse> {
    const session = await request<SessionResponse>('/api/auth/login', {
      method: 'POST',
      body: { email, password },
      auth: false,
    })
    setSession(session)
    return session
  },

  /**
   * Fire-and-forget for pagehide/unload. `sendBeacon` can't carry the bearer
   * token, so this uses fetch keepalive, which survives the page going away.
   */
  beacon(path: string, body: unknown, method: 'PUT' | 'POST' = 'POST') {
    const headers: Record<string, string> = { 'content-type': 'application/json' }
    if (accessToken) headers.authorization = `Bearer ${accessToken}`
    void fetch(path, { method, headers, body: JSON.stringify(body), keepalive: true, credentials: 'same-origin' }).catch(
      () => {},
    )
  },

  async logout(): Promise<void> {
    try {
      await request<void>('/api/auth/logout', { method: 'POST', auth: false })
    } finally {
      setSession(null)
    }
  },
}
