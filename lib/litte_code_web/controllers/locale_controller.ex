defmodule LitteCodeWeb.LocaleController do
  use LitteCodeWeb, :controller

  alias LitteCodeWeb.I18n

  @doc """
  Sets the user's locale in the session and redirects back to where they came from.

  We accept the locale as a URL segment (e.g. `PUT /locale/pt_BR`). Anything
  outside our supported list falls back to the default so a malicious user
  can't poison their own session with garbage.
  """
  def update(conn, %{"locale" => locale} = params) do
    normalized =
      if I18n.supported?(locale), do: locale, else: I18n.default_locale()

    return_to =
      safe_return_to(params["return_to"] || get_req_header(conn, "referer") |> List.first())

    conn
    |> put_session(:locale, normalized)
    |> redirect(to: return_to)
  end

  # Only follow same-origin path redirects — prevents open-redirect abuse.
  defp safe_return_to(url) when is_binary(url) and url != "" do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) and path != "" ->
        case URI.parse(url).query do
          nil -> path
          "" -> path
          query -> path <> "?" <> query
        end

      _ ->
        "/"
    end
  end

  defp safe_return_to(_), do: "/"
end
