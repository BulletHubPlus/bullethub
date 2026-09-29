import { expect, type Page, type APIRequestContext } from '@playwright/test'

export const PASSWORD = 'senha-bem-longa-123'

export const accounts = {
  owner: 'owner@e2e.test',
  support: 'support@e2e.test',
  basic: 'basico@e2e.test', // 1 screen
  family: 'familia@e2e.test', // 4 screens
  noPlan: 'semplano@e2e.test',
}

export async function login(page: Page, email: string) {
  await page.goto('/entrar')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha').fill(PASSWORD)
  await page.getByRole('button', { name: /Entrar/ }).click()
  await expect(page).toHaveURL('/')
  // The account menu button only renders once authenticated.
  await expect(page.getByRole('button', { name: 'Menu da conta' })).toBeVisible()
}

/** Starts playback and makes sure the video actually advances (muted: autoplay rules differ per browser). */
export async function expectPlaying(page: Page) {
  await expect(page.locator('video')).toBeVisible()
  await page.evaluate(() => {
    const v = document.querySelector('video')!
    v.muted = true
    return v.play().catch(() => undefined)
  })
  await expect.poll(() => page.evaluate(() => document.querySelector('video')!.currentTime), { timeout: 15_000 }).toBeGreaterThan(1)
}

/** Latest dev-mailbox message to `email` (Swoosh local adapter). */
export async function lastEmailTo(request: APIRequestContext, email: string) {
  let found: { subject: string; text_body: string } | undefined
  await expect
    .poll(async () => {
      const { data } = await (await request.get('/dev/mailbox/json')).json()
      found = data.find((m: { to: string[] }) => m.to.some((t) => t.includes(email)))
      return !!found
    })
    .toBe(true)
  return found!
}

export function uniqueEmail(prefix: string) {
  return `${prefix}.${Date.now()}.${Math.floor(Math.random() * 1e6)}@e2e.test`
}

/** Valid CPF generator (check digits), so each run registers new accounts. */
export function randomCpf() {
  const d = Array.from({ length: 9 }, () => Math.floor(Math.random() * 10))
  for (let k = 0; k < 2; k++) {
    const w = d.length + 1
    const r = (d.reduce((s, n, i) => s + n * (w - i), 0) * 10) % 11
    d.push(r === 10 ? 0 : r)
  }
  return d.join('')
}
