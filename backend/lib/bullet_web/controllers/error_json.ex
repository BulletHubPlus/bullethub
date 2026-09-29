defmodule BulletWeb.ErrorJSON do
  @moduledoc "Renders unhandled errors in the standard envelope (see `BulletWeb.ErrorResponse`)."

  def render(template, _assigns) do
    status = template |> String.split(".") |> hd()
    code = if status == "404", do: "not_found", else: "http_#{status}"
    BulletWeb.ErrorResponse.body(code, Phoenix.Controller.status_message_from_template(template))
  end
end
