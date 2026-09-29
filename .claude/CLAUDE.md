# bullethub - Claude Context

O contexto canônico do monorepo está em [`AGENTS.md`](../AGENTS.md) (stack,
estrutura, contextos, comandos, gate de qualidade, segurança). Este arquivo
adiciona o que é específico de trabalhar aqui com o Claude Code.

## Antes de implementar

- **Leia o arquivo antes de editar.** Nunca assuma o que o código faz - os
  contextos têm invariantes sutis (rotação de refresh token, máquina de estados
  do asset, Presence para limite de telas, assinatura do webhook).
- O guia do framework Phoenix 1.8 (HEEx, LiveView, Ecto) está em
  `backend/AGENTS.md` e vale como regra.

## Ao concluir uma mudança

Rode o gate de qualidade e **conserte tudo antes de dizer que terminou**:

```bash
cd backend && mix precommit && mix security.check && mix dialyzer
cd frontend && npm run typecheck && npm test && npm run build
```

Se a mudança toca fluxo de usuário (auth, playback, catálogo, admin), rode
também o E2E do Chromium: `cd e2e && npx playwright test --project=chromium`.
A suíte de navegador já pegou 4 bugs que os testes unitários não viam
(auth do socket, corrida do refresh, broadcast de canal, limite por IP em CGNAT)
- trate-a como parte do gate, não como opcional.

## Servidores de teste

O usuário roda o próprio `phx.server` (porta 4010; a 4000 costuma estar ocupada
por outro projeto). **Nunca** suba um servidor de teste no banco `bullet_dev`:
o Oban compete pelas filas e "rouba" os e-mails/jobs do usuário. Use sempre um
banco isolado:

```bash
cd backend && DB_NAME=bullet_e2e mix bullet.e2e.setup
DB_NAME=bullet_e2e PORT=4012 mix phx.server
```

E **desligue** o servidor de teste ao terminar. Ícones na UI são componentes
SVG próprios (`frontend/src/components/ui/Icon.vue`) - não adicione lucide nem
outra lib de ícones.

## Convenções de UI

Design system portado do `effront-web`: preto `#060606`, um único acento
vermelho `#f20024` usado só em borda/texto/gradiente (nunca preenchimento sólido
em superfície grande), Bricolage Grotesque (display) + Inter (corpo), raio 6px.
Logo: símbolo (mark) quando logado, wordmark `bullethub.` quando deslogado.

## REGRAS CRITICAS - SEMPRE SEGUIR

1. **NADA DE Co-Authored-By / atribuicao a IA** em commits ou PRs. Nunca
   adicione linhas `Co-Authored-By:` nem "Generated with Claude Code". O
   historico de git e do usuario.
2. **NADA DE em/en dash** (`-` e `-`, U+2014/U+2013) em codigo, comentarios,
   mensagens de commit, docs ou qualquer saida. Use hifen simples `-`.
3. **NADA DE emoji** em codigo, logs, comentarios ou mensagens de commit.
4. **Commits pequenos e logicos**, agrupados por area/feature. Nunca junte o
   projeto inteiro num unico commit. Adicione arquivos por caminho explicito;
   evite `git add -A` sem necessidade.
5. **Peca antes de commitar/pushar.** git commit e push so com autorizacao
   explicita do usuario; mostre `git diff` antes.
