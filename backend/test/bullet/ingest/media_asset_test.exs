defmodule Bullet.Ingest.MediaAssetTest do
  use ExUnit.Case, async: true

  alias Bullet.Ingest.MediaAsset

  test "only the PRD §9 transitions are allowed" do
    allowed =
      for from <- MediaAsset.statuses(),
          to <- MediaAsset.statuses(),
          MediaAsset.allowed?(from, to),
          do: {from, to}

    assert Enum.sort(allowed) ==
             Enum.sort([
               {:uploading, :processing},
               {:processing, :ready},
               {:processing, :failed},
               {:failed, :uploading}
             ])
  end

  test "path/2 walks late signals through valid steps" do
    assert MediaAsset.path(:uploading, :ready) == {:ok, [:processing, :ready]}
    assert MediaAsset.path(:uploading, :failed) == {:ok, [:processing, :failed]}
    assert MediaAsset.path(:ready, :ready) == {:ok, []}
    assert MediaAsset.path(:ready, :processing) == :error
    assert MediaAsset.path(:failed, :ready) == :error
  end

  test "changeset rejects an invalid transition" do
    cs = MediaAsset.transition_changeset(%MediaAsset{status: :ready}, :uploading)
    refute cs.valid?
    assert {"invalid_transition", _} = cs.errors[:status]
  end
end
