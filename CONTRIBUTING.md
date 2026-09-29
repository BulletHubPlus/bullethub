# Contribuindo com o bullethub

## Fluxo

1. Branch a partir de `main`.
2. Implemente com testes. Toda mudança de comportamento tem teste (ExUnit e/ou
   Playwright).
3. Rode o gate de qualidade completo (abaixo) e conserte tudo.
4. Abra o PR. O CI (`.github/workflows/ci.yml`) roda backend, frontend, E2E nos
   três navegadores, Semgrep e Trivy na imagem.
5. Deploy é por tag semver (`v*.*.*`) com aprovação manual no environment
   `production` (dispara o webhook do Coolify).

## Gate de qualidade

```bash
cd backend
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix sobelow --config --exit
mix deps.audit && mix hex.audit
mix dialyzer           # 0 erros
mix test

cd ../frontend
npm run typecheck
npm test
npm run build
npm audit --audit-level=high

cd ../e2e
npx playwright test    # Chromium, Firefox, WebKit
```

Nenhum merge com warning, achado do Sobelow, erro do Dialyzer ou teste vermelho.

## Estilo

- Código e comentários em inglês; UI e mensagens ao usuário em pt-BR (Gettext).
- Elixir formatado por `mix format`; segue as regras do Credo `--strict`.
- Frontend: TypeScript estrito, sem `any` solto; ícones são SVG próprios (sem
  libs de ícone).
- Commits pequenos, logicos e descritivos, agrupados por area. Migrations reversiveis (`up`/`down`).
- Sem `Co-Authored-By` ou atribuicao a IA nas mensagens. Sem em/en dash e sem emoji.

## Segurança

Mudanças em auth, tokens, webhooks, rate limit ou LGPD exigem:
- teste cobrindo o caminho de abuso (não só o caminho feliz);
- rodar `.pentest/scripts/09_full_audit.sh` contra um alvo local;
- atualizar o RIPD (`docs/lgpd/RIPD.md`) se mudar tratamento de dado pessoal.

Nunca commite segredos. `.env*` são git-ignored; produção lê tudo de env no
`runtime.exs`.
