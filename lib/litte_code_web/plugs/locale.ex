defmodule LitteCodeWeb.Plugs.Locale do
  @moduledoc """
  Detects the request's locale and configures Gettext accordingly.

  Detection order:

    1. `:locale` key in the session (previously set via the language switcher).
    2. `Accept-Language` request header (highest-quality supported match).
    3. The app-wide default (`en`).

  The resolved locale is also:
    * assigned to `conn.assigns.locale` for use in templates
    * written back to the session so subsequent requests skip detection.
  """

  @behaviour Plug

  import Plug.Conn

  alias LitteCodeWeb.I18n

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    locale = detect_locale(conn)
    Gettext.put_locale(LitteCodeWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
  end

  defp detect_locale(conn) do
    with nil <- session_locale(conn),
         nil <- accept_language_locale(conn) do
      I18n.default_locale()
    end
  end

  defp session_locale(conn) do
    case get_session(conn, :locale) do
      code when is_binary(code) ->
        if I18n.supported?(code), do: code

      _ ->
        nil
    end
  end

  defp accept_language_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> I18n.from_accept_language()
  end
end
