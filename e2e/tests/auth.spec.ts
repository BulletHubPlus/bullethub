import { expect, test } from '@playwright/test'
import { PASSWORD, accounts, lastEmailTo, login, randomCpf, uniqueEmail } from './helpers'

test('landing: CTAs go to plans and to the chosen plan at sign-up', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Filmes, séries e animes')
  await page.getByRole('navigation').getByRole('link', { name: 'Ver planos' }).click()
  await expect(page).toHaveURL(/#planos$/)
  await page.getByRole('link', { name: 'Escolher Padrão' }).click()
  await expect(page).toHaveURL(/\/criar-conta\?plano=padrao/)
  await expect(page.getByText('Padrão · 2 telas')).toBeVisible()
})

test('sign-up → confirmation e-mail → confirmed', async ({ page, request }) => {
  const email = uniqueEmail('novo')
  await page.goto('/criar-conta')
  await page.getByLabel('Nome').fill('Pessoa Nova')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('CPF').fill(randomCpf())
  await page.getByLabel('Senha').fill(PASSWORD)
  await page.getByRole('button', { name: /Criar conta/ }).click()
  await expect(page.getByText('Conta criada')).toBeVisible()

  const mail = await lastEmailTo(request, email)
  const link = mail.text_body.match(/https?:\/\/\S+\/confirmar-email\/\S+/)![0]
  await page.goto(new URL(link).pathname)
  await expect(page.getByText('E-mail confirmado')).toBeVisible()
})

// Regression: a reload used to race the refresh-token rotation and revoke the device.
test('session survives reloads and navigations', async ({ page }) => {
  await login(page, accounts.family)
  for (let i = 0; i < 3; i++) {
    await page.reload()
    await expect(page.getByRole('button', { name: 'Menu da conta' })).toBeVisible()
  }
  await page.goto('/titulo/noite-neon')
  await page.goto('/')
  await expect(page.getByRole('button', { name: 'Menu da conta' })).toBeVisible()
})

test('wrong password is refused; repeated attempts are rate limited', async ({ page }) => {
  // Own IP and e-mail buckets, so the limit doesn't block the rest of the suite.
  await page.setExtraHTTPHeaders({ 'x-forwarded-for': `198.51.100.${Math.floor(Math.random() * 250) + 1}` })
  await page.goto('/entrar')
  await page.getByLabel('E-mail').fill(uniqueEmail('bruteforce'))
  const pwd = page.getByLabel('Senha')
  const submit = page.getByRole('button', { name: /Entrar/ })
  await pwd.fill('senha-errada-123')
  await submit.click()
  await expect(page.getByRole('alert')).toContainText('E-mail ou senha incorretos')
  for (let i = 0; i < 5; i++) await submit.click()
  await expect(page.getByRole('alert')).toContainText('Muitas tentativas')
})
