defmodule LitteCodeWeb.Api.LinkController do
  @moduledoc """
  JSON API for creating shortened links.

  ## `POST /api/links`

  Request body (JSON):

      {"url": "https://example.com/some/long/path"}

  Responses:

    * `201 Created` — the URL was shortened.
    * `422 Unprocessable Entity` — validation failed (invalid or missing URL).
    * `429 Too Many Requests` — rate limit exceeded (30 creates per minute per IP).
    * `400 Bad Request` — malformed JSON.
    * `500 Internal Server Error` — hash collision could not be resolved.

  All responses are JSON. Rate-limit info is exposed via the
  `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`
  headers on every request (courtesy of `LitteCodeWeb.Plugs.Attack`).
  """

  use LitteCodeWeb, :controller

  alias LitteCode.Links
  alias LitteCodeWeb.AdminAuth

  # `POST /api/links`
  def create(conn, params) do
    admin? = AdminAuth.matches?(admin_param(conn, params))

    attrs =
      if admin? do
        %{"url" => Map.get(params, "url"), "slug" => Map.get(params, "slug")}
      else
        # Silently drop any submitted slug for non-admins — same behavior
        # as the LiveView form.
        %{"url" => Map.get(params, "url")}
      end

    case Links.create_link(attrs, admin?: admin?) do
      {:ok, link} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", short_url(link))
        |> render(:show, link: link)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error,
          error: "validation_failed",
          details: translate_errors(changeset)
        )

      {:error, :hash_exhausted} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:error,
          error: "hash_exhausted",
          message: "Could not generate a unique short hash. Please retry."
        )
    end
  end

  defp short_url(%LitteCode.Links.Link{slug: slug, hash: hash}) do
    base = LitteCodeWeb.Endpoint.url()
    if slug, do: base <> "/c/" <> slug, else: base <> "/l/" <> hash
  end

  # Admin key can come from `?admin=` (query string) or the body param
  # of the same name — whichever the client finds convenient.
  defp admin_param(_conn, params) when is_map(params) do
    Map.get(params, "admin")
  end

  defp admin_param(_conn, _params), do: nil

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      # Ecto validation messages go through the errors domain so pt_BR
      # users see localized details, matching what the LiveView shows.
      Gettext.dgettext(LitteCodeWeb.Gettext, "errors", msg, opts)
    end)
  end
end
