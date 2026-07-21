defmodule LitteCodeWeb.HomeLive do
  use LitteCodeWeb, :live_view

  alias LitteCode.{Captcha, Links, QRCode}
  alias LitteCodeWeb.{AdminAuth, ClientIp, RateLimit}

  @default_qr_text "https://little-co.de"

  @impl true
  def mount(_params, _session, socket) do
    shorten_form = to_form(Links.change_link(%LitteCode.Links.Link{}, %{}), as: :link)

    # `ClientIp.for_socket/1` reads Fly.io's `Fly-Client-IP` /
    # `X-Forwarded-For` off the WebSocket upgrade request so the shorten
    # rate limit throttles the real client, not Fly's proxy pool.
    peer_ip = ClientIp.for_socket(socket)

    {:ok,
     socket
     |> assign(:page_title, gettext("little-co.de — tiny links & QR codes"))
     |> assign(
       :page_description,
       gettext("Shorten URLs and generate QR codes in a click. Free, no sign-up.")
     )
     |> assign(:current_path, "/")
     |> assign(:tab, :qr)
     |> assign(:admin?, false)
     |> assign(:admin_key, nil)
     |> assign(:qr_text, @default_qr_text)
     |> assign(:qr_svg, QRCode.to_svg(@default_qr_text))
     |> assign(:shorten_form, shorten_form)
     |> assign(:shortened, nil)
     |> assign(:peer_ip, peer_ip)
     |> assign_new_captcha()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "shorten" -> :shorten
        _ -> :qr
      end

    admin? = AdminAuth.matches?(params["admin"])
    admin_key = if admin?, do: params["admin"], else: nil

    current_path = build_current_path(tab, admin_key)

    # If the admin flips on/off, rebuild the form so the slug field is
    # exposed (or scrubbed) via the right changeset.
    shorten_form =
      %LitteCode.Links.Link{}
      |> Links.change_link(%{}, admin?: admin?)
      |> to_form(as: :link)

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:current_path, current_path)
     |> assign(:admin?, admin?)
     |> assign(:admin_key, admin_key)
     |> assign(:shorten_form, shorten_form)}
  end

  defp build_current_path(tab, admin_key) do
    query =
      %{}
      |> maybe_put(:tab, if(tab == :shorten, do: "shorten"))
      |> maybe_put(:admin, admin_key)

    case URI.encode_query(query) do
      "" -> "/"
      qs -> "/?" <> qs
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    to = build_current_path(String.to_atom(tab), socket.assigns.admin_key)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("shorten_validate", %{"link" => params}, socket) do
    form =
      %LitteCode.Links.Link{}
      |> Links.change_link(params, admin?: socket.assigns.admin?)
      |> Map.put(:action, :validate)
      |> to_form(as: :link)

    {:noreply, assign(socket, :shorten_form, form)}
  end

  def handle_event("shorten_submit", params, socket) do
    link_params = Map.get(params, "link", %{})
    honeypot = Map.get(params, "website", "")
    captcha_token = Map.get(params, "captcha_token", "")
    captcha_answer = Map.get(params, "captcha_answer", "")

    admin? = socket.assigns.admin?

    # Silently strip slug for non-admins so a browser DevTools user can't
    # sneak one in by editing the form manually.
    link_params = if admin?, do: link_params, else: Map.delete(link_params, "slug")

    with :ok <- check_rate_limit(socket),
         :ok <- check_honeypot(honeypot),
         :ok <- Captcha.verify(captcha_token, captcha_answer),
         {:ok, link} <- Links.create_link(link_params, admin?: admin?) do
      {:noreply,
       socket
       |> assign(:shortened, link)
       |> assign(
         :shorten_form,
         Links.change_link(%LitteCode.Links.Link{}, %{}, admin?: admin?)
         |> to_form(as: :link)
       )
       |> assign_new_captcha()
       |> put_flash(:info, gettext("Shortened! Copy your link below."))}
    else
      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign_new_captcha()
         |> put_flash(:error, gettext("You're going a bit fast. Try again in a minute."))}

      {:error, :honeypot} ->
        # Bots don't need a real error — silently drop.
        {:noreply, assign_new_captcha(socket)}

      {:error, :incorrect} ->
        {:noreply,
         socket
         |> assign_new_captcha()
         |> put_flash(:error, gettext("Captcha answer was incorrect. Please try again."))}

      {:error, :missing} ->
        {:noreply,
         socket
         |> assign_new_captcha()
         |> put_flash(:error, gettext("Please solve the captcha to continue."))}

      {:error, :expired} ->
        {:noreply,
         socket
         |> assign_new_captcha()
         |> put_flash(:error, gettext("Captcha expired. Please solve the new one."))}

      {:error, :hash_exhausted} ->
        {:noreply,
         socket
         |> assign_new_captcha()
         |> put_flash(:error, gettext("We couldn't generate a unique hash. Please retry."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:shorten_form, to_form(changeset, as: :link))
         |> assign_new_captcha()}
    end
  end

  def handle_event("new_captcha", _params, socket) do
    {:noreply, assign_new_captcha(socket)}
  end

  defp check_rate_limit(socket) do
    RateLimit.check({:shorten_ws, socket.assigns.peer_ip},
      period: 60_000,
      limit: 10
    )
  end

  defp check_honeypot(""), do: :ok
  defp check_honeypot(nil), do: :ok
  defp check_honeypot(_), do: {:error, :honeypot}

  defp assign_new_captcha(socket), do: assign(socket, :captcha, Captcha.new())

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} current_path={@current_path}>
      <div class="max-w-2xl mx-auto w-full">
        <div class="text-center mb-10">
          <h1 class="text-4xl sm:text-5xl font-bold tracking-tight bg-clip-text text-transparent bg-gradient-to-r from-primary to-accent">
            little-co.de
          </h1>
          <p class="mt-3 text-base-content/70">
            {gettext("Tiny links and pretty QR codes. Nothing else.")}
          </p>
          <p class="mt-2 text-sm text-base-content/50 italic max-w-md mx-auto">
            {gettext("I got pissed at QR Code sites so I built my own with no ads and no charges")}
          </p>
        </div>

        <div
          role="tablist"
          class="tabs tabs-boxed bg-base-200 justify-center mb-8"
          aria-label={gettext("Tools")}
        >
          <button
            id="tab-qr"
            role="tab"
            aria-selected={@tab == :qr}
            phx-click="switch_tab"
            phx-value-tab="qr"
            class={["tab gap-2", @tab == :qr && "tab-active"]}
          >
            <.icon name="hero-qr-code" class="size-4" /> {gettext("QR Code")}
          </button>
          <button
            id="tab-shorten"
            role="tab"
            aria-selected={@tab == :shorten}
            phx-click="switch_tab"
            phx-value-tab="shorten"
            class={["tab gap-2", @tab == :shorten && "tab-active"]}
          >
            <.icon name="hero-link" class="size-4" /> {gettext("Shorten URL")}
          </button>
        </div>

        <div
          :if={@tab == :qr}
          id="qr-panel"
          role="tabpanel"
          aria-labelledby="tab-qr"
          class="card bg-base-100 border border-base-200 shadow-sm"
        >
          <div
            class="card-body"
            id="qr-code-generator"
            phx-hook="QRPreview"
            data-qr-input="qr-text-input"
          >
            <div class="fieldset mb-2">
              <label for="qr-text-input" class="label mb-1">
                {gettext("Any text or URL")}
              </label>
              <%!--
                Plain <input> (no LiveView form) so:
                  * Enter doesn't try to submit anywhere.
                  * `autocorrect` / `autocapitalize` / `spellcheck` reliably
                    pass through and iOS Safari stops fighting the input.
                LiveView is told not to touch this element via `phx-update`
                so the value the user typed is never clobbered by a re-render.
              --%>
              <input
                type="text"
                id="qr-text-input"
                name="qr_text"
                value={@qr_text}
                placeholder="https://example.com"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                data-1p-ignore="true"
                data-lpignore="true"
                data-bwignore="true"
                data-form-type="other"
                class="w-full input"
                phx-update="ignore"
              />
            </div>

            <%!--
              Customize block. Marked `phx-update="ignore"` so LiveView
              doesn't reset the color / file inputs the user just chose
              on unrelated re-renders. Everything here is wired up by
              the `QRPreview` JS hook.
            --%>
            <details
              id="qr-customize"
              class="mt-1 rounded-box border border-base-200 bg-base-200/40 group"
              phx-update="ignore"
            >
              <summary class="cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden px-4 py-2 flex items-center justify-between text-sm font-medium">
                <span class="inline-flex items-center gap-2">
                  <.icon name="hero-swatch" class="size-4 opacity-70" />
                  {gettext("Customize")}
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="size-4 opacity-60 transition-transform group-open:rotate-180"
                />
              </summary>

              <div class="px-4 pb-4 pt-1 space-y-4">
                <%!-- Presets --%>
                <div>
                  <span class="text-xs font-medium block mb-2">{gettext("Presets")}</span>
                  <div class="flex flex-wrap gap-2">
                    <%= for preset <- qr_presets() do %>
                      <button
                        type="button"
                        data-qr-preset={preset.key}
                        aria-pressed="false"
                        title={preset.label}
                        class="group inline-flex flex-col items-center gap-1 text-xs rounded-lg p-1 hover:bg-base-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary transition-colors"
                      >
                        <span
                          class="block size-8 rounded-md border overflow-hidden shadow-sm"
                          style={preset_swatch_style(preset)}
                          aria-hidden="true"
                        >
                          <span
                            class="block size-2/3 mt-1 mx-auto"
                            style={"background-color: #{preset.fg};"}
                          />
                        </span>
                        <span class="text-base-content/80 group-hover:text-base-content">
                          {preset.label}
                        </span>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Colors --%>
                <div class="grid grid-cols-2 gap-3">
                  <label class="text-xs font-medium">
                    <span class="label">{gettext("Foreground")}</span>
                    <input
                      type="color"
                      data-qr-fg
                      value="#0f172a"
                      class="w-full h-10 rounded-md border border-base-300 bg-base-100 cursor-pointer"
                      aria-label={gettext("Foreground color")}
                    />
                  </label>
                  <label class="text-xs font-medium">
                    <span class="label">{gettext("Background")}</span>
                    <input
                      type="color"
                      data-qr-bg
                      value="#ffffff"
                      class="w-full h-10 rounded-md border border-base-300 bg-base-100 cursor-pointer"
                      aria-label={gettext("Background color")}
                    />
                  </label>
                </div>

                <%!-- Border color + width --%>
                <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-3 items-end">
                  <label class="text-xs font-medium">
                    <span class="label">{gettext("Border")}</span>
                    <input
                      type="color"
                      data-qr-border-color
                      value="#0f172a"
                      class="w-full h-10 rounded-md border border-base-300 bg-base-100 cursor-pointer"
                      aria-label={gettext("Border color")}
                    />
                  </label>
                  <label class="text-xs font-medium">
                    <span class="label">{gettext("Border width")}</span>
                    <input
                      type="range"
                      data-qr-border-width
                      min="0"
                      max="40"
                      step="1"
                      value="0"
                      class="range range-primary range-sm w-full"
                      aria-label={gettext("Border width (0 = no border)")}
                    />
                  </label>
                </div>

                <%!-- Radius --%>
                <label class="text-xs font-medium block">
                  <span class="label">{gettext("Corner radius")}</span>
                  <input
                    type="range"
                    data-qr-radius
                    min="0"
                    max="50"
                    step="1"
                    value="0"
                    class="range range-primary range-sm w-full"
                    aria-label={gettext("Corner radius")}
                  />
                </label>

                <div>
                  <label class="text-xs font-medium block mb-1">
                    {gettext("Center logo (optional)")}
                  </label>
                  <div class="flex items-center gap-2">
                    <input
                      type="file"
                      accept="image/*"
                      data-qr-logo
                      class="file-input file-input-sm w-full"
                      aria-label={gettext("Upload a logo to place in the center of the QR code")}
                    />
                    <button
                      type="button"
                      data-qr-logo-remove
                      hidden
                      class="btn btn-ghost btn-sm gap-1"
                      aria-label={gettext("Remove logo")}
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                  <p class="text-xs text-base-content/60 mt-1">
                    {gettext(
                      "Never leaves your browser. PNG, JPG or SVG. Error correction is bumped to level H automatically."
                    )}
                  </p>

                  <div class="mt-3 space-y-2">
                    <label class="text-xs font-medium block">
                      <span class="label">{gettext("Logo size")}</span>
                      <%!-- Capped at 30% to stay within QR error-correction
                            headroom (level H recovers ~30%). Anything larger
                            starts occluding timing/alignment patterns and
                            the code stops scanning reliably. --%>
                      <input
                        type="range"
                        data-qr-logo-size
                        min="10"
                        max="30"
                        step="1"
                        value="22"
                        class="range range-primary range-sm w-full"
                        aria-label={gettext("Logo size (percent of the QR width)")}
                      />
                    </label>

                    <label class="inline-flex items-center gap-2 text-xs cursor-pointer">
                      <input
                        type="checkbox"
                        data-qr-logo-rounded
                        class="checkbox checkbox-xs"
                      />
                      <span>{gettext("Rounded corners")}</span>
                    </label>
                  </div>
                </div>

                <div class="flex justify-end">
                  <button
                    type="button"
                    data-qr-reset
                    class="btn btn-ghost btn-xs gap-1"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-3" />
                    {gettext("Reset")}
                  </button>
                </div>
              </div>
            </details>

            <div class="mt-4 flex flex-col items-center gap-4">
              <%!--
                `phx-update="ignore"` on the wrapper keeps LiveView from clobbering
                the QR SVG that our JS hook writes in on every keystroke.
              --%>
              <div
                id="qr-preview-wrapper"
                class="p-6 bg-white rounded-box shadow-inner border border-base-200 w-64 h-64 flex items-center justify-center transition-all"
                phx-update="ignore"
              >
                <div
                  data-qr-preview
                  aria-label={gettext("QR Code")}
                  class="w-full h-full"
                >
                  {Phoenix.HTML.raw(@qr_svg)}
                </div>
                <div
                  data-qr-empty
                  hidden
                  class="text-sm text-base-content/60 text-center"
                >
                  {gettext("Type something to generate a QR code.")}
                </div>
              </div>

              <div
                class="flex flex-wrap items-center justify-center gap-2"
                phx-update="ignore"
                id="qr-actions"
              >
                <button
                  type="button"
                  data-qr-download
                  data-copied-label={gettext("Downloaded!")}
                  class="btn btn-primary btn-sm gap-2 disabled:opacity-50"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" />
                  <span data-label>{gettext("Download PNG")}</span>
                </button>
                <%!-- Hidden for now while we figure out cross-browser clipboard support. --%>
                <button
                  type="button"
                  data-qr-copy
                  data-copied-label={gettext("Copied!")}
                  class="btn btn-ghost btn-sm gap-2 disabled:opacity-50"
                  hidden
                >
                  <.icon name="hero-clipboard-document" class="size-4" />
                  <span data-label>{gettext("Copy image")}</span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@tab == :shorten}
          id="shorten-panel"
          role="tabpanel"
          aria-labelledby="tab-shorten"
          class="card bg-base-100 border border-base-200 shadow-sm"
        >
          <div class="card-body">
            <.form
              for={@shorten_form}
              id="shorten-form"
              phx-change="shorten_validate"
              phx-submit="shorten_submit"
              autocomplete="off"
            >
              <.input
                field={@shorten_form[:url]}
                type="url"
                label={gettext("Long URL")}
                placeholder="https://example.com/some/very/long/path"
                required
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                data-1p-ignore="true"
                data-lpignore="true"
                data-bwignore="true"
                data-form-type="other"
              />

              <%!--
                Custom slug — only rendered when the request carries a
                valid `?admin=` query param. Non-admin visitors never see
                this input; even if they craft a submission the LiveView
                strips `slug` before hitting the context.
              --%>
              <div :if={@admin?} class="mt-2">
                <.input
                  field={@shorten_form[:slug]}
                  type="text"
                  label={gettext("Custom slug (optional)")}
                  placeholder="my-cool-link"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                  data-1p-ignore="true"
                  data-lpignore="true"
                  data-bwignore="true"
                  data-form-type="other"
                />
                <p class="text-xs text-base-content/60 mt-1">
                  {gettext("Lowercase letters, digits, and dashes. 2–50 characters.")}
                </p>
              </div>

              <%!-- Honeypot: real users won't see or fill this. --%>
              <div class="absolute -left-[9999px]" aria-hidden="true">
                <label>
                  Website
                  <input
                    type="text"
                    name="website"
                    tabindex="-1"
                    autocomplete="off"
                  />
                </label>
              </div>

              <div class="mt-2 rounded-box border border-base-200 bg-base-200/40 p-4">
                <div class="flex items-center justify-between mb-2">
                  <label for="captcha-answer" class="text-sm font-medium">
                    {gettext("Captcha: what is")}
                    <span class="font-mono font-semibold ml-1">{@captcha.question}?</span>
                  </label>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs gap-1"
                    phx-click="new_captcha"
                    aria-label={gettext("New captcha")}
                  >
                    <.icon name="hero-arrow-path" class="size-3" /> {gettext("New")}
                  </button>
                </div>
                <input type="hidden" name="captcha_token" value={@captcha.token} />
                <input
                  id="captcha-answer"
                  type="text"
                  name="captcha_answer"
                  inputmode="numeric"
                  pattern="-?\d+"
                  class="input w-full"
                  placeholder={gettext("Your answer")}
                  required
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                  data-1p-ignore="true"
                  data-lpignore="true"
                  data-bwignore="true"
                  data-form-type="other"
                />
              </div>

              <div class="mt-4 flex justify-end">
                <button type="submit" class="btn btn-primary gap-2">
                  <.icon name="hero-scissors" class="size-4" /> {gettext("Shorten")}
                </button>
              </div>
            </.form>

            <div :if={@shortened} id="shorten-result" class="mt-6">
              <div class="rounded-box border border-success/40 bg-success/5 p-4">
                <p class="text-xs uppercase tracking-wide text-success/80 mb-1">
                  {gettext("Your short link")}
                </p>
                <div class="flex items-center gap-2">
                  <a
                    id="shortened-link"
                    href={short_url(@shortened)}
                    class="font-mono text-base-content underline break-all"
                    target="_blank"
                    rel="noopener"
                  >
                    {display_short_url(@shortened)}
                  </a>
                  <%!-- Hidden for now while we figure out cross-browser clipboard support. --%>
                  <button
                    type="button"
                    id="copy-shortened"
                    phx-hook=".CopyToClipboard"
                    data-copy={short_url(@shortened)}
                    data-copied-label={gettext("Copied!")}
                    class="btn btn-ghost btn-sm gap-1"
                    aria-label={gettext("Copy short link")}
                    hidden
                  >
                    <.icon name="hero-clipboard-document" class="size-4" /> {gettext("Copy")}
                  </button>
                </div>
                <p class="text-xs text-base-content/60 mt-2 break-all">
                  {gettext("Redirects to")} <span class="font-mono">{@shortened.url}</span>
                </p>
              </div>
            </div>

            <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
              export default {
                mounted() {
                  this.el.addEventListener("click", async () => {
                    const value = this.el.dataset.copy
                    const copiedLabel = this.el.dataset.copiedLabel || "Copied!"
                    try {
                      await navigator.clipboard.writeText(value)
                      const original = this.el.innerHTML
                      this.el.innerHTML = copiedLabel
                      setTimeout(() => { this.el.innerHTML = original }, 1500)
                    } catch (_) {}
                  })
                }
              }
            </script>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # QR customization presets. The hex values here mirror `PRESETS` in
  # assets/js/hooks/qr_preview.js — kept in both places so the preview
  # swatches match what the browser draws. The labels live on the server
  # so they can be translated.
  defp qr_presets do
    [
      %{key: "classic", label: gettext("Classic"), fg: "#0f172a", bg: "#ffffff", border: nil},
      %{
        key: "business",
        label: gettext("Business"),
        fg: "#0f172a",
        bg: "#ffffff",
        border: "#94a3b8"
      },
      %{key: "bubble", label: gettext("Bubble"), fg: "#1e3a8a", bg: "#dbeafe", border: "#1e3a8a"},
      %{key: "lo-fi", label: gettext("Lo-fi"), fg: "#7c2d12", bg: "#fef3c7", border: nil},
      %{key: "developer", label: gettext("Developer"), fg: "#22c55e", bg: "#0a0a0a", border: nil},
      %{key: "sunset", label: gettext("Sunset"), fg: "#7c2d12", bg: "#fed7aa", border: "#7c2d12"},
      %{key: "neon", label: gettext("Neon"), fg: "#f0abfc", bg: "#0f172a", border: "#22d3ee"},
      %{key: "print", label: gettext("Print"), fg: "#000000", bg: "#ffffff", border: "#000000"}
    ]
  end

  defp preset_swatch_style(preset) do
    border = preset.border || "transparent"
    "background-color: #{preset.bg}; border-color: #{border};"
  end

  defp short_url(%LitteCode.Links.Link{slug: slug, hash: hash}) do
    base = LitteCodeWeb.Endpoint.url()
    if slug, do: base <> "/c/" <> slug, else: base <> "/l/" <> hash
  end

  # Display URL as "little-co.de/l/HASH" (or /c/SLUG) instead of the full
  # https:// prefix for a cleaner look, regardless of the configured scheme.
  defp display_short_url(%LitteCode.Links.Link{slug: slug, hash: hash}) do
    uri = URI.parse(LitteCodeWeb.Endpoint.url())
    host = uri.host || "little-co.de"
    segment = if slug, do: "c/#{slug}", else: "l/#{hash}"
    "#{host}/#{segment}"
  end
end
