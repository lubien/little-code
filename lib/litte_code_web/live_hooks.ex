defmodule LitteCodeWeb.LiveHooks do
  @moduledoc """
  `on_mount` hooks used from `live_session` in the router.
  """

  import Phoenix.Component, only: [assign: 3]

  alias LitteCodeWeb.I18n

  @doc """
  Puts the request session's locale on the current LiveView process so
  `gettext/1` calls made during render use the right catalog.

  Also mirrors the locale into `socket.assigns.locale` so templates can
  read it (for the language switcher, `<html lang="...">`, etc.).
  """
  def on_mount(:set_locale, _params, session, socket) do
    locale =
      case session["locale"] do
        code when is_binary(code) ->
          if I18n.supported?(code), do: code, else: I18n.default_locale()

        _ ->
          I18n.default_locale()
      end

    Gettext.put_locale(LitteCodeWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end
end
