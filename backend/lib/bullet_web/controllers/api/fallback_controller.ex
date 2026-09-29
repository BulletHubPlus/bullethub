defmodule BulletWeb.Api.FallbackController do
  @moduledoc false
  use BulletWeb, :controller

  alias BulletWeb.ErrorResponse

  def not_found(conn, _params),
    do: ErrorResponse.send(conn, 404, "not_found", "Rota não encontrada.")

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    ErrorResponse.send(conn, 422, "validation_failed", "Verifique os campos informados.", %{
      fields: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    })
  end

  def call(conn, {:error, :not_found}),
    do: ErrorResponse.send(conn, 404, "not_found", "Não encontrado.")

  def call(conn, {:error, :invalid_token}),
    do: ErrorResponse.send(conn, 400, "invalid_token", "Link inválido ou expirado.")

  def call(conn, {:error, :already_confirmed}),
    do: ErrorResponse.send(conn, 409, "already_confirmed", "E-mail já confirmado.")

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
