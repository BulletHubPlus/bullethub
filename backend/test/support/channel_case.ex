defmodule BulletWeb.ChannelCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import BulletWeb.ChannelCase

      @endpoint BulletWeb.Endpoint
    end
  end

  setup tags do
    Bullet.DataCase.setup_sandbox(tags)
    :ok
  end
end
