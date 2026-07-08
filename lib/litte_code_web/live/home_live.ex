defmodule LitteCodeWeb.HomeLive do
  use LitteCodeWeb, :live_view

  alias LitteCode.{Captcha, Links, QRCode}
  alias LitteCodeWeb.RateLimit

  @default_qr_text "https://little-co.de"

  @impl true
  def mount(_params, _session, socket) do
    qr_form = to_form(%{"text" => @default_qr_text}, as: :qr)
    shorten_form = to_form(Links.change_link(), as: :link)

    peer_ip =
      if connected?(socket) do
        case get_connect_info(socket, :peer_data) do
          %{address: ip} -> ip
          _ -> {0, 0, 0, 0}
        end
      else
        {0, 0, 0, 0}
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("little-co.de — tiny links & QR codes"))
     |> assign(
       :page_description,
       gettext("Shorten URLs and generate QR codes in a click. Free, no sign-up.")
     )
     |> assign(:current_path, "/")
     |> assign(:tab, :qr)
     |> assign(:qr_text, @default_qr_text)
     |> assign(:qr_svg, QRCode.to_svg(@default_qr_text))
     |> assign(:qr_form, qr_form)
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

    current_path =
      case tab do
        :shorten -> "/?tab=shorten"
        :qr -> "/"
      end

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:current_path, current_path)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?tab=#{tab}")}
  end

  def handle_event("qr_update", %{"qr" => %{"text" => text}}, socket) do
    {:noreply,
     socket
     |> assign(:qr_text, text)
     |> assign(:qr_svg, QRCode.to_svg(text))
     |> assign(:qr_form, to_form(%{"text" => text}, as: :qr))}
  end

  def handle_event("shorten_validate", %{"link" => params}, socket) do
    form =
      %LitteCode.Links.Link{}
      |> Links.change_link(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :link)

    {:noreply, assign(socket, :shorten_form, form)}
  end

  def handle_event("shorten_submit", params, socket) do
    link_params = Map.get(params, "link", %{})
    honeypot = Map.get(params, "website", "")
    captcha_token = Map.get(params, "captcha_token", "")
    captcha_answer = Map.get(params, "captcha_answer", "")

    with :ok <- check_rate_limit(socket),
         :ok <- check_honeypot(honeypot),
         :ok <- Captcha.verify(captcha_token, captcha_answer),
         {:ok, link} <- Links.create_link(link_params) do
      {:noreply,
       socket
       |> assign(:shortened, link)
       |> assign(:shorten_form, to_form(Links.change_link(), as: :link))
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
          <div class="card-body">
            <.form for={@qr_form} id="qr-form" phx-change="qr_update" autocomplete="off">
              <.input
                field={@qr_form[:text]}
                type="text"
                label={gettext("Any text or URL")}
                placeholder="https://example.com"
                phx-debounce="150"
              />
            </.form>

            <div class="mt-4 flex justify-center">
              <div
                :if={@qr_svg}
                id="qr-preview"
                class="p-6 bg-white rounded-box shadow-inner border border-base-200 w-64 h-64 flex items-center justify-center transition-all"
              >
                {Phoenix.HTML.raw(@qr_svg)}
              </div>
              <div
                :if={is_nil(@qr_svg)}
                class="p-6 bg-base-200 rounded-box w-64 h-64 flex items-center justify-center text-sm text-base-content/60"
              >
                {gettext("Type something to generate a QR code.")}
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
              />

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
                    href={short_url(@shortened.hash)}
                    class="font-mono text-base-content underline break-all"
                    target="_blank"
                    rel="noopener"
                  >
                    {display_short_url(@shortened.hash)}
                  </a>
                  <button
                    type="button"
                    id="copy-shortened"
                    phx-hook=".CopyToClipboard"
                    data-copy={short_url(@shortened.hash)}
                    data-copied-label={gettext("Copied!")}
                    class="btn btn-ghost btn-sm gap-1"
                    aria-label={gettext("Copy short link")}
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

  defp short_url(hash) do
    LitteCodeWeb.Endpoint.url() <> "/l/" <> hash
  end

  # Display URL as "little-co.de/l/HASH" instead of the full https://... prefix
  # for a cleaner look, regardless of the configured URL scheme.
  defp display_short_url(hash) do
    uri = URI.parse(LitteCodeWeb.Endpoint.url())
    host = uri.host || "little-co.de"
    "#{host}/l/#{hash}"
  end
end
