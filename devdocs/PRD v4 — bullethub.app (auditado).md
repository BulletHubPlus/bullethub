# PRD v4 — bullethub.app (auditado)

dominio ja comprado bullethub.app

Sep 28, 2026 · @Michael · Versão 4.0 · Status: Em revisão

## 1. Auditoria das versões v1 → v3

A v3 está tecnicamente coerente na infra, mas mantém quatro premissas de segurança que não se sustentam e uma mudança de escopo não justificada (cursos → filmes/séries). A v4 corrige cada ponto abaixo e recompõe os requisitos.

| Item | v1 (25/09) | v2 (27/09) | v3 (27/09) | Veredito da auditoria |
| --- | --- | --- | --- | --- |
| Nome / domínio | BulletFlix, `bulletflix.com.br` | BulletOnRails, `play.bulletonrails.com` | bullethub.app | OK. O nome sugere Rails; a stack precisa ser decidida explicitamente (ADR-001). |
| Escopo de conteúdo | Cursos online | Cursos online | Filmes e séries | Mudança de produto sem nota. Filmes exigem licenciamento; cursos não. Decisão pendente do PO (seção 2). |
| RF01 ocultar URL | "ocultar completamente a URL" | idem | idem, via SDK/Hls.js | Impossível: o navegador precisa buscar o manifesto. Reescrito como URL assinada de curta duração + DRM. |
| RF05 domain lock | referrer `bulletflix.com.br` | Allowed Domains + 403 | idem, "bloqueado nativamente" | Referrer é spoofável fora do navegador (curl, apps). Vira controle secundário, não primário. |
| RF06 watermark | e-mail + CPF flutuante | idem | overlay HTML/CSS `pointer-events:none` "impede inspeção" | Falso: um `Delete` no DevTools remove o overlay. E expor CPF completo na tela viola minimização da LGPD. Reescrito. |
| RF07 sessões simultâneas | "localizações geográficas diferentes" | idem | idem | Geo por IP é inconfiável (CGNAT, VPN, 4G). Substituído por limite de streams ativos por conta via Presence. |
| RF08 upload | chunk upload | chunk upload | TUS obrigatório | Correto na v3. Falta: webhook de encoding, máquina de estados do asset, assinatura do upload. |
| RNF01 latência 1,5 s | declarado | declarado | "devido ao HLS" | Sem método de medição. v4 define TTFF medido no player (p95) e enviado por telemetria. |
| RNF03 10k simultâneos | só CDN | só CDN | só CDN | Ignora que RF03/RF07 exigem 10k conexões WebSocket abertas no app server. É o principal argumento de stack. |
| Modelo de dados | 4 tabelas | 4 tabelas | 4 tabelas, `Configurações_Bunny` separada | Faltam séries/temporadas, sessões de playback, assinaturas, eventos de webhook, auditoria, papéis de admin. |
| Custos Bunny | $0,01/GB storage, $0,005/GB CDN | idem | idem | Preço de CDN para América do Sul é maior que o citado. Verificado na seção 5. |
| Roadmap | 4 fases | 4 fases | 3 fases, sem fase de testes | v3 removeu homologação e antipirataria do roadmap. Restaurado com critérios de saída. |

## 2. Visão do produto e escopo

bullethub.app é uma plataforma VOD por assinatura, com experiência estilo Netflix, custo de infra mínimo (mídia 100% delegada ao Bunny Stream) e proteção antipirataria proporcional ao valor do conteúdo. O escopo de conteúdo fica parametrizado: o mesmo catálogo suporta cursos (curso → módulo → aula) e séries (série → temporada → episódio) através de uma hierarquia genérica `Collection → Season → Media`.

**Decisão pendente do PO:** confirmar se o lançamento é com conteúdo próprio (cursos) ou licenciado (filmes/séries). Isso muda o nível de DRM exigido por distribuidoras e o risco jurídico, não a arquitetura.

Fora de escopo da v4: live streaming, apps nativos (a PWA cobre mobile), downloads offline, legendas geradas por IA, recomendação personalizada por ML.

Personas:

- Assinante: assiste em web e mobile (PWA), retoma de onde parou em qualquer dispositivo, até 2 telas simultâneas.
- Administrador de conteúdo: sobe arquivos grandes (até 50 GB) de forma resiliente, organiza catálogo, acompanha status de encoding.
- Operador/segurança: acompanha tentativas de abuso (sessões excedentes, tokens expirados, watermark removido) e pode suspender contas.

## 3. ADR-001 — Stack: Elixir/Phoenix no backend, Vue 3 no cliente

**Decisão:** backend único em Elixir/Phoenix 1.7+ (API JSON + Channels + LiveView para o painel admin), frontend do assinante em Vue 3 + Vite (SPA/PWA em `play.bulletonrails.com`), PostgreSQL 16 como único banco. Ruby fica restrito a tooling (CLI de ingestão em lote com cliente TUS, scripts de migração) — não entra no caminho de produção.

**Por que não Rails como núcleo, apesar do nome:** os requisitos RF03 (progresso em tempo real), RF07 (limite de sessões simultâneas) e RNF03 (10k usuários) implicam \~10k conexões WebSocket persistentes com heartbeat. Isso é o caso de uso onde a BEAM domina: um único nó Phoenix em VPS de 4 GB sustenta essa carga, e `Phoenix.Presence` resolve o estado distribuído de sessões sem Redis. Em Rails o mesmo desenho exige Action Cable + Redis (ou AnyCable-go) e mais um processo para manter — contrário à premissa de custo mínimo.

