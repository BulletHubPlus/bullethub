import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

const session = { access_token: 'new', expires_in: 900, device_id: 'd1', user: { id: 'u1' } }

describe('api client', () => {
  beforeEach(() => vi.resetModules())
  afterEach(() => vi.unstubAllGlobals())

  it('refreshes once on 401 and retries with the new token', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(401, { error: { code: 'unauthorized', message: 'x', details: {} } }))
      .mockResolvedValueOnce(json(200, session))
      .mockResolvedValueOnce(json(200, { ok: true }))
    vi.stubGlobal('fetch', fetchMock)

    const { api } = await import('@/api/client')
    await expect(api.get('/api/me')).resolves.toEqual({ ok: true })

    expect(fetchMock.mock.calls[1][0]).toBe('/api/auth/refresh')
    expect(fetchMock.mock.calls[2][1].headers.authorization).toBe('Bearer new')
  })

  it('concurrent 401s share a single refresh (reuse would revoke the device)', async () => {
    const fetchMock = vi.fn(async (url: string) =>
      url === '/api/auth/refresh' ? json(200, session) : json(401, { error: { code: 'unauthorized', message: 'x', details: {} } }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const { refreshSession } = await import('@/api/client')
    await Promise.all([refreshSession(), refreshSession(), refreshSession()])

    expect(fetchMock.mock.calls.filter(([u]) => u === '/api/auth/refresh')).toHaveLength(1)
  })

  it('throws a typed ApiError with the backend envelope', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(json(422, { error: { code: 'validation_failed', message: 'm', details: { fields: { cpf: ['inválido'] } } } })))

    const { api, ApiError } = await import('@/api/client')
    const err = (await api.post('/api/auth/register', {}, false).catch((e: unknown) => e)) as InstanceType<typeof ApiError>

    expect(err).toBeInstanceOf(ApiError)
    expect(err.code).toBe('validation_failed')
    expect(err.fields).toEqual({ cpf: ['inválido'] })
  })
})
