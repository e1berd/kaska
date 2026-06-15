defmodule KaskaWeb.Api.ApiDocsTest do
  use KaskaWeb.ConnCase, async: true

  test "the OpenAPI spec is structurally sound and JSON-encodable" do
    map = KaskaWeb.ApiSpec.spec() |> OpenApiSpex.OpenApi.to_map()

    assert map["openapi"] =~ "3."
    assert Map.has_key?(map["paths"], "/p/{project_slug}/tasks/{id}")
    assert is_binary(Jason.encode!(map))
  end

  test "serves the spec as JSON", %{conn: conn} do
    body = conn |> get(~p"/api/openapi") |> json_response(200)

    assert body["openapi"]
    assert body["info"]["title"] == "Kaska Agent API"
    assert get_in(body, ["paths", "/p/{project_slug}/tasks", "get", "operationId"]) == "listTasks"
    assert body["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end

  test "serves Swagger UI as HTML", %{conn: conn} do
    html =
      conn
      |> put_req_header("accept", "text/html")
      |> get(~p"/api/docs")
      |> html_response(200)

    assert html =~ "swagger"
  end
end
