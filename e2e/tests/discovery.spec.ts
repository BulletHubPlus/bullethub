import { expect, test } from '@playwright/test'
import { accounts, login } from './helpers'

test.beforeEach(async ({ page }) => login(page, accounts.family))

test('title page shows the ficha técnica', async ({ page }) => {
  await page.goto('/titulo/noite-neon')
  await expect(page.getByRole('heading', { level: 1, name: 'Noite Neon' })).toBeVisible()
  await expect(page.getByText('Neon Night')).toBeVisible()
  await expect(page.getByText('2025')).toBeVisible()
  await expect(page.getByTitle('Não recomendado para menores de 16 anos')).toBeVisible()
  await expect(page.getByText('Ana Lima, Bruno Reis')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Crime' })).toBeVisible()
})

test('search ignores accents and filters by genre', async ({ page }) => {
  await page.goto('/buscar')
  await page.getByLabel('Buscar por título, elenco ou direção').fill('acao')
  await expect(page.getByRole('link', { name: /Ação no Porto/ })).toBeVisible()

  await page.getByLabel('Buscar por título, elenco ou direção').fill('')
  await page.getByRole('button', { name: /Shounen/ }).click()
  await expect(page).toHaveURL(/genero=shounen/)
  await expect(page.getByRole('link', { name: /Lâmina Carmesim/ })).toBeVisible()
  await expect(page.getByRole('link', { name: /Noite Neon/ })).toHaveCount(0)
})

test('side drawer navigates by category and genre', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Abrir menu' }).click()
  const menu = page.getByRole('navigation', { name: 'Menu' })
  await expect(menu).toBeVisible()

  // Category → browse page
  await menu.getByRole('link', { name: 'Filmes' }).click()
  await expect(page).toHaveURL(/\/tipo\/filmes/)
  await expect(page.getByRole('heading', { level: 1, name: /Filmes/ })).toBeVisible()
  await expect(page.getByRole('link', { name: /Ação no Porto/ })).toBeVisible()

  // Reopen, jump to a genre → search filtered
  await page.getByRole('button', { name: 'Abrir menu' }).click()
  await page.getByRole('navigation', { name: 'Menu' }).getByRole('link', { name: /Shounen/ }).click()
  await expect(page).toHaveURL(/genero=shounen/)
  await expect(page.getByRole('link', { name: /Lâmina Carmesim/ })).toBeVisible()
})

test('Minha lista: save a title, see it on the home, remove it', async ({ page }) => {
  await page.goto('/titulo/lamina-carmesim')
  const button = page.getByRole('button', { name: /Minha lista|Na minha lista/ })
  if ((await button.getAttribute('aria-pressed')) === 'true') await button.click()
  await button.click()
  await expect(button).toHaveAttribute('aria-pressed', 'true')

  await page.goto('/')
  await expect(page.getByLabel('Minha lista').getByRole('link', { name: /Lâmina Carmesim/ })).toBeVisible()

  await page.goto('/titulo/lamina-carmesim')
  await page.getByRole('button', { name: 'Na minha lista' }).click()
  await page.goto('/')
  await expect(page.getByLabel('Minha lista')).toHaveCount(0)
})
