# syntax=docker/dockerfile:1.7
# bullethub.app - single release: Phoenix (API + WebSocket + admin LiveView) serving the Vue SPA.

ARG ELIXIR_IMAGE=elixir:1.18-otp-27-alpine
# Must match the Alpine release of ELIXIR_IMAGE (musl/openssl ABI of ERTS).
ARG RUNTIME_IMAGE=alpine:3.22

# ---------- 1. SPA (Vue 3 + Vite) ----------
FROM node:25-alpine AS web
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
# vite.config.ts writes to ../backend/priv/static/app
RUN npm run build

# Admin (LiveView) JS deps, bundled later by esbuild in the Elixir stage.
WORKDIR /app/backend/assets
COPY backend/assets/package.json backend/assets/package-lock.json ./
RUN npm ci --no-audit --no-fund

# ---------- 2. Elixir release ----------
FROM ${ELIXIR_IMAGE} AS build
RUN apk add --no-cache build-base git
WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY backend/mix.exs backend/mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY backend/config/config.exs backend/config/prod.exs config/
RUN mix deps.compile

COPY backend/priv priv
COPY backend/lib lib
COPY backend/assets assets
COPY --from=web /app/backend/assets/node_modules assets/node_modules
COPY --from=web /app/backend/priv/static/app priv/static/app

RUN mix compile --warnings-as-errors
RUN mix assets.deploy

COPY backend/config/runtime.exs config/
COPY backend/rel rel
RUN mix release

# ---------- 3. Runtime ----------
FROM ${RUNTIME_IMAGE}
RUN apk add --no-cache libstdc++ libgcc ncurses-libs openssl ca-certificates tini \
 && addgroup -S app && adduser -S app -G app

WORKDIR /app
ENV HOME=/app MIX_ENV=prod PORT=4000 LANG=C.UTF-8

COPY --from=build --chown=app:app /app/_build/prod/rel/bullet ./

USER app
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:${PORT}/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
# Migrations run before the new container starts serving; a failed migration
# keeps the old container live in Coolify (healthcheck never passes).
CMD ["sh", "-c", "/app/bin/migrate && exec /app/bin/server"]
