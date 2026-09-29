import { defineConfig, devices } from '@playwright/test'

/**
 * Browser suite against a real Phoenix server (not mocks): the bugs that
 * mattered so far - socket auth, refresh races, channel broadcasts - only
 * show up end to end.
 *
 * The server runs on its own database (bullet_e2e), freshly seeded, so it
 * never competes with a developer's server for Oban jobs or data.
 */
const PORT = process.env.E2E_PORT ?? '4012'
const mix = 'M=mix; command -v mise >/dev/null 2>&1 && M="mise exec -- mix";'

export default defineConfig({
  testDir: './tests',
  // One seeded database, stateful flows (stream limits): run serially.
  workers: 1,
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    locale: 'pt-BR',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], launchOptions: { args: ['--autoplay-policy=no-user-gesture-required'] } },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'], launchOptions: { firefoxUserPrefs: { 'media.autoplay.default': 0 } } },
      // admin.localhost host routing and the PWA install flow are Chromium-only concerns.
      testIgnore: /admin|pwa/,
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
      testIgnore: /admin|pwa/,
    },
  ],
  webServer: {
    cwd: '../backend',
    command:
      `sh -c '${mix} test -f priv/static/app/index.html || (cd ../frontend && npm run build) && ` +
      `DB_NAME=bullet_e2e $M bullet.e2e.setup && DB_NAME=bullet_e2e PORT=${PORT} exec $M phx.server'`,
    url: `http://localhost:${PORT}/health`,
    reuseExistingServer: false,
    timeout: 180_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
})