| Critério | A. Phoenix + Vue (escolhida) | B. Rails + Vue + AnyCable | C. Híbrido (Phoenix realtime + Rails admin) |
| --- | --- | --- | --- |
| Conexões WebSocket 10k | Nativo, 1 nó | Redis + AnyCable-go obrigatórios | Nativo no lado Phoenix |
| Estado de sessões (RF07) | `Phoenix.Presence` (CRDT, sem Redis) | Redis + expiração manual | Presence |
| Jobs (webhooks, e-mail, limpeza) | Oban sobre Postgres | Sidekiq + Redis | Dois sistemas de jobs |
| Admin CRUD | LiveView (rápido, sem JS extra) | ActiveAdmin/Avo (mais maduro) | Avo |
| Custo de infra mensal (app) | 1 VPS + Postgres | 1 VPS + Postgres + Redis | 2 apps + Postgres + Redis |
| Velocidade inicial de entrega | Média (menos gems prontas) | Alta | Baixa (duas bases, dois deploys) |
| Risco operacional | 1 runtime | 2 runtimes (Ruby + Go) | 2 runtimes + contrato entre apps |

A opção B é viável se o time for Rails-first e aceitar Redis como dependência; nesse caso a seção 10 (canais) se mantém com AnyCable. A opção C é rejeitada: duplica autenticação, deploy e modelo de dados para ganhar apenas o ActiveAdmin.

**Vue 3 no cliente:** Composition API + Pinia + Vue Router, `hls.js` como engine de player (HLS nativo no Safari via detecção de suporte). LiveView não é usado no cliente do assinante porque o player, a watermark e o ABR são estado puramente do navegador; um SPA evita round-trips ao servidor a cada interação de UI.

## 4. Arquitetura de referência

Nenhum byte de vídeo atravessa o app server: o navegador busca HLS direto na CDN com um token que o backend assinou, e o admin envia arquivos direto ao Bunny Stream via TUS. O Phoenix só autentica, assina, registra progresso e mantém o estado de sessões.

&#91;embedded content: arquitetura de referência · 7 componentes\]

O Phoenix não fala com a CDN em runtime: ele e a CDN compartilham a chave de Token Authentication, e a CDN valida a assinatura sozinha.

### Design patterns adotados

| Padrão | Onde | Motivo |
| --- | --- | --- |
| Bounded contexts (Phoenix Contexts) | `Accounts`, `Billing`, `Catalog`, `Ingest`, `Playback`, `Security` | Cada contexto expõe funções públicas; schemas Ecto nunca vazam entre contextos. |
| Ports & Adapters (Behaviour) | `Bullet.Media.Provider` com `Bunny` e `Fake` | Testes sem rede; troca de provedor sem tocar no domínio. |
| Anti-corruption layer | `Bullet.Ingest.BunnyWebhook` normaliza payload em `MediaAssetEvent` | Vocabulário do Bunny (status 0–5) não contamina o domínio. |
| Máquina de estados | `MediaAsset.status` com `Ecto.Enum` e transições validadas | Impede "ready" sem encoding e publicação de asset quebrado. |
| Idempotent consumer | tabela `webhook_events` com unique em `(provider, event_id)` | Bunny reenvia webhooks; processar duas vezes não pode duplicar efeito. |
| Transactional outbox (leve) | Oban jobs enfileirados na mesma transação Ecto | E-mail, invalidação de cache e auditoria nunca ficam órfãos. |
| Presence (CRDT) | `Bullet.Playback.Presence` por `user:<id>` | Limite de streams sem Redis e tolerante a partição. |
| Token service puro | `Bullet.Security.PlaybackToken.sign/3` sem efeitos colaterais | Testável por propriedade; auditável. |
| Strategy (front) | `usePlayerEngine`: `HlsJsEngine` vs `NativeHlsEngine` | Safari usa HLS nativo; demais navegadores usam hls.js. |
| Facade (front) | `api/client.ts` único ponto de HTTP com refresh de token | Componentes nunca chamam `fetch` direto. |
| Rate limiting | Hammer no endpoint `/playback/token` | Limita enumeração de tokens por conta comprometida. |

## 5. Integração Bunny.net e custos reais

O custo de entrega no Brasil pela rede Standard é $0,045/GB, nove vezes o valor citado nas v1–v3 ($0,005/GB, que é a rede Volume). A escolha do tier de entrega é a decisão de custo mais importante do projeto e deve ser validada com medição de latência em Fase 1.

### 5.1 Preços oficiais (as of 28/09/2026)

