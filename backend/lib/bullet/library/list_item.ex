defmodule Bullet.Library.ListItem do
  @moduledoc false
  use Bullet.Schema

  schema "list_items" do
    belongs_to :user, Bullet.Accounts.User
    belongs_to :collection, Bullet.Catalog.Collection
    belongs_to :media, Bullet.Catalog.Media

    timestamps(updated_at: false)
  end
end
