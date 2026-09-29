defmodule BulletWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  test "renders 404 in the standard envelope" do
    assert BulletWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Not Found", details: %{}}}
  end

  test "renders 500" do
    assert %{error: %{code: "http_500"}} = BulletWeb.ErrorJSON.render("500.json", %{})
  end
end
