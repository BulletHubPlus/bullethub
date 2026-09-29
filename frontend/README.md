# bullethub - Frontend

[![Vue](https://img.shields.io/badge/vue-3.5-42b883?logo=vuedotjs&logoColor=white)](https://vuejs.org/)
[![TypeScript](https://img.shields.io/badge/typescript-5-3178c6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Vite](https://img.shields.io/badge/vite-6-646cff?logo=vite&logoColor=white)](https://vite.dev/)
[![Pinia](https://img.shields.io/badge/state-Pinia-ffd859)](https://pinia.vuejs.org/)
[![Tailwind](https://img.shields.io/badge/tailwind-4-06b6d4?logo=tailwindcss&logoColor=white)](https://tailwindcss.com/)
[![PWA](https://img.shields.io/badge/PWA-installable-5a0fc8)](#02--technology-stack)

SPA do assinante em **Vue 3.5 + TypeScript + Vite**, servida como **PWA**. O
build sai em `../backend/priv/static/app` e é servido pelo próprio Phoenix - um
deploy, um domínio, CORS trivial. Estilo "Netflix" com design system próprio
(vermelho sobre preto), portado do `effront-web`.

Contexto do monorepo: [`../AGENTS.md`](../AGENTS.md)

## Índice

- [01 · Quick Start](#01--quick-start)
- [02 · Technology Stack](#02--technology-stack)
- [03 · Estrutura](#03--estrutura)
- [04 · Padrões & Decisões](#04--padrões--decisões)
- [05 · Comandos](#05--comandos)
- [06 · Testes & Qualidade](#06--testes--qualidade)

## 01 · Quick Start

```bash
npm install
BACKEND_PORT=4010 npm run dev     # http://localhost:5173
```

O Vite faz proxy de `/api`, `/socket`, `/health` e `/dev` para o Phoenix (porta
`BACKEND_PORT`, padrão `4000`). Rode o backend em paralelo (ver `../backend`).

## 02 · Technology Stack

| Área | Tecnologia |
| --- | --- |
| Framework | Vue 3.5 (Composition API) + TypeScript |
| Build | Vite 6 |
| Estado | Pinia |
| Rotas | Vue Router (guards `requireAuth` / `guest`) |
| Estilo | Tailwind CSS 4 + tokens próprios (Bricolage Grotesque + Inter) |
| Realtime | `phoenix` (npm) - canais `user:` e `playback:` |
| Player | Player.js (embed do Bunny) via a interface `PlayerEngine` |
| PWA | manifest + service worker (offline shell, instalável) |
| Testes | Vitest (unit) + Playwright (E2E, em `../e2e`) |

## 03 · Estrutura

```
src/
  api/           client.ts (Facade: fetch + refresh single-flight + Web Locks) e tipos
  stores/        Pinia: auth (sessão) · progress (sincronização entre dispositivos)
  engines/       PlayerEngine (Strategy): BunnyEmbedEngine (Player.js) · NativeEngine (dev)
  composables/   useUserChannel (socket compartilhado) · useInstallPrompt (PWA)
  components/
    shell/       AppHeader · SideNav (drawer) · UserMenu · BrandLink
    catalog/     PosterCard · TitleHero · TitleMeta · ProgressBar · MyListButton
    player/      WatermarkLayer (canvas + tamper detection)
    ui/          Icon (SVG próprios) · UserAvatar · TextField · FormAlert …
  views/         Landing · Home · Browse · Collection · Movie · Watch · Search
                 · Account · Devices · auth (login/registro/reset/confirm)
  router/        guards e rotas
  styles/        design tokens
```

## 04 · Padrões & Decisões

- **HTTP só via `api/client.ts`** (Facade). Componentes nunca chamam `fetch`
  direto. O refresh é *single-flight* (uma tentativa por vez, coordenada entre
  abas com Web Locks), porque o backend trata reuso de refresh como roubo.
- **Player só via a interface `PlayerEngine`** (Strategy). Trocar Bunny ↔
  hls.js + Enterprise DRM não toca em componente nenhum.
- **Ícones são componentes SVG próprios** (`components/ui/Icon.vue`). Sem lucide
  nem qualquer lib de ícone.
- **Design system**: preto `#060606`, acento vermelho `#f20024` só em
  borda/texto/gradiente (nunca preenchimento sólido em superfície grande), raio
  6px. Logo: símbolo (mark) quando logado, wordmark `bullethub.` quando
  deslogado.
- **Watermark** (RF06): e-mail mascarado + código da sessão desenhados em
  `<canvas>` sobre o player, com detecção de remoção (`MutationObserver` +
  `ResizeObserver`); ao adulterar, pausa e reporta ao canal.
- **Auth**: access token só em memória (Pinia); refresh em cookie `HttpOnly`.

## 05 · Comandos

```bash
npm run dev          # Vite dev server (BACKEND_PORT= para o proxy)
npm run typecheck    # vue-tsc (estrito)
npm test             # Vitest
npm run build        # → ../backend/priv/static/app
npm audit --audit-level=high
```

## 06 · Testes & Qualidade

O gate do CI para o frontend: `npm run typecheck`, `npm test`, `npm run build`,
`npm audit --audit-level=high`. Os fluxos de usuário (auth, playback, catálogo,
drawer) são cobertos pela suíte Playwright em [`../e2e`](../e2e), que roda contra
um servidor Phoenix real nos três navegadores (Chromium, Firefox, WebKit).

> A arte de fundo do login (`src/assets/login-bg.webp`) é uma composição
> **original** (abstrata, na identidade da marca). Se um dia usar pôsteres/artes
> de terceiros como fundo, garanta o licenciamento antes de publicar.
