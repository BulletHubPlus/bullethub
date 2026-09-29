defmodule Bullet.RateLimit do
  @moduledoc """
  In-node ETS rate limiter. With a single Phoenix node (PRD §13) this is exact;
  on 2+ nodes each node counts separately, so effective limits multiply by N.
  """
  use Hammer, backend: :ets
end
