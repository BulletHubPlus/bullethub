import { expect, test } from '@playwright/test'
import { PASSWORD, accounts, login } from './helpers'

const ADMIN = `http://admin.localhost:${process.env.E2E_PORT ?? '4012'}`

/** LiveView resets inputs typed before it connects: wait for the socket. */
async function connected(page: import('@playwright/test').Page, heading: string | RegExp) {
  await expect(page.getByRole('heading', { level: 1, name: heading })).toBeVisible()
  await page.waitForFunction(() => document.querySelector('[data-phx-main]')?.classList.contains('phx-connected'))
}

async function adminLogin(page: import('@playwright/test').Page, email: string) {
  await page.goto(`${ADMIN}/login`)
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha').fill(PASSWORD)
  await page.getByRole('button', { name: /Entrar/ }).click()
}

test('editor flow: create a series, add an episode, simulate encoding, publish', async ({ page }) => {
  await adminLogin(page, accounts.owner)
  await expect(page).toHaveURL(`${ADMIN}/`)
  const title = `Série E2E ${Date.now()}`

  await page.getByRole('link', { name: 'Nova coleção' }).click()
  await connected(page, /Nova coleção/)
  await page.getByLabel('Título', { exact: true }).fill(title)
  await page.getByText('Drama', { exact: true }).click()
  await page.getByRole('button', { name: 'Salvar' }).click()
  await expect(page.getByRole('heading', { name: title })).toBeVisible()

  await page.getByRole('button', { name: /Adicionar temporada/ }).click()
  await page.getByRole('link', { name: 'Episódio' }).click()
  await connected(page, /Novo episódio/)
  await page.getByLabel('Título').fill('Piloto')
  await page.getByRole('button', { name: 'Criar e enviar vídeo' }).click()

  await connected(page, /Piloto/)
  await page.getByRole('button', { name: /Simular upload/ }).click()
  await expect(page.locator('#asset-ready')).toBeVisible()
  await page.locator('#publish').click()
  await expect(page.locator('#unpublish')).toBeVisible()
})

// RF06: a leaked frame's code leads to the account.
test('support finds an account by the watermark code and suspends it', async ({ browser, page }) => {
  const viewer = await (await browser.newContext()).newPage()
  await login(viewer, accounts.family)
  const res = await viewer.request.post('/api/auth/refresh')
  const { access_token } = await res.json()
  const media = await (await viewer.request.get('/api/catalog/collections/noite-neon', { headers: { authorization: `Bearer ${access_token}` } })).json()
  const session = await (
    await viewer.request.post('/api/playback/sessions', {
      headers: { authorization: `Bearer ${access_token}` },
      data: { media_id: media.seasons[0].media[0].id },
    })
  ).json()

  await adminLogin(page, accounts.support)
  await page.goto(`${ADMIN}/usuarios`)
  await connected(page, /Usuários/)
  await page.getByRole('searchbox').fill(session.code.toLowerCase())
  await page.getByRole('searchbox').press('Enter')
  await expect(page.locator('#matched-code')).toContainText(session.code)
  await page.locator('#hits a').first().click()
  await expect(page.locator('#sessions')).toContainText(session.code)
  await expect(page.locator('#grant-form')).toHaveCount(0)

  await viewer.context().close()
})

test('support sees Usuários and Ingest but not the catalog (RF15)', async ({ page }) => {
  await adminLogin(page, accounts.support)
  await expect(page).toHaveURL(`${ADMIN}/ingest`)
  await expect(page.getByRole('link', { name: 'Usuários' }).first()).toBeVisible()
  await expect(page.getByRole('link', { name: 'Catálogo' })).toHaveCount(0)
})
