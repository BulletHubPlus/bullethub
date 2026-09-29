defmodule Bullet.Catalog.Metadata do
  @moduledoc """
  Title metadata shared by `Collection` (series/anime) and `Media` (movies):
  original title, year, classificação indicativa, genres, cast, creators
  (direção/estúdio), vertical poster and wide backdrop.
  """
  import Ecto.Changeset

  alias Bullet.Catalog.{Collection, Genres}

  @age_ratings ~w(L 10 12 14 16 18)
  @fields [
    :original_title,
    :release_year,
    :age_rating,
    :genres,
    :cast,
    :creators,
    :poster_url,
    :backdrop_url
  ]

  def age_ratings, do: @age_ratings
  def fields, do: @fields

  defmacro schema_fields do
    quote do
      field :original_title, :string
      field :release_year, :integer
      field :age_rating, :string
      field :genres, {:array, :string}, default: []
      field :cast, {:array, :string}, default: []
      field :creators, {:array, :string}, default: []
      field :poster_url, :string
      field :backdrop_url, :string
    end
  end

  @doc """
  Casts and validates the metadata. `cast`/`creators` accept a list or a
  comma-separated string (what the admin form sends).
  """
  def changeset(changeset, attrs) do
    attrs = attrs |> normalize_list("cast") |> normalize_list("creators") |> normalize_genres()

    changeset
    |> cast(attrs, @fields)
    |> validate_length(:original_title, max: 160)
    |> validate_number(:release_year,
      greater_than_or_equal_to: 1888,
      less_than_or_equal_to: Date.utc_today().year + 2
    )
    |> validate_inclusion(:age_rating, @age_ratings, message: "use L, 10, 12, 14, 16 ou 18")
    |> validate_subset(:genres, Genres.slugs(), message: "gênero inválido")
    |> validate_length(:cast, max: 30)
    |> validate_length(:creators, max: 10)
    |> Collection.validate_url(:poster_url)
    |> Collection.validate_url(:backdrop_url)
  end

  defp normalize_list(attrs, key) do
    case fetch(attrs, key) do
      {k, value} when is_binary(value) ->
        Map.put(
          attrs,
          k,
          value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        )

      _ ->
        attrs
    end
  end

  # Checkbox groups send [""] when nothing is ticked.
  defp normalize_genres(attrs) do
    case fetch(attrs, "genres") do
      {k, list} when is_list(list) -> Map.put(attrs, k, Enum.reject(list, &(&1 in ["", nil])))
      _ -> attrs
    end
  end

  defp fetch(attrs, key) do
    cond do
      Map.has_key?(attrs, key) ->
        {key, attrs[key]}

      Map.has_key?(attrs, String.to_existing_atom(key)) ->
        {String.to_existing_atom(key), attrs[String.to_existing_atom(key)]}

      true ->
        nil
    end
  end

  @doc "Admin form value for list fields."
  def join(list) when is_list(list), do: Enum.join(list, ", ")
  def join(other), do: other
end
