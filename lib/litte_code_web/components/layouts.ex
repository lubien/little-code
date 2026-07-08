defmodule LitteCodeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LitteCodeWeb, :html

  alias LitteCodeWeb.I18n

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Converts an application locale code (e.g. `"pt_BR"`) into a BCP-47
  language tag suitable for the `<html lang>` attribute (`"pt-BR"`).
  """
  def html_lang(nil), do: "en"

  def html_lang(locale) when is_binary(locale) do
    String.replace(locale, "_", "-")
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :locale, :string, default: nil, doc: "current locale code (e.g. \"en\")"
  attr :current_path, :string, default: "/", doc: "current request path, for locale switcher"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign_new(assigns, :locale, fn -> I18n.default_locale() end)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 font-semibold tracking-tight">
            <span class="inline-flex items-center justify-center size-8 rounded-lg bg-primary text-primary-content">
              <.icon name="hero-link" class="size-4" />
            </span>
            <span class="text-base">little-co.de</span>
          </a>
        </div>
        <div class="flex-none flex items-center gap-2">
          <.language_switcher current_locale={@locale} current_path={@current_path} />
          <.theme_toggle />
        </div>
      </header>

      <main class="flex-1 px-4 py-10 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-2xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="border-t border-base-200 py-6 px-4 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-2xl flex flex-col sm:flex-row items-center justify-between gap-2 text-sm text-base-content/60">
          <p class="inline-flex items-center gap-1 flex-wrap justify-center">
            {gettext("Made with")}
            <.icon name="hero-heart-solid" class="size-4 text-error" />
            {gettext("using")}
            <a
              href="https://www.phoenixframework.org/"
              class="link link-hover font-medium text-base-content"
              target="_blank"
              rel="noopener"
            >
              Phoenix Framework
            </a>
            {gettext("by")}
            <a
              href="https://github.com/lubien"
              class="link link-hover font-medium text-base-content"
              target="_blank"
              rel="noopener"
            >
              Lubien
            </a>
          </p>
          <div class="inline-flex items-center gap-2">
            <a
              href="https://github.com/lubien"
              class="link link-hover inline-flex items-center gap-1"
              target="_blank"
              rel="noopener"
              aria-label={gettext("Lubien on GitHub")}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" class="size-4 fill-current">
                <path
                  fill-rule="evenodd"
                  clip-rule="evenodd"
                  d="M12 0C5.37 0 0 5.506 0 12.303c0 5.445 3.435 10.043 8.205 11.674.6.107.825-.262.825-.585 0-.292-.015-1.261-.015-2.291C6 21.67 5.22 20.346 4.98 19.654c-.135-.354-.72-1.446-1.23-1.738-.42-.23-1.02-.8-.015-.815.945-.015 1.62.892 1.845 1.261 1.08 1.86 2.805 1.338 3.495 1.015.105-.8.42-1.338.765-1.645-2.67-.308-5.46-1.37-5.46-6.075 0-1.338.465-2.446 1.23-3.307-.12-.308-.54-1.569.12-3.26 0 0 1.005-.323 3.3 1.26.96-.276 1.98-.415 3-.415s2.04.139 3 .416c2.295-1.6 3.3-1.261 3.3-1.261.66 1.691.24 2.952.12 3.26.765.861 1.23 1.953 1.23 3.307 0 4.721-2.805 5.767-5.475 6.075.435.384.81 1.122.81 2.276 0 1.645-.015 2.968-.015 3.383 0 .323.225.707.825.585a12.047 12.047 0 0 0 5.919-4.489A12.536 12.536 0 0 0 24 12.304C24 5.505 18.63 0 12 0Z"
                />
              </svg>
              @lubien
            </a>
            <span aria-hidden="true" class="opacity-50">·</span>
            <a
              href="https://github.com/lubien/little-code"
              class="link link-hover inline-flex items-center gap-1"
              target="_blank"
              rel="noopener"
              aria-label={gettext("View source on GitHub")}
            >
              <.icon name="hero-code-bracket" class="size-4" /> {gettext("Source")}
            </a>
          </div>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  A tiny two-button locale switcher styled like the theme toggle.

  Each button is a plain `<form method="post">` so switching works without
  JavaScript and always triggers a fresh SSR pass with the new locale.
  """
  attr :current_locale, :string, required: true
  attr :current_path, :string, default: "/"

  def language_switcher(assigns) do
    ~H"""
    <div
      class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full"
      id="language-switcher"
      role="group"
      aria-label={gettext("Language")}
    >
      <%= for {locale, index} <- Enum.with_index(I18n.locales()) do %>
        <form
          method="post"
          action={~p"/locale/#{locale.code}"}
          class="contents"
        >
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="return_to" value={@current_path} />
          <button
            type="submit"
            id={"lang-#{locale.code}"}
            aria-pressed={@current_locale == locale.code}
            title={locale.label}
            class={[
              "px-3 py-1 text-xs font-semibold rounded-full cursor-pointer transition-colors",
              index == 0 && "rounded-r-none",
              index == length(I18n.locales()) - 1 && "rounded-l-none",
              @current_locale == locale.code &&
                "bg-base-100 text-base-content brightness-200",
              @current_locale != locale.code && "text-base-content/60 hover:text-base-content"
            ]}
          >
            {locale.short}
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
