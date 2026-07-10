defmodule LitteCodeWeb.DocsLive do
  use LitteCodeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("little-co.de — API docs"))
     |> assign(
       :page_description,
       gettext("REST API reference for shortening links programmatically.")
     )
     |> assign(:current_path, "/docs")
     |> assign(:host, host())}
  end

  defp host do
    uri = URI.parse(LitteCodeWeb.Endpoint.url())
    uri.host || "little-co.de"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} current_path={@current_path}>
      <article class="max-w-2xl mx-auto w-full prose prose-sm sm:prose-base dark:prose-invert">
        <header class="mb-8 text-center not-prose">
          <h1 class="text-3xl sm:text-4xl font-bold tracking-tight bg-clip-text text-transparent bg-gradient-to-r from-primary to-accent">
            {gettext("API Docs")}
          </h1>
          <p class="mt-3 text-base-content/70">
            {gettext("Shorten URLs from your terminal, CI job, or app.")}
          </p>
        </header>

        <section>
          <h2 class="text-xl font-semibold">{gettext("Shorten a URL")}</h2>
          <p class="text-base-content/70">
            {gettext(
              "POST a JSON body containing the URL you want shortened. Returns the short URL and metadata."
            )}
          </p>

          <h3 class="font-semibold text-base mt-4">{gettext("cURL")}</h3>
          <pre
            phx-no-curly-interpolation
            class="rounded-box border border-base-200 bg-base-200/60 p-4 overflow-x-auto"
          ><code>curl -X POST https://{@host}/api/links \
    -H "Content-Type: application/json" \
    -d '&lbrace;"url":"https://example.com/some/very/long/path"&rbrace;'</code></pre>

          <h3 class="font-semibold text-base mt-4">{gettext("HTTP")}</h3>
          <pre
            phx-no-curly-interpolation
            class="rounded-box border border-base-200 bg-base-200/60 p-4 overflow-x-auto"
          ><code>POST /api/links HTTP/1.1
    Host: {@host}
    Content-Type: application/json

    &lbrace;"url":"https://example.com/some/very/long/path"&rbrace;</code></pre>

          <h3 class="font-semibold text-base mt-4">{gettext("Response")}</h3>
          <pre
            phx-no-curly-interpolation
            class="rounded-box border border-base-200 bg-base-200/60 p-4 overflow-x-auto"
          ><code>HTTP/1.1 201 Created
    Location: https://{@host}/l/abc12
    X-RateLimit-Limit: 30
    X-RateLimit-Remaining: 29
    X-RateLimit-Reset: 1783685040
    Content-Type: application/json

    &lbrace;
    "data": &lbrace;
    "hash": "abc12",
    "slug": null,
    "url": "https://example.com/some/very/long/path",
    "short_url": "https://{@host}/l/abc12",
    "views": 0,
    "created_at": "2026-07-10T12:00:00Z"
    &rbrace;
    &rbrace;</code></pre>
        </section>

        <section class="mt-10">
          <h2 class="text-xl font-semibold">{gettext("Following a short link")}</h2>
          <p class="text-base-content/70">
            {gettext(
              "Every shortened URL is served as a 302 redirect to the original target. Auto-generated links live at "
            )}
            <code>/l/&lt;hash&gt;</code>{gettext(" and custom slugs live at ")}
            <code>/c/&lt;slug&gt;</code>{gettext(". Both track a view counter server-side.")}
          </p>

          <pre
            phx-no-curly-interpolation
            class="rounded-box border border-base-200 bg-base-200/60 p-4 overflow-x-auto"
          ><code>curl -I https://{@host}/l/abc12
    # HTTP/1.1 302 Found
    # location: https://example.com/some/very/long/path</code></pre>
        </section>

        <section class="mt-10">
          <h2 class="text-xl font-semibold">{gettext("Rate limits")}</h2>
          <p class="text-base-content/70">
            {gettext(
              "Link creation is capped at 30 requests per minute per IP. Every response includes "
            )}
            <code>X-RateLimit-Limit</code>, <code>X-RateLimit-Remaining</code>,
            <code>X-RateLimit-Reset</code>
            (unix seconds), {gettext("and, on 429s, ")} <code>Retry-After</code>
            {gettext(" so polite clients can back off.")}
          </p>
        </section>

        <section class="mt-10">
          <h2 class="text-xl font-semibold">{gettext("Custom slugs (admin only)")}</h2>
          <p class="text-base-content/70">
            {gettext("This instance can also mint short links with a human-readable slug — e.g. ")}
            <code>/c/summer-sale</code>{gettext(
              " instead of /l/abc12. Because slugs are scarce and abuseable, they are gated behind a server-configured admin secret. The server operator sets an "
            )}
            <code>ADMIN_KEY</code>
            {gettext(" env var; when it's blank the feature is disabled entirely.")}
          </p>
          <p class="text-base-content/70 mt-2">
            {gettext(
              "If you're not the server operator, ask them whether an admin key is available and, if so, they'll share it out-of-band."
            )}
            {gettext("You can also self-host your own instance and set the key yourself — see ")}
            <a
              href="https://github.com/lubien/little-code"
              target="_blank"
              rel="noopener"
              class="link link-hover font-semibold"
            >github.com/lubien/little-code</a>.
          </p>

          <p class="text-base-content/70 mt-4">
            {gettext("Pass the key via the ")}<code>?admin=</code>{gettext(
              " query string. Anything else in the body works exactly as before, except that a "
            )}
            <code>slug</code> {gettext("field is now accepted.")}
          </p>

          <pre
            phx-no-curly-interpolation
            class="rounded-box border border-base-200 bg-base-200/60 p-4 overflow-x-auto"
          ><code>curl -X POST "https://{@host}/api/links?admin=YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '&lbrace;"url":"https://example.com/summer-sale","slug":"summer-sale"&rbrace;'

    # HTTP/1.1 201 Created
    # Location: https://{@host}/c/summer-sale
    # &lbrace;"data":&lbrace;"hash":"...","slug":"summer-sale","short_url":"https://{@host}/c/summer-sale",...&rbrace;&rbrace;</code></pre>

          <p class="text-base-content/70 mt-4 text-sm">
            {gettext(
              "Slugs must be 2–50 lowercase letters, digits, or dashes; can't start or end with a dash; and can't be one of a small reserved list."
            )}
          </p>
        </section>

        <section class="mt-10">
          <h2 class="text-xl font-semibold">{gettext("Errors")}</h2>
          <p class="text-base-content/70">
            {gettext("All errors are JSON. The most common ones:")}
          </p>
          <ul class="mt-2 space-y-1 text-base-content/80">
            <li>
              <code>422 Unprocessable Entity</code>
              — {gettext("validation failed (missing / invalid URL, slug taken, etc.)")}
            </li>
            <li>
              <code>429 Too Many Requests</code>
              — {gettext("rate limit exceeded. Wait for the Retry-After header.")}
            </li>
            <li>
              <code>400 Bad Request</code> — {gettext("malformed JSON body.")}
            </li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end
end
