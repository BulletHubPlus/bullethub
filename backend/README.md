# bullethub - Backend

[![Elixir](https://img.shields.io/badge/elixir-1.18-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white)](https://www.phoenixframework.org/)
[![OTP](https://img.shields.io/badge/OTP-27-A90533?logo=erlang&logoColor=white)](https://www.erlang.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Oban](https://img.shields.io/badge/jobs-Oban-b1003e)](https://hexdocs.pm/oban)
[![Tests](https://img.shields.io/badge/tests-142_green-3ecf8e)](#06--testes--qualidade)

API JSON + Phoenix Channels + painel admin (LiveView) num **único release
Phoenix**, que também serve a SPA Vue (`priv/static/app`). Nenhum byte de vídeo
atravessa o app server - o navegador fala direto com a CDN do Bunny; o Phoenix só
autentica, assina tokens, registra progresso e mantém o estado de sessões.

Contexto do monorepo: [`../AGENTS.md`](../AGENTS.md) · Arquitetura visual:
[`../diagram.mmd`](../diagram.mmd)

## Índice

- [01 · Quick Start](#01--quick-start)
- [02 · Technology Stack](#02--technology-stack)
- [03 · Arquitetura (Bounded Contexts)](#03--arquitetura-bounded-contexts)
- [04 · Setup](#04--setup)
- [05 · Comandos & Ferramentas](#05--comandos--ferramentas)
- [06 · Testes & Qualidade](#06--testes--qualidade)
- [07 · Configuração & Deploy](#07--configuração--deploy)

## 01 · Quick Start

```bash
# Postgres local (127.0.0.1:5439) - não conflita com outros projetos
docker compose -f ../docker-compose.dev.yml up -d

# deps + ecto.create + migrate + assets
mix setup

# http://localhost:4000  (PORT=4010 se a 4000 estiver ocupada)
mix phx.server
```

Toolchain via [mise](https://mise.jdx.dev) (`../.tool-versions`); o Elixir do
sistema é antigo demais. E-mails de dev ficam em `/dev/mailbox`. Admin em
`admin.localhost`.

> Sem `BUNNY_API_KEY` no ambiente, o provider de mídia é o `Fake` (encoding
> instantâneo, vídeo local `/dev/sample.mp4`), então dá para exercitar todo o
> fluxo - upload, player, watermark - sem conta no Bunny.

## 02 · Technology Stack

| Camada | Tecnologia |
| --- | --- |
| Runtime | Elixir 1.18 / OTP 27 |
| Web | Phoenix 1.8 (Bandit), Phoenix LiveView, Phoenix Channels |
| Banco | PostgreSQL 16, Ecto 3, UUID v7 como PK |
| Jobs | Oban (fila sobre Postgres) + GenServers |
| Auth | Argon2id, `Phoenix.Token` (access), refresh rotativo em cookie |
| Rate limit | Hammer (ETS) |
| Cripto | `cloak_ecto` (AES-256-GCM para o CPF) |
| Mídia | `Bullet.Media.Provider` (Behaviour): Bunny Stream / Fake |
| E-mail | Swoosh + Resend |
| Qualidade | Credo, Sobelow, Dialyzer, mix_audit |

## 03 · Arquitetura (Bounded Contexts)

Cada contexto expõe funções públicas; schemas Ecto **nunca** vazam entre
contextos, e campos definidos pelo servidor (`role`, `user_id`, `kind`) nunca
entram em `cast`.

| Contexto | Responsabilidade |
| --- | --- |
| `Accounts` | Contas (Argon2id), confirmação, reset, dispositivos, sessões (refresh rotativo), LGPD (`Accounts.Privacy`) |
| `Billing` | Planos e assinaturas (gateway na Fase 3; hoje concessão manual) |
| `Catalog` | `Collection → Season → Media`, metadados, gêneros, busca, legendas |
| `Ingest` | Upload TUS, máquina de estados do asset, webhook Bunny (idempotente), poller |
| `Playback` | Sessões, Presence (limite de telas), progresso, watermark, autoplay |
| `Security` | Auditoria (`security_events`) e `PlaybackToken` (assinatura pura, testável por vetor) |
| `Support` | Busca de contas para o admin (e-mail, id, código da watermark) |
| `Media.Provider` | Ports & Adapters: `Bunny` (prod) e `Fake` (dev/test) |

Padrões: **máquina de estados** validada no changeset (`MediaAsset.status`),
**idempotência** em webhooks/jobs (`unique (provider, event_id)`), **Presence**
(CRDT, sem Redis) para o limite de streams, **outbox leve** (jobs Oban
enfileirados na mesma transação Ecto).

Diagrama completo (Mermaid): [`../diagram.mmd`](../diagram.mmd).

## 04 · Setup

**Pré-requisitos:** mise (ou asdf), Docker, Node 20 (para os assets do admin e
o build da SPA). O `mix setup` cuida de deps, banco, migrations e assets.

```bash
mise install                 # Elixir 1.18 / OTP 27 / Node 20 (via ../.tool-versions)
docker compose -f ../docker-compose.dev.yml up -d
mix setup
mix phx.server
```

Primeiro owner e assinatura (em produção via `bin/bullet eval`; em dev):

```bash
mix run -e 'Bullet.Accounts.set_role(Bullet.Accounts.get_user_by_email("voce@x"), :owner)'
mix run -e 'Bullet.Billing.grant(Bullet.Accounts.get_user_by_email("voce@x"), "padrao")'
```

## 05 · Comandos & Ferramentas

```bash
mix phx.server                 # servidor (PORT= para trocar a porta)
mix test                       # ExUnit (unit + controller + channel + LiveView)
mix test --failed              # só os que falharam
mix precommit                  # compile --warnings-as-errors + format + credo --strict + test
mix security.check             # sobelow + deps.audit + hex.audit
mix dialyzer                   # análise estática (0 erros)

# Banco isolado para testes de navegador / pentest - NUNCA use bullet_dev
DB_NAME=bullet_e2e mix bullet.e2e.setup

# Conteúdo de demonstração (série "Crossing Lines", provider Fake)
mix run priv/repo/demo_crossing_lines.exs

# Operações de release (produção)
bin/bullet eval 'Bullet.Release.migrate()'
bin/bullet eval 'Bullet.Release.promote("email@x", "owner")'
bin/bullet eval 'Bullet.Release.grant_subscription("email@x", "padrao", 30)'
```

## 06 · Testes & Qualidade

O gate abaixo é o mesmo do CI (`.github/workflows/ci.yml`). Nada faz merge com
warning, achado do Sobelow ou erro do Dialyzer.

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix sobelow --config --exit
mix deps.audit && mix hex.audit
mix dialyzer
mix test
```

Segurança tem também um lab de pentest caixa-preta em [`../.pentest`](../.pentest)
(tokens, refresh, rate limit, IDOR, mass assignment, webhook HMAC, headers/CORS)
e a suíte de navegador em [`../e2e`](../e2e).

## 07 · Configuração & Deploy

Tudo por env no `config/runtime.exs` (**o boot aborta se faltar um segredo**):

| Variável | Uso |
| --- | --- |
| `DATABASE_URL`, `POOL_SIZE` | Postgres |
| `SECRET_KEY_BASE` | assinatura de sessão/token (`mix phx.gen.secret`) |
| `CLOAK_KEY` | cifra o CPF em repouso - **faça backup fora do servidor** |
| `CPF_HMAC_KEY` | hash de unicidade do CPF (chave separada) |
| `BUNNY_LIBRARY_ID`, `BUNNY_API_KEY` | Bunny Stream (upload, criação de vídeo) |
| `BUNNY_READONLY_API_KEY` | valida o HMAC do webhook do Bunny |
| `BUNNY_EMBED_TOKEN_KEY` | assina o token do player embed |
| `BUNNY_CDN_HOSTNAME` | miniaturas (`vz-xxx.b-cdn.net`) |
| `RESEND_API_KEY`, `MAIL_FROM` | e-mail transacional |
| `PHX_HOST`, `ADMIN_HOST` | hosts do app e do admin |

Deploy: `mix release` → imagem Docker (`../Dockerfile`) → Coolify + Traefik. As
migrations rodam no start do container (`bin/migrate && bin/server`); se uma
falhar, o healthcheck não passa e o Coolify mantém o container anterior. Guia:
[`../README.md`](../README.md#deploy-coolify).
