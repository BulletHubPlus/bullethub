defmodule Bullet.Catalog.Caption do
  @moduledoc false
  use Bullet.Schema

  @type t :: %__MODULE__{}

  @languages [{"pt-BR", "Português"}, {"en", "English"}, {"es", "Español"}, {"ja", "日本語"}]

  schema "media_captions" do
    field :srclang, :string
    field :label, :string
    field :content, :string

    belongs_to :media, Bullet.Catalog.Media

    timestamps()
  end

  def languages, do: @languages

  def changeset(caption, attrs) do
    caption
    |> cast(attrs, [:srclang, :label, :content])
    |> validate_required([:srclang, :label, :content])
    |> validate_inclusion(:srclang, Enum.map(@languages, &elem(&1, 0)))
    |> validate_length(:content, max: 2_000_000)
    |> unique_constraint([:media_id, :srclang])
  end

  @doc """
  Accepts SubRip (.srt) or WebVTT and returns WebVTT. SRT differs in the
  header and the millisecond separator (`00:01:02,500` → `00:01:02.500`).
  """
  @spec to_vtt(binary()) :: {:ok, String.t()} | {:error, :invalid}
  def to_vtt(raw) do
    text =
      raw
      |> String.replace_prefix("﻿", "")
      |> String.replace("\r\n", "\n")
      |> String.trim()

    cond do
      not String.valid?(text) ->
        {:error, :invalid}

      String.starts_with?(text, "WEBVTT") ->
        {:ok, text <> "\n"}

      Regex.match?(~r/\d{2}:\d{2}:\d{2},\d{3}\s+-->/, text) ->
        {:ok,
         "WEBVTT\n\n" <> Regex.replace(~r/(\d{2}:\d{2}:\d{2}),(\d{3})/, text, "\\1.\\2") <> "\n"}

      true ->
        {:error, :invalid}
    end
  end
end
