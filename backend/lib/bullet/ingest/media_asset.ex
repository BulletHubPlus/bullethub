defmodule Bullet.Ingest.MediaAsset do
  @moduledoc """
  The encoded file behind a `Media`, 1:1 but with its own lifecycle
  (upload → encoding → ready / failed → re-upload).

  Status is a state machine (PRD §9). Any transition not listed in
  `@transitions` is rejected with `invalid_transition`.
  """
  use Bullet.Schema

  @type status :: :uploading | :processing | :ready | :failed
  @type t :: %__MODULE__{}

  @statuses [:uploading, :processing, :ready, :failed]

  @transitions %{
    uploading: [:processing],
    processing: [:ready, :failed],
    failed: [:uploading],
    ready: []
  }

  schema "media_assets" do
    field :bunny_video_id, :string
    field :status, Ecto.Enum, values: @statuses
    field :duration_seconds, :integer
    field :encoded_resolutions, {:array, :string}, default: []
    field :storage_bytes, :integer
    field :error, :string
    field :status_changed_at, :utc_datetime_usec

    belongs_to :media, Bullet.Catalog.Media

    timestamps()
  end

  def statuses, do: @statuses

  @spec allowed?(status(), status()) :: boolean()
  def allowed?(from, to), do: to in Map.fetch!(@transitions, from)

  @doc """
  Shortest valid path from `from` to `to`, or `:error`. Lets a late or skipped
  signal (e.g. "finished" arriving while we still think it's uploading) land
  on the right state through valid transitions only.
  """
  @spec path(status(), status()) :: {:ok, [status()]} | :error
  def path(same, same), do: {:ok, []}
  def path(:uploading, target) when target in [:ready, :failed], do: {:ok, [:processing, target]}

  def path(from, to) do
    if allowed?(from, to), do: {:ok, [to]}, else: :error
  end

  def create_changeset(asset, bunny_video_id) do
    asset
    |> change(
      bunny_video_id: bunny_video_id,
      status: :uploading,
      status_changed_at: DateTime.utc_now()
    )
    |> unique_constraint(:media_id)
    |> unique_constraint(:bunny_video_id)
  end

  @doc "Single transition, validated. `attrs` may carry metadata (duration, error, …)."
  def transition_changeset(%__MODULE__{status: from} = asset, to, attrs \\ %{}) do
    changeset =
      asset
      |> cast(attrs, [
        :bunny_video_id,
        :duration_seconds,
        :encoded_resolutions,
        :storage_bytes,
        :error
      ])
      |> put_change(:status, to)
      |> put_change(:status_changed_at, DateTime.utc_now())
      |> unique_constraint(:bunny_video_id)

    if allowed?(from, to),
      do: changeset,
      else: add_error(changeset, :status, "invalid_transition", from: from, to: to)
  end
end
