# bullethub.app

Plataforma VOD por assinatura: filmes, séries e animes. Especificação: [`devdocs/PRD v4 - bullethub.app (auditado).md`](devdocs/PRD%20v4%20-%20bullethub.app%20(auditado).md).

```
backend/    Phoenix 1.8 (Elixir 1.18 / OTP 27) - API JSON, Channels, admin LiveView, serve a SPA
frontend/   Vue 3.5 + Vite + Pinia + Tailwind 4 - SPA do assinante (build → backend/priv/static/app)
Dockerfile  release única (node → mix release → alpine, ~70 MB, usuário não-root)
docker-compose.yml       deploy no Coolify (Traefik + Let's Encrypt)
docker-compose.dev.yml   Postgres local na porta 5439
```

Um único release atende os dois hosts:

| Host | O que serve |
| --- | --- |
| `bullethub.app` | SPA Vue (`/*`), API (`/api/*`), WebSocket (`/socket`), `/health` |
| `admin.bullethub.app` | Painel LiveView (Fase 1) com cookie de sessão próprio |
| `www.bullethub.app` | 301 → apex (Traefik) |

## Rodando local

Toolchain via [mise](https://mise.jdx.dev) (`.tool-versions`). O Elixir do sistema (1.14) é antigo demais.

```bash
docker compose -f docker-compose.dev.yml up -d      # Postgres em 127.0.0.1:5439

cd backend
mix setup                                           # deps + ecto.create + migrate + assets
mix phx.server                                      # http://localhost:4000  (PORT=4010 se a 4000 estiver ocupada)

cd ../frontend
npm install
npm run dev                                         # http://localhost:5173 (proxy /api e /socket → :4000)
```

E-mails em dev: `http://localhost:4000/dev/mailbox`. Admin em dev: `http://admin.localhost:4000`.

Testes de navegador (Playwright: Chromium, Firefox e WebKit/Safari) contra um servidor real, na porta 4012, com banco próprio (`bullet_e2e`) recriado a cada execução. Não interferem no seu servidor de dev:

```bash
./scripts/dev-sample-video.sh          # uma vez
cd e2e && npm install && npx playwright install chromium firefox webkit
npx playwright test                     # ou: npm run test:chromium
```

Checks (os mesmos do CI):

```bash
cd backend && mix precommit && mix security.check && mix dialyzer
cd frontend && npm run typecheck && npm test && npm run build && npm audit --audit-level=high
```

## Deploy (Coolify)

Mesmo padrão do prostaff-events/prostaff-api.

1. **Postgres**: crie um recurso *PostgreSQL 16* no Coolify (rede `coolify`), ative *Scheduled Backups* para S3/Bunny Storage (RNF07) e copie a URL interna para `DATABASE_URL`.
2. **App**: novo recurso *Docker Compose* apontando para este repositório (`docker-compose.yml`). Preencha as variáveis de `.env.example`. O compose recusa subir se faltar alguma, e o `runtime.exs` aborta o boot também.
3. **DNS**: `bullethub.app`, `admin.bullethub.app` e `www.bullethub.app` → IP do servidor Coolify.
4. **GitHub**: secrets `COOLIFY_WEBHOOK` e `COOLIFY_TOKEN`; environment `production` com revisores obrigatórios.
5. Deploy: `git tag v0.1.0 && git push --tags` → CI completo → aprovação → webhook do Coolify → espera `/health` ficar verde.

As migrações rodam no start do container (`bin/migrate && bin/server`). Se uma migração falhar, o healthcheck não passa e o Coolify mantém o container anterior.

**Guarde `CLOAK_KEY` e `CPF_HMAC_KEY` fora do servidor.** Sem a primeira, os CPFs cifrados são irrecuperáveis. Trocar a segunda quebra a unicidade de CPF sem um rehash.

## Fase 0: o que está pronto

| Item do PRD | Onde |
| --- | --- |
| Accounts: registro com CPF validado, Argon2id, confirmação de e-mail, reset de senha | `Bullet.Accounts`, `Api.AuthController` |
| Access token 15 min (só em memória) + refresh rotativo em cookie `HttpOnly; SameSite=Strict; Path=/api/auth` | `BulletWeb.AccessToken`, `Accounts.refresh/2` |
| Reuso de refresh revoga o dispositivo inteiro e grava `security_events` | `Accounts.rotate/1` |
| Dispositivos nomeados + revogação que derruba o WebSocket na hora (RF11) | `UserSocket.id/1`, `Accounts.broadcast_device_revoked/2` |
| CPF cifrado (AES-GCM, `cloak_ecto`) + `cpf_hash` HMAC para unicidade (RNF09) | `Bullet.Vault`, `Accounts.CPF` |
| Rate limit (login 5/min por IP e por e-mail, cadastro 3/h, reset 5/h) | `Plugs.RateLimit` (Hammer/ETS) |
| IP real atrás do Traefik (só confia no XFF quando o peer é a rede privada) | `Plugs.RemoteIp` |
| E-mails via Oban na mesma transação (outbox) | `UserNotifier`, `Workers.DeliverUserEmail` |
| `Bullet.Media.Provider` (Behaviour) com adapters `Bunny` e `Fake` | `lib/bullet/media/` |
| Assinatura pura do embed token e da assinatura TUS do Bunny | `Security.PlaybackToken` (testado com vetores externos) |
| Envelope de erro `{error: {code, message, details}}` (§10.4) | `BulletWeb.ErrorResponse` |
| CSP estrita na SPA (só `iframe.mediadelivery.net` em `frame-src`), na API e no admin | `SpaController`, `router.ex` |
| SPA: facade HTTP com refresh single-flight + Web Locks entre abas, guards, telas de auth e dispositivos | `frontend/src/api/client.ts`, `router/` |
| CI: format, credo --strict, sobelow, deps.audit, hex.audit, dialyzer, vitest, npm audit, semgrep, Trivy na imagem | `.github/workflows/ci.yml` |

## Fase 1: o que está pronto

| Item do PRD | Onde |
| --- | --- |
| Catálogo `Collection → Season → Media`: séries e animes (temporada → episódio), filmes sem coleção (RF09) | `Bullet.Catalog` |
| `media_assets` com máquina de estados validada no changeset; sinais atrasados passam só por transições válidas, numa transação | `Ingest.MediaAsset`, `Ingest.advance/3` |
| Upload TUS direto ao Bunny, retomável, assinatura por vídeo com validade de 24 h (RF08) | `Ingest.start_upload/1`, `assets/js/hooks/tus_upload.js` |
| Webhook `POST /webhooks/bunny`: HMAC-SHA256 do corpo cru com a read-only key, idempotente por `(provider, event_id)`, job Oban na mesma transação | `Ingest.accept_bunny_webhook/2`, `WebhookController` |
| Poller a cada 10 min para assets em `processing` há mais de 30 min; `failed` por timeout após 6 h | `Workers.AssetStatusPoller` |
| Status ao vivo no painel via PubSub, sem polling (RF10) | `Admin.IngestLive`, `Admin.MediaLive` |
| `publish_media/1` só com asset `ready` | `Catalog.publish_media/1` |
| Painel admin em `admin.bullethub.app`: login próprio, papéis `owner`/`editor`/`support` (RF15) | `BulletWeb.AdminAuth`, `live/admin/` |
| API do catálogo para a SPA (home, título, filme); só mostra o que está publicado e pronto | `Api.CatalogController` |
| Landing pública em `/`; home do assinante com fileiras reais | `frontend/src/views/` |

## Fase 2: o que está pronto

| Item do PRD | Onde |
| --- | --- |
| `POST /api/playback/sessions`: exige e-mail confirmado (403), plano ativo (402) e mídia publicada e pronta (404); rate limit de 30/min por conta | `Bullet.Playback.start_session/4` |
| Fonte assinada com expiração de duração + 30 min, mínimo 5 min (RF01, RNF02) | `Media.Provider.playback_source/2` |
| Limite de telas por plano via Presence + lock por conta; 409 com as telas ativas; encerrar outra tela (RF07) | `Playback`, `PlaybackChannel`, `DELETE /api/playback/sessions/:id` |
| `SessionReaper` a cada 30 s fecha sessões sem player | `Playback.SessionReaper` |
| Progresso a cada 10 s pelo canal + `fetch keepalive` no `pagehide`; sincroniza entre dispositivos sem dar seek (RF03) | `save_progress/4`, `stores/progress.ts` |
| "Continuar assistindo" com uma query indexada (RF13) | `Playback.continue_watching/2` |
| Watermark em canvas (e-mail mascarado + código da sessão) que troca de posição a cada 20-60 s, com detecção de adulteração (RF06, RF14) | `WatermarkLayer.vue` |
| Autoplay do próximo episódio com contagem de 10 s e botão para pular a abertura (RF04) | `WatchView.vue`, `Catalog.next_media/1` |
| `PlayerEngine` (Strategy): `BunnyEmbedEngine` (Player.js) e `NativeEngine` (dev) | `frontend/src/engines/` |
| TTFF enviado para `POST /api/telemetry` → `:telemetry` (RNF01) | `PlaybackController.telemetry/2` |

## Fase 3 (sem gateway): LGPD e suporte

| Item | Onde |
| --- | --- |
| "Baixar meus dados" → JSON com todas as categorias (portabilidade) | `Accounts.export_user_data/1`, `GET /api/me/export` |
| "Excluir conta" com confirmação de senha: anonimiza, mantém CPF e assinaturas pelo prazo fiscal e desvincula o histórico | `Accounts.erase_user/1`, `DELETE /api/me` |
| Retenção diária: IP de reprodução 30 dias, eventos de segurança 90, webhooks 90; dispositivos inativos há 30 dias são aposentados | `Workers.PurgeExpiredData`, `Workers.PruneTokens` |
| Logs sem PII: `filter_parameters` para senha, CPF, e-mail e tokens (RNF09) | `config/config.exs` |
| Admin → Usuários (owner/suporte): busca por e-mail, id ou **código da watermark**; sessões, eventos por período, dispositivos | `Bullet.Support`, `Admin.UsersLive`, `Admin.UserLive` |
| Suspender conta: revoga todos os dispositivos e derruba os streams na hora; fica auditado (runbook 3) | `Accounts.suspend_user/3` |
| Owner concede plano manualmente pelo painel | `Admin.UserLive` |
| Rascunho do RIPD para o DPO | [`docs/lgpd/RIPD.md`](docs/lgpd/RIPD.md) |

**Gateway de pagamento:** adiado por decisão do PO. Assinaturas são concedidas manualmente pelo owner no painel ou pelo comando abaixo.

**Assinaturas** (o gateway entra depois). Até lá, o acesso é concedido manualmente:

```bash
bin/bullet eval 'Bullet.Release.grant_subscription("voce@exemplo.com", "padrao", 30)'      # prod
mix run -e 'Bullet.Billing.grant(Bullet.Accounts.get_user_by_email("voce@exemplo.com"), "padrao")'  # dev
```

**Vídeo em dev:** sem Bunny, o player usa `/dev/sample.mp4`. Gere com `./scripts/dev-sample-video.sh` (precisa de ffmpeg; o arquivo fica fora do git e da imagem).

**Primeiro owner** (a conta precisa existir; crie pelo cadastro do site):

```bash
# prod (Coolify → terminal do container)
bin/bullet eval 'Bullet.Release.promote("voce@exemplo.com", "owner")'
# dev
mix run -e 'Bullet.Accounts.set_role(Bullet.Accounts.get_user_by_email("voce@exemplo.com"), :owner)'
```

**Bunny:** em Stream → Library → Webhook URL, use `https://bullethub.app/webhooks/bunny`. Em dev, sem `BUNNY_API_KEY` o provider é o Fake e a tela de mídia mostra um botão "Simular upload + encoding". Com as variáveis do Bunny exportadas, o upload é real. O webhook não chega em localhost, mas o poller cobre.

**Gate da Fase 0 ainda aberto:** medir o TTFF p95 a partir de São Paulo nas redes Standard e Volume do Bunny, com 3 vídeos de teste, e registrar a decisão em ADR-003. Isso precisa da conta Bunny e fica fora do código.

## Documentação e contribuição

| Arquivo | O quê |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Contexto do monorepo para agentes (stack, contextos, comandos, segurança) |
| [`.claude/CLAUDE.md`](.claude/CLAUDE.md) · [`.claude/agents/`](.claude/agents) · [`.codex/agents/`](.codex/agents) | Contexto e agentes especializados (Claude / Codex) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Fluxo, gate de qualidade, convenções |
| [`backend/README.md`](backend/README.md) · [`frontend/README.md`](frontend/README.md) | Guias de dev de cada app |
| [`e2e/`](e2e) | Testes de navegador (Playwright: Chromium, Firefox, WebKit) |
| [`.pentest/`](.pentest) | Lab de segurança caixa-preta (adaptado do prostaff) |
| [`diagram.mmd`](diagram.mmd) | Diagrama de arquitetura (Mermaid) |
| [`docs/lgpd/RIPD.md`](docs/lgpd/RIPD.md) | Relatório de impacto (LGPD) |

## Desvios em relação ao PRD v4

- **Domínios:** o PRD ainda cita `play.bulletonrails.com` e `admin.bulletonrails.com`. Aqui se usa `bullethub.app` e `admin.bullethub.app`, o que também vale para o Allowed Domains do Bunny (RF05).
- **Infra:** a §13 fala em Hetzner + Caddy + Cloudflare. Aqui é Coolify + Traefik, como no prostaff. Se o Cloudflare entrar na frente, o `Plugs.RemoteIp` precisa passar a ler `CF-Connecting-IP`.
- **Player:** vale o ADR-002 (embed + Player.js), não a menção a hls.js no ADR-001.
- **`user_tokens.used_at`:** coluna extra, não prevista no §9. Ela é necessária para detectar reuso de refresh token (§10.1).
- **Escopo de conteúdo:** filmes, séries e animes. Não há cursos (decisão de 28/09/2026). Anime tem a mesma estrutura de série; `lesson` saiu do enum.
- **`media_assets.encoded_resolutions`:** é `text[]`, não jsonb.
- **`media_assets.status_changed_at`:** coluna extra, usada pelo poller e pelo timeout de 6 h.
- **`security_events`:** criada já na Fase 0 para registrar `login_failed`, `refresh_reused` e `device_revoked`.
- **Controles do player:** play e seek ficam com os controles do próprio embed do Bunny (a documentação não descreve como escondê-los). A UI nossa fica por cima: voltar, pular abertura, próximo episódio, tela cheia do wrapper e watermark. O iframe não recebe `fullscreen` nem `picture-in-picture`, para o vídeo nunca sair de baixo da watermark.
- **`sendBeacon` → `fetch keepalive`:** o `sendBeacon` não envia o header de autorização; o `fetch` com keepalive tem a mesma garantia de entrega no `pagehide`.
- **Refresh token:** reusar um token rotacionado dentro de 30 s é tratado como refresh abortado (navegação ou aba fechada), não como roubo. Depois disso, revoga o dispositivo.
- **Liveness de stream:** vem da Presence, não de heartbeat gravado no banco; `playback_sessions` ganhou `joined_at`.
- **Rate limit pensando em CGNAT:** o PRD pede 5/min por IP e por e-mail no login. Na prática, muitos usuários de operadora móvel compartilham o mesmo IP. Por isso: por **e-mail**, 5 **falhas**/min (login bem-sucedido não conta); por **IP**, 20/min no login, 300/min no refresh, 20/h no cadastro e na recuperação de senha.
- **Rate limit em ETS:** é exato com 1 nó. Com 2 ou mais nós, cada nó conta separado.
