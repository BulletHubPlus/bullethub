import { expect, test } from '@playwright/test'
import { accounts, expectPlaying, login } from './helpers'

test('plays with watermark and skip-intro; unfinished episode shows in continue watching', async ({ page }) => {
  await login(page, accounts.family)
  await page.goto('/titulo/noite-neon')
  await page.getByRole('link', { name: 'Assistir Capítulo 1' }).click()
  await expectPlaying(page)
  await expect(page.locator('canvas')).toBeVisible()

  // Skip-intro is offered during the first 10 s. Rewind: an earlier browser
  // project may have left this episode's progress past the intro (resume).
  await page.evaluate(() => (document.querySelector('video')!.currentTime = 2))
  await page.getByRole('button', { name: 'Pular abertura' }).click()
  await expect.poll(() => page.evaluate(() => document.querySelector('video')!.currentTime)).toBeGreaterThanOrEqual(10)

  // Past the 30 s resume threshold, then pause: progress is pushed on pause.
  await page.evaluate(() => {
    const v = document.querySelector('video')!
    v.currentTime = 60
    v.pause()
  })
  await page.waitForTimeout(500)
  await page.goto('/')
  await expect(page.getByLabel('Continuar assistindo').getByText('Capítulo 1').first()).toBeVisible()
})

test('end of an episode offers the next one (RF04)', async ({ page }) => {
  await login(page, accounts.family)
  await page.goto('/titulo/noite-neon')
  await page.getByRole('link', { name: 'Assistir Capítulo 2' }).click()
  await expectPlaying(page)
  await page.evaluate(() => (document.querySelector('video')!.currentTime = document.querySelector('video')!.duration - 1))
  await expect(page.getByRole('status')).toContainText('Capítulo 3')
  await page.getByRole('button', { name: 'Assistir agora' }).click()
  await expect(page).toHaveURL(/\/assistir\//)
  await expect(page.getByText('T2:E1')).toBeVisible()
})

// RF07: 1-screen plan; the second device must free the first one.
test('stream limit blocks a second screen until the first is ended', async ({ browser }) => {
  const a = await (await browser.newContext()).newPage()
  const b = await (await browser.newContext()).newPage()

  await login(a, accounts.basic)
  await a.goto('/titulo/noite-neon')
  await a.getByRole('link', { name: 'Assistir Capítulo 1' }).click()
  await expectPlaying(a)

  await login(b, accounts.basic)
  await b.goto('/titulo/noite-neon')
  await b.getByRole('link', { name: 'Assistir Capítulo 2' }).click()
  await expect(b.getByText('Todas as telas do seu plano estão em uso')).toBeVisible()

  await b.getByRole('button', { name: 'Encerrar esta tela' }).click()
  await expect(a.getByText('Esta tela foi encerrada em outro dispositivo')).toBeVisible()
  await expectPlaying(b)

  await a.context().close()
  await b.context().close()
})

test('removing the watermark pauses playback', async ({ page }) => {
  await login(page, accounts.family)
  await page.goto('/titulo/lamina-carmesim')
  await page.getByRole('link', { name: /Assistir/ }).first().click()
  await expectPlaying(page)
  await page.evaluate(() => document.querySelector('canvas')!.remove())
  await expect(page.getByText("A marca d'água do player foi alterada")).toBeVisible()
})

test('movie has captions in the native player', async ({ page }) => {
  await login(page, accounts.family)
  await page.goto('/buscar?q=porto')
  await page.getByRole('link', { name: /Ação no Porto/ }).first().click()
  await page.getByRole('link', { name: /Assistir|Continuar/ }).click()
  await expectPlaying(page)
  await expect(page.locator('video track[srclang="pt-BR"]')).toHaveCount(1)
})

test('without a plan, the player explains instead of playing', async ({ page }) => {
  await login(page, accounts.noPlan)
  await page.goto('/titulo/noite-neon')
  await page.getByRole('link', { name: 'Assistir Capítulo 1' }).click()
  await expect(page.getByText('Você ainda não tem um plano ativo')).toBeVisible()
})