| Item | Preço | Fonte |
| --- | --- | --- |
| Storage (região padrão Frankfurt) | $0,01/GB/mês; cada resolução habilitada é armazenada separadamente | [Bunny Stream Pricing](https://bunny.net/docs/stream/pricing) |
| CDN Standard — Europa e América do Norte | $0,010/GB | idem |
| CDN Standard — América do Sul | $0,045/GB | idem |
| CDN Volume (rede menor, tarifa global) | $0,005/GB até 500 TB/mês | idem |
| Encoding H.264 até 1080p | incluído | idem |
| MediaCage Basic DRM | incluído; só funciona no player embed do Bunny | [Security options](https://docs.bunny.net/stream/security-options) |
| MediaCage Enterprise DRM (Widevine/FairPlay) | $99/mês por biblioteca + $0,005 por licença (até 20k/mês) | [Bunny Stream Pricing](https://bunny.net/docs/stream/pricing) |

### 5.2 Estimativa de custo mensal (cenário hipotético)

Premissas: 5.000 assinantes ativos, 20 h assistidas por assinante por mês, média de 1,5 GB/h (mix 720p/1080p), catálogo de 200 h em 4 resoluções (\~5,7 GB/h).

| Componente | Cálculo | Custo/mês |
| --- | --- | --- |
| Entrega, rede Standard (BR) | 150.000 GB × $0,045 | $6.750 |
| Entrega, rede Volume | 150.000 GB × $0,005 | $750 |
| Storage | 1.140 GB × $0,01 | $11 |
| Enterprise DRM (opcional) | $99 + 200k licenças escalonadas | \~$820 |
| App server + Postgres (Hetzner CX32 + backup) | fixo | \~$25 |

A rede Volume tem menos PoPs que a Standard. Fase 1 deve medir TTFF p95 a partir de São Paulo nas duas redes antes de fixar o tier; se a Volume não atender RNF01, o custo de entrega sobe 9×.

### 5.3 ADR-002 — Player: embed do Bunny com Player.js, não hls.js

**Decisão:** o player do assinante usa o iframe embed do Bunny controlado via [Player.js](https://docs.bunny.net/stream/playback-api), com controles nativos ocultos e UI própria em Vue por cima. Motivo: o MediaCage Basic (DRM gratuito, anti-download) só atua no player embed; com hls.js e URLs diretas o vídeo fica baixável por qualquer um com token válido durante a janela de expiração.

| Critério | Embed + Player.js (escolhida) | hls.js + CDN Token Auth |
| --- | --- | --- |
| Anti-download básico | MediaCage Basic incluído | Nenhum; precisa Enterprise DRM |
| Controle de UI | Parcial: controles via API, UI própria sobreposta | Total |
| Eventos de progresso | `timeupdate`, `ended`, `play`, `pause` via Player.js | Nativos do `<video>` |
| Watermark | Overlay Vue sobre o iframe (`pointer-events: none`) | Overlay sobre o `<video>` |
| Autenticação | Embed token: `SHA256_HEX(key + video_id + expires)` | Token de path no Pull Zone |
| Upgrade para Widevine/FairPlay | Nativo no embed | Não documentado para player custom |

Se a hierarquia de UI exigir controles que o Player.js não expõe (ex.: seleção manual de faixa de áudio), reabrir esta ADR; a alternativa é hls.js + Enterprise DRM.

### 5.4 Fluxo de upload (RF08)

1. Admin escolhe o arquivo no painel LiveView e informa metadados.
2. Backend chama `POST /library/{id}/videos` no Bunny para criar o objeto e obter `videoId`; grava `media_assets` com status `uploading`.
3. Backend gera `AuthorizationSignature = SHA256(library_id + api_key + expire + video_id)` e `AuthorizationExpire` (now + 24 h) e devolve ao navegador junto com `LibraryId` e `VideoId` ([TUS docs](https://docs.bunny.net/stream/tus-resumable-uploads)).
4. Navegador envia o arquivo com `tus-js-client` direto para `https://video.bunnycdn.com/tusupload`, em chunks, com retomada por fingerprint em `localStorage`.
5. Bunny transcodifica e envia webhook a `POST /webhooks/bunny`; o backend valida a assinatura, grava em `webhook_events` (idempotente) e transiciona o asset para `processing` → `ready` ou `failed`.
6. LiveView recebe `PubSub` e atualiza o status na tela sem polling.

A API key da biblioteca nunca sai do backend. A assinatura é válida só para aquele `videoId`.

### 5.5 Fluxo de playback (RF01, RNF02)

1. SPA chama `POST /api/playback/sessions` com `media_id` e `device_id`.
2. Backend verifica assinatura ativa, limite de streams (Presence), e gera `token` + `expires`. Expiração: `now + duração_da_mídia + 30 min`, nunca menos de 5 min, para o token não expirar no meio de um filme de 2 h.
3. Backend responde com a URL do embed assinada, o `session_id` e a configuração da watermark.
4. SPA monta o iframe, conecta Player.js, entra no canal `playback:<session_id>` e começa a enviar heartbeats.
5. Ao terminar ou fechar a aba, o canal cai e a Presence libera a vaga em até 30 s.

Endpoint de token protegido por rate limit de 30 req/min por conta.

## 6. Requisitos funcionais v4

Cada requisito abaixo tem um critério de aceite verificável em teste automatizado ou homologação. Os RF01–RF08 mantêm a numeração das versões anteriores com o texto corrigido; RF09–RF15 são novos.

| ID | Requisito | Critério de aceite |
| --- | --- | --- |
| RF01 | Player com UI própria sobre o embed do Bunny; a URL assinada tem validade limitada e é obtida só via `POST /api/playback/sessions` autenticado | Copiar a URL do iframe e abrir em outra aba após `expires` retorna 403; sem sessão válida o endpoint retorna 401 |
| RF02 | ABR automático (360p–1080p) delegado ao encoder e player do Bunny | Em throttling de 1,5 Mbps o player cai para ≤480p sem parar a reprodução |
| RF03 | Progresso salvo a cada 10 s e em `pause`/`ended`/`beforeunload` (via `sendBeacon`), sincronizado entre dispositivos pelo canal `user:<id>` | Pausar no desktop e abrir no celular retoma no mesmo segundo ±10 s |
| RF04 | Autoplay do próximo item da coleção com contagem de 10 s e botão cancelar; pula abertura se `intro_end_seconds` existir | Ao terminar o episódio 1, o episódio 2 inicia sozinho em ≤12 s |
| RF05 | Allowed Domains no Bunny restrito a `bulletonrails.com` e `play.bulletonrails.com`, como controle secundário ao token | Embed em domínio externo retorna 403 mesmo com token válido |
| RF06 | Watermark dinâmica: e-mail mascarado + código curto da sessão (6 chars, rastreável em `playback_sessions`), posição e opacidade aleatórias a cada 20–60 s; nunca o CPF | Um frame gravado permite identificar a conta pelo código da sessão em ≤1 min de consulta ao banco |
| RF07 | Limite de streams simultâneos por plano (Básico 1, Padrão 2, Família 4) via Presence; ao exceder, o novo pedido recebe 409 com a lista de sessões ativas e opção de encerrar uma | Terceira tela num plano de 2 é bloqueada em ≤5 s; encerrar uma libera a vaga em ≤30 s |
| RF08 | Upload TUS direto ao Bunny com assinatura do backend, retomável após fechar o navegador, arquivos até 50 GB | Interromper rede aos 40% e reconectar retoma sem reenviar os chunks concluídos |
| RF09 | Catálogo hierárquico genérico: `Collection` (curso ou série) → `Season` (módulo ou temporada) → `Media` (aula ou episódio), com filme = Media sem coleção | Admin cria uma série de 2 temporadas e um curso de 3 módulos com o mesmo formulário |
| RF10 | Status de encoding visível no painel em tempo real (uploading → processing → ready/failed) via webhook + PubSub | Status muda na tela ≤5 s após o webhook, sem reload |
| RF11 | Autenticação: e-mail + senha (Argon2id), verificação de e-mail, reset de senha, refresh token rotativo, dispositivos nomeados com revogação | Revogar um dispositivo derruba seu WebSocket em ≤10 s |
| RF12 | Assinaturas: planos, status (`trialing`, `active`, `past_due`, `canceled`), integração com gateway via webhook idempotente; `past_due` mantém acesso por 3 dias | Webhook duplicado não cria duas transições |
| RF13 | "Continuar assistindo" e "Próximos" calculados por query indexada, sem tabela materializada | Home carrega em ≤300 ms p95 com 10k usuários e 1M linhas de progresso |
| RF14 | Auditoria de segurança: eventos `session_limit_hit`, `token_expired`, `watermark_tampered`, `device_revoked` com IP, UA e `user_id` | Cada evento consultável no painel por conta e período |
| RF15 | Painel admin (LiveView) com papéis `owner`, `editor`, `support`; `support` só lê e suspende contas | `editor` não consegue acessar a tela de assinaturas |

## 7. Modelo de ameaças antipirataria

Nenhum controle do lado do cliente impede gravação de tela; a estratégia é tornar cada cópia rastreável até a conta e cara de produzir. As v1–v3 tratavam overlay e referrer como bloqueios; a v4 os classifica como dissuasão e coloca o peso em token, DRM e sessões.

| Ameaça | Controle | O que protege de fato | O que não protege |
| --- | --- | --- | --- |
| Copiar a URL do vídeo (F12, extensões) | Embed token com expiração curta + rate limit no endpoint | Link não funciona fora da janela nem sem sessão | Download dentro da janela por quem já tem sessão válida |
| Baixar o HLS com ferramenta (yt-dlp, IDM) | MediaCage Basic no embed | Bloqueia downloaders genéricos | Ataques dedicados ao player; para isso, Enterprise DRM |
| Embed do vídeo em site pirata | Allowed Domains + token | Bloqueia iframe em outro domínio | Cliente fora do navegador com Referer forjado (por isso o token é o controle primário) |
| Compartilhar a conta | Limite de streams por plano via Presence + dispositivos nomeados | Contas com mais telas que o plano | Duas pessoas revezando a mesma tela |
| Gravar a tela (OBS, celular) | Watermark com código de sessão; auditoria em `playback_sessions` | Identifica a conta de origem em qualquer frame | A gravação em si |
| Remover a watermark no DevTools | `MutationObserver` no container: se o nó sumir ou opacidade mudar, pausa e emite `watermark_tampered` | Eleva o custo e registra a tentativa | Atacante que reescreve o bundle JS; assumido como aceitável |
| Abusar do endpoint de token para enumerar mídia | Rate limit 30/min por conta + autorização por assinatura + `media.status = ready` | Enumeração em massa | Um usuário legítimo lento |
| Webhook forjado marcando asset como `ready` | Validação de assinatura HMAC do Bunny + IP allowlist opcional + idempotência | Transições falsas | Comprometimento da API key (rotação trimestral) |

**Regra de decisão para DRM Enterprise:** ativar quando o valor do catálogo justificar $99/mês + licenças, ou quando uma distribuidora exigir Widevine/FairPlay. Para cursos próprios, MediaCage Basic + watermark é suficiente.

**Watermark: por que não o CPF.** Um frame gravado circula publicamente; imprimir o CPF completo nele expõe dado pessoal do próprio assinante (LGPD, minimização). O código de sessão de 6 caracteres cumpre a mesma função de rastreio sem expor nada. O e-mail aparece mascarado (`ca***@gmail.com`) como dissuasão visível.

## 8. Requisitos não-funcionais

Todo RNF tem métrica, método de medição e limiar; o que não é medido não entra no critério de saída de fase.

| ID | Requisito | Métrica e método | Limiar |
| --- | --- | --- | --- |
| RNF01 | Time-to-first-frame | `play` → primeiro `timeupdate` no Player.js, enviado em lote por `navigator.sendBeacon` a `/api/telemetry`; agregado por Telemetry/PromEx | p95 ≤ 1,5 s em banda larga; p95 ≤ 2,5 s em 4G |
| RNF02 | Segurança de endpoints | Token expira em `duração + 30 min`; sem token válido, 403 no Bunny; chave de assinatura só em `runtime.exs` via env | 0 URLs reproduzíveis após expiração em teste automatizado |
| RNF03 | Escala de entrega | Delegada ao Bunny; teste de carga k6 com 10k sessões virtuais contra `play.bulletonrails.com` | 0 erros 5xx na CDN; rebuffer ratio ≤ 1% |
| RNF04 | Escala do app server | 10k WebSockets abertos com heartbeat de 15 s em 1 nó Phoenix; `:observer` e PromEx | CPU ≤ 60%, memória ≤ 2 GB, latência de join ≤ 200 ms p95 |
| RNF05 | Latência da API | `GET /api/catalog/home` e `POST /api/playback/sessions` | ≤ 300 ms p95 sob 500 req/s |
| RNF06 | Disponibilidade | Uptime do app medido por healthcheck externo (1 min) | ≥ 99,5%/mês (≈3,6 h de indisponibilidade) |
| RNF07 | Recuperação | Backup Postgres diário + WAL; restore testado por trimestre | RPO ≤ 15 min; RTO ≤ 1 h |
| RNF08 | Segurança de aplicação | OWASP ASVS nível 2; `mix sobelow`, `mix deps.audit`, `npm audit` no CI | 0 achados críticos no merge |
| RNF09 | Privacidade | CPF cifrado em repouso (`cloak_ecto`, AES-GCM); logs sem PII | Auditoria de logs sem e-mail/CPF em texto |
| RNF10 | Observabilidade | Traços OpenTelemetry por request e por job Oban; Sentry para exceções | 100% dos endpoints com span; alerta em erro > 1%/5 min |
| RNF11 | Compatibilidade | Chrome, Firefox, Edge, Safari (últimas 2 versões), iOS 16+, Android 10+ | Suite Playwright verde nos 4 navegadores |
| RNF12 | Acessibilidade | WCAG 2.1 AA no player e no catálogo (teclado, foco, legendas) | Axe sem violações sérias |

## 9. Modelo de dados v4

Doze tabelas em PostgreSQL 16, UUID v7 como chave primária (ordenável por tempo), `inserted_at`/`updated_at` em todas. A tabela `Configurações_Bunny` da v3 vira `media_assets`, que é 1:1 com `media` mas separada porque tem ciclo de vida próprio (upload, encoding, reprocessamento).

| Tabela (contexto) | Colunas principais | Índices e restrições |
| --- | --- | --- |
| `users` (Accounts) | `email` citext, `password_hash`, `name`, `cpf_encrypted` bytea, `cpf_hash` (HMAC para unicidade), `role` enum(`subscriber`,`support`,`editor`,`owner`), `confirmed_at`, `suspended_at` | unique `email`; unique `cpf_hash` |
| `user_tokens` (Accounts) | `user_id`, `token` bytea, `context` (`session`,`refresh`,`confirm`,`reset`), `sent_to`, `device_id` | unique (`context`,`token`); index `user_id` |
| `devices` (Accounts) | `user_id`, `name`, `user_agent`, `last_seen_at`, `revoked_at` | index (`user_id`, `revoked_at`) |
| `plans` (Billing) | `slug`, `name`, `price_cents`, `max_streams` int, `active` | unique `slug` |
| `subscriptions` (Billing) | `user_id`, `plan_id`, `status` enum(`trialing`,`active`,`past_due`,`canceled`), `gateway`, `gateway_ref`, `current_period_end` | unique `gateway_ref`; index (`user_id`,`status`) |
| `collections` (Catalog) | `kind` enum(`course`,`series`), `title`, `slug`, `description`, `thumbnail_url`, `published_at` | unique `slug`; index `published_at` |
| `seasons` (Catalog) | `collection_id`, `number`, `title` | unique (`collection_id`,`number`) |
| `media` (Catalog) | `kind` enum(`movie`,`episode`,`lesson`), `collection_id` null, `season_id` null, `position`, `title`, `synopsis`, `thumbnail_url`, `intro_end_seconds`, `published_at` | unique (`season_id`,`position`); check: `movie` sem `collection_id` |
| `media_assets` (Ingest) | `media_id`, `bunny_video_id`, `status` enum(`uploading`,`processing`,`ready`,`failed`), `duration_seconds`, `encoded_resolutions` jsonb, `storage_bytes`, `error` | unique `media_id`; unique `bunny_video_id` |
| `webhook_events` (Ingest, Billing) | `provider` (`bunny`,`gateway`), `event_id`, `payload` jsonb, `processed_at`, `error` | unique (`provider`,`event_id`) |
| `watch_progress` (Playback) | `user_id`, `media_id`, `position_seconds`, `completed` bool, `updated_at` | unique (`user_id`,`media_id`); index (`user_id`,`updated_at desc`) para "continuar assistindo" |
| `playback_sessions` (Playback) | `user_id`, `media_id`, `device_id`, `code` char(6), `ip`, `started_at`, `last_heartbeat_at`, `ended_at`, `end_reason` | unique `code`; index (`user_id`,`ended_at`) |
| `security_events` (Security) | `user_id` null, `kind`, `ip`, `user_agent`, `metadata` jsonb | index (`user_id`,`inserted_at desc`); particionar por mês a partir de 10M linhas |

### Máquina de estados de `media_assets.status`

| De | Para | Gatilho | Efeito |
| --- | --- | --- | --- |
| — | `uploading` | Admin inicia upload; vídeo criado no Bunny | Assinatura TUS emitida |
| `uploading` | `processing` | Webhook status "queued/processing" ou TUS concluído | PubSub para o painel |
| `processing` | `ready` | Webhook status "finished" | `duration_seconds` e resoluções preenchidos; `media` pode ser publicada |
| `processing` | `failed` | Webhook status "failed"/"error" ou timeout de 6 h via Oban | Alerta ao admin; botão "reprocessar" |
| `failed` | `uploading` | Admin reenvia | Novo `bunny_video_id` |

Qualquer outra transição é rejeitada no changeset com erro `invalid_transition`. `media.published_at` só pode ser preenchido se o asset estiver `ready` (validação cross-context em `Catalog.publish_media/1`).

### Decisões de modelagem

- CPF: `cpf_encrypted` para exibição ao próprio usuário e nota fiscal; `cpf_hash` (HMAC-SHA256 com chave separada) para garantir unicidade sem descriptografar.
- Progresso é upsert (`on_conflict: replace`), não histórico; quem precisar de histórico usa `playback_sessions`.
- `plans.max_streams` é a única fonte para RF07; não duplicar no código.
- Sem soft delete genérico: `suspended_at`, `revoked_at`, `ended_at` são explícitos por tabela.

## 10. API REST e canais realtime

A API JSON serve o SPA; tudo que é tempo real (progresso, limite de streams, status de encoding) vai por Phoenix Channels. Autenticação por Bearer token de acesso (15 min) + refresh token rotativo em cookie `HttpOnly` (30 dias), o que evita XSS roubando sessão longa.

### 10.1 Endpoints

| Método e rota | Contexto | Resposta | Regras |
| --- | --- | --- | --- |
| `POST /api/auth/register` | Accounts | 201 `{user}` | Envia e-mail de confirmação; CPF validado por dígito verificador |
| `POST /api/auth/login` | Accounts | 200 `{access_token, user}` + cookie refresh | Rate limit 5/min por IP e e-mail |
| `POST /api/auth/refresh` | Accounts | 200 `{access_token}` | Rotaciona refresh; reuso de refresh antigo revoga a família inteira |
| `GET /api/me/devices` · `DELETE /api/me/devices/:id` | Accounts | 200 | Revogar dispositivo derruba seus sockets via PubSub |
| `GET /api/catalog/home` | Catalog | 200 `{continue_watching, rows[]}` | Cache ETag por usuário; só mídia `published` com asset `ready` |
| `GET /api/catalog/collections/:slug` | Catalog | 200 `{collection, seasons[], media[]}` | Inclui `progress` por mídia para o usuário |
| `POST /api/playback/sessions` | Playback | 201 `{session_id, code, embed_url, expires, watermark}` | 402 sem assinatura ativa; 409 `stream_limit` com `active_sessions[]` |
| `DELETE /api/playback/sessions/:id` | Playback | 204 | Permite encerrar outra sessão da própria conta (RF07) |
| `PUT /api/progress/:media_id` | Playback | 204 | Fallback HTTP do canal; aceita `sendBeacon` |
| `POST /api/telemetry` | Playback | 202 | Lote de eventos QoE (TTFF, rebuffer); sem PII |
| `POST /webhooks/bunny` | Ingest | 200 | Sem auth de usuário; valida assinatura; idempotente |
| `POST /webhooks/billing` | Billing | 200 | idem |
| `GET /health` | Plataforma | 200 | Checa Postgres e fila Oban |

Admin não tem API JSON: LiveView fala direto com os contextos, autenticado por sessão de cookie separada em `admin.bulletonrails.com`.

### 10.2 Canais

| Tópico | Quem entra | Eventos cliente → servidor | Eventos servidor → cliente |
| --- | --- | --- | --- |
| `user:<user_id>` | Todo dispositivo logado | — | `progress_updated {media_id, position}`, `device_revoked`, `subscription_changed` |
| `playback:<session_id>` | Um player ativo | `heartbeat {position}` a cada 15 s; `progress {position}` a cada 10 s; `event {kind}` (ex.: `watermark_tampered`) | `session_terminated {reason}` (limite excedido, dispositivo revogado, assinatura cancelada) |
| `admin:ingest` | Painel admin | — | `asset_status {media_id, status}` |

### 10.3 Presence para RF07

`Bullet.Playback.Presence` rastreia `user:<id>` com metadados `{session_id, media_id, device_id, started_at}`. Ao criar sessão, `Presence.list/1` conta entradas ativas e compara com `plans.max_streams`. Um GenServer `SessionReaper` varre a cada 30 s e encerra sessões sem heartbeat há mais de 45 s, gravando `end_reason = timeout`. Em cluster com 2+ nós, a Presence converge por CRDT sem Redis; a decisão de limite é feita no nó que recebe o pedido e pode admitir um excesso de curta duração em partição de rede — aceito como tradeoff.

### 10.4 Formato de erro

`{ "error": { "code": "stream_limit", "message": "...", "details": {} } }` com `code` estável para o SPA; mensagens em pt-BR via Gettext.

## 11. Frontend Vue 3

SPA em Vue 3.5 + TypeScript + Vite, servida como PWA em `play.bulletonrails.com`, com Pinia para estado, Vue Router com guards e `phoenix` (npm) para canais. Sem framework de UI pesado: Tailwind + componentes próprios, porque a identidade "Netflix style" não sai de um kit pronto.

### Estrutura de pastas

```text
src/
  api/           client.ts (Facade: fetch + refresh automático + erro tipado)
  stores/        auth.ts · catalog.ts · player.ts · sessions.ts (Pinia)
  composables/   usePlayerEngine · useWatermark · useProgressSync · usePresenceChannel · useAutoplayNext
  engines/       BunnyEmbedEngine.ts (Player.js) · interface PlayerEngine
  components/    player/ · catalog/ · shell/
  views/         Home · Collection · Watch · Account · Devices
  router/        guards: requireAuth, requireSubscription
```

### Padrões e decisões

| Decisão | Como | Por quê |
| --- | --- | --- |
| `PlayerEngine` como interface (Strategy) | `play()`, `pause()`, `seek(s)`, `on(event)`, `destroy()`; hoje só `BunnyEmbedEngine` | Trocar para hls.js + Enterprise DRM sem tocar em componentes |
| Watermark como componente irmão do iframe, não filho | `<WatermarkLayer>` posicionado `absolute` sobre o `<iframe>`, `pointer-events: none`, `z-index` alto; texto renderizado em `<canvas>` para dificultar `Ctrl+F` no DOM | Overlay dentro do iframe é impossível (cross-origin); irmão funciona |
| Tamper detection | `MutationObserver` no wrapper + `ResizeObserver` no canvas; se removido/ocultado, `engine.pause()` e `channel.push('event', {kind: 'watermark_tampered'})` | RF14 e dissuasão |
| Progresso | `useProgressSync` faz `push('progress')` a cada 10 s (throttle) e `sendBeacon` em `pagehide`; ao receber `progress_updated` de outro dispositivo, atualiza a store sem seek automático | Evita seek surpresa em quem está assistindo |
| Sessão e limite | `sessions` store guarda `active_sessions[]` do 409 e mostra modal "Encerrar outra tela" | UX igual à da Netflix |
| Autoplay | `useAutoplayNext` escuta `ended`, busca `next_media` da store, contagem 10 s, cancelável; respeita `prefers-reduced-motion` | RF04 |
| Auth | Access token só em memória (Pinia), refresh em cookie `HttpOnly`; `client.ts` faz retry único em 401 | Reduz superfície de XSS |
| Rotas | `requireSubscription` checa `status in [active, trialing, past_due]` antes de `/watch/:id` | Feedback antes de gastar um token de playback |
| Performance | Lazy routes, `<img loading="lazy">`, thumbnails via Bunny Optimizer com `?width=`, prefetch da rota `Watch` ao hover no card | LCP ≤ 2,5 s na Home |
| Testes | Vitest para composables e stores; Playwright para Watch (com iframe mockado via `page.route`) | RNF11 |
| Build | `vite build` gera `dist/` servido pelo próprio Phoenix (`Plug.Static`) atrás do Cloudflare; sem Vercel | Um deploy, um domínio, CORS trivial |

### Watermark: composição e ritmo

Texto: `ca***@gmail.com · 7K3Q9F` (e-mail mascarado + código da sessão). A cada 20–60 s (aleatório com `crypto.getRandomValues`) muda de posição entre 9 zonas e opacidade entre 0,25 e 0,45; fonte 14–16 px. O código da sessão vem do backend na resposta de `POST /api/playback/sessions`, nunca é calculado no cliente.

## 12. LGPD e conformidade

O produto coleta CPF, e-mail, IP e hábitos de consumo; cada um precisa de base legal, retenção e forma de descarte definidas antes do lançamento. Isto não é aconselhamento jurídico; o DPO deve validar a tabela.

| Dado | Finalidade | Base legal provável | Retenção | Proteção |
| --- | --- | --- | --- | --- |
| CPF | Nota fiscal, unicidade de conta, antifraude | Execução de contrato; obrigação legal (fiscal) | Enquanto houver relação + 5 anos (fiscal) | Cifrado em repouso; exibido só ao titular e ao `owner` |
| E-mail | Autenticação, comunicação | Execução de contrato | Enquanto houver conta | Mascarado na watermark e nos logs |
| IP e user agent | Segurança, limite de sessões | Legítimo interesse | 90 dias em `security_events`; 30 dias em `playback_sessions` | Job Oban de expurgo mensal |
| Progresso e histórico | Funcionalidade do serviço | Execução de contrato | Enquanto houver conta | — |
| Telemetria QoE | Melhoria do serviço | Legítimo interesse | 180 dias agregada; eventos brutos 30 dias | Sem `user_id`, só `session_id` truncado |

Direitos do titular implementados como funções de contexto, não como processo manual:

- `Accounts.export_user_data/1` gera JSON com todos os dados do titular em ≤ 15 dias (prazo LGPD).
- `Accounts.erase_user/1` anonimiza `users` (mantém `cpf_hash` e dados fiscais pelo prazo legal), apaga `watch_progress` e `devices`, e desvincula `playback_sessions`.
- Consentimento de cookies só para analytics de terceiros, se houver; cookies de sessão são estritamente necessários.

Watermark com CPF (v1–v3) foi removida por violar minimização (art. 6º, III): um frame vazado exporia o dado do próprio titular.

Bunny.net armazena vídeo em Frankfurt por padrão; a transferência internacional de dados pessoais não ocorre porque nenhum dado do assinante vai ao Bunny (o token é opaco). Registrar isso no relatório de impacto (RIPD).

## 13. Observabilidade, operação e custo do app

Um nó Phoenix numa VPS de 4 vCPU/8 GB, Postgres gerenciado ou no mesmo host com backup externo, Cloudflare na frente. Custo fixo de aplicação abaixo de $40/mês; o custo variável é todo do Bunny (seção 5).

| Componente | Escolha | Custo/mês | Observação |
| --- | --- | --- | --- |
| App server | Hetzner CX32 (4 vCPU, 8 GB) | \~$15 | Suporta RNF04 com folga; segundo nó só para HA |
| Postgres | Mesmo host + `pgbackrest` para Bunny Storage; ou Neon/Supabase | $0–$20 | Backup diário + WAL (RNF07) |
| Proxy/TLS | Cloudflare Free (proxy laranja) + Caddy no host | $0 | WebSocket passa pelo Cloudflare sem config extra |
| Deploy | `mix release` em imagem Docker; `docker compose` com healthcheck; GitHub Actions | $0 | Migrações via `release.eval` antes do swap |
| Erros | Sentry (plano dev) | $0–$26 | Backend e SPA |
| Métricas | PromEx + Grafana Cloud Free | $0 | Dashboards: TTFF, rebuffer, sessões ativas, fila Oban, latência API |
| Uptime | Better Stack ou UptimeRobot | $0 | Healthcheck de 1 min (RNF06) |
| E-mail transacional | Resend ou Postmark via Swoosh | $0–$15 | Confirmação, reset, avisos de sessão |

### Telemetria mínima

- `bullet.playback.ttff` (histograma, ms) por tier de CDN e por região; é o dado de RNF01 e da decisão Standard vs Volume.
- `bullet.playback.rebuffer_ratio` por mídia; identifica encodings ruins.
- `bullet.sessions.active` (gauge, da Presence) e `bullet.sessions.limit_hit` (contador).
- `bullet.ingest.asset_status` transições por status; alerta se `failed` > 5% em 1 h.
- `oban.job.exception` e tamanho de fila; alerta se fila > 500 por 10 min.

### Runbooks obrigatórios antes do go-live

1. Rotação da API key do Bunny e da chave de embed token (sem downtime: aceitar duas chaves por 24 h).
2. Restore do Postgres a partir do backup em host limpo.
3. Suspensão de conta por abuso e revogação de todos os dispositivos.
4. Reprocessamento de asset `failed` e limpeza de resoluções órfãs no Bunny.

## 14. Roadmap v4

Onze semanas para um time de 2 desenvolvedores (1 Elixir, 1 Vue) mais o PO; a fase de homologação removida na v3 volta como gate obrigatório de go-live.

&#91;embedded content: roadmap v4 · 5 fases, 5 gates\]

Nenhuma fase começa sem o gate anterior fechado; o gate 1 (tier de CDN) é o único que pode reabrir o orçamento.

| Fase | Entregáveis | Critério de saída |
| --- | --- | --- |
| 0 · Fundação | Phoenix com Accounts (registro, login, refresh, dispositivos), CI com Sobelow/Credo/Dialyzer, biblioteca Bunny criada, Allowed Domains e embed token ativos, `Bullet.Media.Provider` com adapter Fake | TTFF p95 medido de São Paulo nas redes Standard e Volume com 3 vídeos de teste; decisão de tier registrada em ADR-003 |
| 1 · Ingest | LiveView de upload TUS, `media_assets` com máquina de estados, webhook idempotente, catálogo `Collection/Season/Media` | Upload de 50 GB interrompido e retomado; webhook reenviado 3× gera 1 transição |
| 2 · Playback | SPA (Home, Collection, Watch), `BunnyEmbedEngine`, `POST /playback/sessions`, canais `user:` e `playback:`, Presence + `SessionReaper`, watermark + tamper detection, autoplay | RF01–RF07 e RF09–RF11 com testes de aceite verdes em Playwright |
| 3 · Billing e LGPD | Planos, gateway (Stripe ou Asaas), webhook idempotente, `export_user_data`, `erase_user`, expurgo de logs, RIPD | Webhook duplicado não duplica transição; export em JSON valida; RIPD aprovado pelo DPO |
| 4 · Homologação | k6 com 10k sessões, pentest externo, Playwright nos 4 navegadores, runbooks executados, dashboards Grafana | RNF01–RNF12 dentro do limiar; 0 achados críticos no pentest |

## 15. Riscos e decisões pendentes

Três decisões do PO travam o orçamento e o escopo jurídico; as demais são riscos técnicos com mitigação já no roadmap.

### Decisões pendentes do product owner

- [ ] Conteúdo de lançamento: cursos próprios ou filmes/séries licenciados? Define se Enterprise DRM entra no orçamento.
- [ ] Tier de CDN: aceitar a rede Volume (9× mais barata) se o TTFF p95 ficar ≤ 2 s em Fase 0, ou pagar Standard?
- [ ] Planos e limites de streams: confirmar Básico 1 / Padrão 2 / Família 4 e preços.
- [ ] Gateway de pagamento: Stripe (internacional) ou Asaas/Pagar.me (Pix e boleto nativos)?
- [ ] Nome: manter "bullethub.app" mesmo sem Rails no núcleo?

### Riscos técnicos

| Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- |
| Player.js não expõe algum controle exigido pela UI (faixa de áudio, legenda) | Média | Médio | `PlayerEngine` como interface permite trocar para hls.js + Enterprise DRM; validar lista de métodos em Fase 0 |
| Rede Volume sem PoP no Brasil eleva TTFF | Média | Alto (custo 9×) | Gate 1 mede antes de decidir; fallback é Standard |
| Presence admite excesso de streams durante partição de rede | Baixa | Baixo | Aceito; `SessionReaper` corrige em ≤ 45 s |
| Watermark removida por usuário técnico | Alta | Baixo | Tamper detection + código de sessão continua no backend; ataque é rastreável |
| Webhook do Bunny atrasado ou perdido | Média | Médio | Job Oban `AssetStatusPoller` a cada 10 min para assets em `processing` há mais de 30 min |
| Custo de storage cresce com resoluções e MP4 fallback | Alta | Médio | Desativar MP4 fallback e "keep original" na biblioteca; limitar a 4 resoluções |
| Vazamento da API key do Bunny | Baixa | Alto | Só em `runtime.exs` via env; rotação trimestral com janela de duas chaves |
| Time sem experiência em LiveView atrasa o painel | Média | Médio | Painel admin é CRUD simples; alternativa é Backpex ou tabelas LiveView geradas por `mix phx.gen.live` |

### Fontes consultadas em 28/09/2026

- [Bunny Stream Pricing](https://bunny.net/docs/stream/pricing)
- [TUS Resumable Uploads](https://docs.bunny.net/stream/tus-resumable-uploads)
- [Embed view token authentication](https://docs.bunny.net/stream/token-authentication)
- [Understanding Bunny Stream security options](https://docs.bunny.net/stream/security-options)
- [Playback API (Player.js)](https://docs.bunny.net/stream/playback-api)
