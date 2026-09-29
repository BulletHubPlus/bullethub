defmodule Bullet.Library do
  @moduledoc """
  "Minha lista": titles a subscriber saved to watch later. A title is either a
  collection (series/anime) or a movie. Removing a title from the catalog
  removes it from every list (FK cascade); unpublished titles are hidden.
  """

  import Ecto.Query

  alias Bullet.{Catalog, Repo}
  alias Bullet.Library.ListItem

  @type kind :: :collection | :movie

  @spec add(String.t(), kind(), String.t()) :: :ok | {:error, :not_found}
  def add(user_id, kind, id) do
    with {:ok, field, title_id} <- resolve(kind, id) do
      Repo.insert!(%ListItem{user_id: user_id} |> Map.put(field, title_id),
        on_conflict: :nothing,
        conflict_target: {:unsafe_fragment, "(user_id, #{field}) WHERE #{field} IS NOT NULL"}
      )

      :ok
    end
  end

  def remove(user_id, kind, id) do
    with {:ok, field, title_id} <- field_for(kind, id) do
      Repo.delete_all(
        from i in ListItem, where: i.user_id == ^user_id and field(i, ^field) == ^title_id
      )

      :ok
    end
  end

  @doc "Saved titles that are still playable, most recently added first."
  def list(user_id) do
    ids =
      Repo.all(
        from i in ListItem,
          where: i.user_id == ^user_id,
          order_by: [desc: i.inserted_at],
          select: coalesce(i.collection_id, i.media_id)
      )

    by_id = Map.new(Catalog.playable_titles(), &{&1.id, &1})
    ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end

  def member?(user_id, kind, id) do
    case field_for(kind, id) do
      {:ok, field, title_id} ->
        Repo.exists?(
          from i in ListItem, where: i.user_id == ^user_id and field(i, ^field) == ^title_id
        )

      _ ->
        false
    end
  end

  # Only playable titles can be added.
  defp resolve(:collection, slug_or_id) do
    case Enum.find(
           Catalog.playable_titles(),
           &(match?(%Catalog.Collection{}, &1) and &1.id == slug_or_id)
         ) do
      nil -> {:error, :not_found}
      c -> {:ok, :collection_id, c.id}
    end
  end

  defp resolve(:movie, id) do
    case Catalog.get_published_movie(id) do
      nil -> {:error, :not_found}
      m -> {:ok, :media_id, m.id}
    end
  end

  defp field_for(kind, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, if(kind == :collection, do: :collection_id, else: :media_id), uuid}
      :error -> {:error, :not_found}
    end
  end
end
