defmodule Bullet.Catalog.Genres do
  @moduledoc """
  Fixed genre list (slug → label). Kept in code, not a table: it changes
  rarely and every change is a product decision worth a commit.
  """

  @genres [
    {"acao", "Ação"},
    {"aventura", "Aventura"},
    {"comedia", "Comédia"},
    {"drama", "Drama"},
    {"fantasia", "Fantasia"},
    {"ficcao-cientifica", "Ficção científica"},
    {"suspense", "Suspense"},
    {"terror", "Terror"},
    {"misterio", "Mistério"},
    {"crime", "Crime"},
    {"romance", "Romance"},
    {"animacao", "Animação"},
    {"familia", "Família"},
    {"documentario", "Documentário"},
    {"historia", "História"},
    {"guerra", "Guerra"},
    {"esporte", "Esporte"},
    {"musical", "Musical"},
    {"shounen", "Shounen"},
    {"seinen", "Seinen"},
    {"shoujo", "Shoujo"},
    {"isekai", "Isekai"},
    {"mecha", "Mecha"},
    {"slice-of-life", "Slice of life"}
  ]

  @labels Map.new(@genres)

  def all, do: @genres
  def slugs, do: Enum.map(@genres, &elem(&1, 0))
  def label(slug), do: Map.get(@labels, slug)
  def valid?(slug), do: Map.has_key?(@labels, slug)
end
