import { expect, test } from '@playwright/test'

test('installable: manifest, icons and a registered service worker', async ({ page }) => {
  await page.goto('/')
  const href = await page.locator('link[rel="manifest"]').getAttribute('href')
  const res = await page.request.get(href!)
  expect(res.headers()['content-type'], `GET ${res.url()} → ${res.status()}`).toContain('application/manifest+json')
  const manifest = await res.json()
  expect(manifest.display).toBe('standalone')
  for (const icon of manifest.icons) expect((await page.request.get(icon.src)).ok()).toBe(true)

  await expect.poll(() => page.evaluate(async () => !!(await navigator.serviceWorker.getRegistration('/')))).toBe(true)
})
