# bullethub - Agent Context

Contexto compartilhado para agentes (Codex, Claude Code) trabalhando neste
monorepo. O Claude também lê `.claude/CLAUDE.md`; o guia do framework Phoenix
fica em `backend/AGENTS.md`.

## O que é

**bullethub.app** - plataforma VOD por assinatura (filmes, séries e animes),
estilo Netflix, com infra de mídia 100% delegada ao Bunny Stream e proteção
antipirataria proporcional (token de curta duração, MediaCage, watermark
rastreável, limite de telas). Spec: `devdocs/PRD v4 - bullethub.app (auditado).md`.

## Stack

```
Backend   Elixir 1.18 / OTP 27 · Phoenix 1.8 (API JSON + Channels + admin LiveView)
          PostgreSQL 16 · Ecto · Oban (jobs) · Hammer (rate limit) · cloak_ecto (CPF)
Frontend  Vue 3.5 + TypeScript · Vite · Pinia · Vue Router · Tailwind 4 · player.js
Mídia     Bunny Stream (upload TUS, embed + Player.js, webhooks HMAC)
Deploy    Docker (release única) · Coolify + Traefik · Cloudflare
Toolchain mise (.tool-versions) - o Elixir do sistema (1.14) é antigo demais
```

Um único release Phoenix serve os dois hosts:

| Host | Serve |
| --- | --- |
| `bullethub.app` | SPA Vue (`/*`), API (`/api/*`), WebSocket (`/socket`), `/health`, `/webhooks/*` |
| `admin.bullethub.app` | Painel LiveView (cookie de sessão próprio) |

## Estrutura

```
backend/
  lib/bullet/            Contextos de domínio (bounded contexts)
    accounts/            Contas, sessões, dispositivos, tokens, LGPD (Privacy)
    billing/             Planos e assinaturas
    catalog/             Collection → Season → Media, metadados, gêneros, legendas
    ingest/              Upload TUS, máquina de estados do asset, webhook Bunny
    playback/            Sessões, Presence (limite de telas), progresso, watermark
    security/            Auditoria + PlaybackToken (assinatura pura Bunny)
    media/               Provider (Behaviour): Bunny (prod) e Fake (dev/test)
    support.ex           Busca de contas p/ o admin (e-mail, id, código da watermark)
    workers/             Oban: e-mail, webhook, poller, expurgo LGPD
  lib/bullet_web/
    controllers/api/     Endpoints JSON do SPA
    channels/            user:<id> e playback:<session_id>
    live/admin/          Catálogo, Ingest, Usuários (LiveView)
    plugs/               RequireAuth, RateLimit, RemoteIp
  test/                  ExUnit (unit + controller + channel + LiveView)
frontend/src/
  api/                   client.ts (Facade: fetch + refresh single-flight) + tipos
  stores/                Pinia: auth, progress
  engines/               PlayerEngine (Strategy): BunnyEmbedEngine, NativeEngine
  composables/           useUserChannel, useInstallPrompt
  views/ components/     Telas e UI (design system effront: vermelho/preto)
e2e/                     Playwright (Chromium, Firefox, WebKit) contra servidor real
.pentest/                Lab de segurança caixa-preta (adaptado do prostaff)
```

## Contextos (regras)

- **Bounded contexts**: cada contexto expõe funções públicas; schemas Ecto nunca
  vazam entre contextos. Campos definidos pelo servidor (`role`, `user_id`,
  `kind`) **nunca** entram em `cast` - são setados explicitamente.
- **Ports & Adapters**: o domínio só fala com `Bullet.Media.Provider` (Behaviour).
  `Bunny` é produção, `Fake` roda dev/test sem rede.
- **Máquina de estados** (`MediaAsset.status`): transições validadas no changeset;
  qualquer transição inválida é rejeitada.
- **Idempotência**: webhooks têm unique `(provider, event_id)`; jobs Oban únicos.
- **Presence, não heartbeat no banco**: o limite de telas (RF07) usa
  `Bullet.Playback.Presence` (CRDT), sem Redis.
- **Token puro**: `Bullet.Security.PlaybackToken` não tem efeito colateral (as
  chaves são passadas por argumento) - testável por vetor.

## Comandos

```bash
# Dev
docker compose -f docker-compose.dev.yml up -d          # Postgres em 127.0.0.1:5439
cd backend && mix setup && mix phx.server                # http://localhost:4000 (PORT=4010 se ocupado)
cd frontend && npm install && BACKEND_PORT=4010 npm run dev   # http://localhost:5173

# Gate de qualidade (o mesmo do CI) - rodar antes de concluir
cd backend && mix precommit && mix security.check && mix dialyzer
cd frontend && npm run typecheck && npm test && npm run build && npm audit --audit-level=high

# Testes de navegador (3 engines, servidor real, banco isolado bullet_e2e)
./scripts/dev-sample-video.sh                            # uma vez (precisa ffmpeg)
cd e2e && npm install && npx playwright install chromium firefox webkit && npx playwright test

# Pentest caixa-preta (alvo local próprio)
cd backend && DB_NAME=bullet_e2e mix bullet.e2e.setup && DB_NAME=bullet_e2e PORT=4012 mix phx.server &
cd .pentest && BASE_URL=http://localhost:4012 ./scripts/09_full_audit.sh
```

## Gate de qualidade (obrigatório - o CI falha sem isso)

Backend: `mix compile --warnings-as-errors`, `mix format --check-formatted`,
`mix credo --strict`, `mix sobelow --config --exit`, `mix deps.audit`,
`mix dialyzer` (0 erros), `mix test` (sem falhas).
Frontend: `vue-tsc` sem erros, `vitest`, `npm audit --audit-level=high`.
Nunca faça merge com warning, achado do Sobelow ou erro do Dialyzer.

## Segurança (não regredir)

- Access token de 15 min só em memória no SPA; refresh em cookie `HttpOnly`,
  `SameSite=Strict`, `Path=/api/auth`. Reuso de refresh (fora da janela de 15 s
  ou após a cadeia avançar) revoga o dispositivo.
- CPF cifrado (AES-GCM, `cloak_ecto`); unicidade por HMAC com chave separada;
  exibido só mascarado; **nunca** na watermark (só e-mail mascarado + código).
- Webhook Bunny: HMAC-SHA256 do corpo cru com a read-only key; idempotente.
- `filter_parameters` remove senha/CPF/e-mail/tokens dos logs.
- Rate limit pensando em CGNAT: por e-mail conta falhas; por IP é mais frouxo.
- Segredos só em `runtime.exs` via env; o boot aborta se faltar um.

## Convenções

- Comentários e docs em código: inglês. Texto de UI e mensagens: pt-BR (Gettext).
- Migrations com `up`/`down` reversíveis; UUID v7 como PK.
- Desvios do PRD são documentados no `README.md` (seção "Desvios em relação ao PRD").
- Decisões e o estado das fases: `README.md`. RIPD (LGPD): `docs/lgpd/RIPD.md`.
