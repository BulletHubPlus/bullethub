# Deterministic fixtures for the Playwright suite (e2e/). Run through
# `DB_NAME=bullet_e2e mix bullet.e2e.setup`, never against the dev database.
alias Bullet.{Accounts, Billing, Catalog, Ingest, Repo}
alias Bullet.Accounts.User

password = "senha-bem-longa-123"

account = fn email, name, cpf, role ->
  {:ok, user} = Accounts.register_user(%{email: email, name: name, password: password, cpf: cpf}, & &1)
  user = Repo.update!(User.confirm_changeset(user))
  {:ok, user} = Accounts.set_role(user, role)
  user
end

owner = account.("owner@e2e.test", "Owner E2E", "52998224725", :owner)
_support = account.("support@e2e.test", "Suporte E2E", "11144477735", :support)
basic = account.("basico@e2e.test", "Assinante Básico", "39053344705", :subscriber)
family = account.("familia@e2e.test", "Assinante Família", "12345678909", :subscriber)
_no_plan = account.("semplano@e2e.test", "Sem Plano", "98765432100", :subscriber)
{:ok, _} = Billing.grant(basic, "basico")
{:ok, _} = Billing.grant(family, "familia")
_ = owner

ready = fn media ->
  {:ok, asset, _} = Ingest.start_upload(media)
  {:ok, asset} = Ingest.mark_uploaded(asset)
  {:ok, _} = Ingest.simulate_encoding(asset)
  {:ok, media} = Catalog.publish_media(media)
  media
end

{:ok, series} =
  Catalog.create_collection(%{
    kind: :series,
    title: "Noite Neon",
    original_title: "Neon Night",
    description: "Uma detetive particular atravessa a cidade atrás de um arquivo que ninguém deveria ter visto.",
    release_year: 2025,
    age_rating: "16",
    genres: ["crime", "drama"],
    cast: ["Ana Lima", "Bruno Reis"],
    creators: ["Carla Dias"]
  })

for n <- 1..2 do
  {:ok, season} = Catalog.create_season(series, %{number: n})

  for p <- 1..2 do
    {:ok, ep} = Catalog.create_item(season, %{title: "Capítulo #{p + (n - 1) * 2}", position: p, intro_end_seconds: 10})
    ready.(ep)
  end
end

{:ok, _} = Catalog.set_collection_published(series, true)

{:ok, anime} =
  Catalog.create_collection(%{kind: :anime, title: "Lâmina Carmesim", genres: ["acao", "shounen"], creators: ["Estúdio Aurora"], age_rating: "14"})

{:ok, s1} = Catalog.create_season(anime, %{number: 1})
{:ok, ep} = Catalog.create_item(s1, %{title: "O Juramento", position: 1})
ready.(ep)
{:ok, _} = Catalog.set_collection_published(anime, true)

{:ok, movie} =
  Catalog.create_movie(%{
    title: "Ação no Porto",
    synopsis: "Um thriller curto e seco.",
    release_year: 2024,
    age_rating: "14",
    genres: ["acao", "suspense"],
    cast: ["Joana Prado"],
    creators: ["Diretor Um"]
  })

movie = ready.(movie)
{:ok, _} = Catalog.put_caption(movie, "pt-BR", "1\n00:00:01,000 --> 00:00:04,000\nLegenda de teste\n")

IO.puts("e2e seed ok")
