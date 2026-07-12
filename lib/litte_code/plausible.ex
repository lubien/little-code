defmodule LitteCode.Plausible do
  @moduledoc """
  Server-side Plausible analytics client.

  Used to report events that happen without a browser page load — most
  importantly, redirects served by `LinkController` (a QR scanner or
  `curl` never fetches HTML, so the JS tracker never runs). Firing an
  event here means those visits still show up in the dashboard.

  Events are POSTed asynchronously (`Task.Supervisor.start_child/2`)
  so the redirect itself is never blocked or delayed by upstream
  latency or a temporary outage. Failures are logged and swallowed —
  analytics must never break the site.
  """

  require Logger

  alias LitteCode.Plausible.TaskSupervisor

  @doc """
  Start_link/1 shim so this module can be listed directly in the
  application supervision tree — it starts the underlying task
  supervisor that owns the fire-and-forget event tasks.
  """
  def child_spec(_opts) do
    Supervisor.child_spec({Task.Supervisor, name: TaskSupervisor}, id: __MODULE__)
  end

  @doc """
  Fires an event asynchronously. Returns `:ok` immediately.

  ## Options
    * `:name` — event name (default `"pageview"`).
    * `:url` — full URL of the event target. Required.
    * `:referrer` — string forwarded to Plausible (from the request `Referer`).
    * `:remote_ip` — inet address tuple; forwarded as `X-Forwarded-For` so
      Plausible can attribute the event to the visitor's country/browser.
    * `:user_agent` — string forwarded verbatim.
    * `:props` — map of custom event properties.
  """
  @spec track(keyword()) :: :ok
  def track(opts) do
    if enabled?() do
      Task.Supervisor.start_child(TaskSupervisor, fn -> send_event(opts) end)
    end

    :ok
  end

  @doc "Synchronous version of `track/1` — used directly by tests."
  @spec send_event(keyword()) :: :ok | {:error, term()}
  def send_event(opts) do
    payload =
      %{
        "name" => Keyword.get(opts, :name, "pageview"),
        "url" => Keyword.fetch!(opts, :url),
        "domain" => domain(),
        "referrer" => Keyword.get(opts, :referrer),
        "props" => Keyword.get(opts, :props)
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    headers = build_headers(opts)

    req_opts =
      Keyword.merge(
        [json: payload, headers: headers, receive_timeout: 3_000],
        config()[:req_options] || []
      )

    case Req.post(events_url(), req_opts) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Plausible tracking non-2xx: #{status} #{inspect(body)}")

      {:error, reason} ->
        Logger.warning("Plausible tracking failed: #{inspect(reason)}")
    end
  end

  defp build_headers(opts) do
    ua = Keyword.get(opts, :user_agent) || "little-co.de/1.0 (+link redirect)"

    xff =
      case Keyword.get(opts, :remote_ip) do
        nil -> []
        ip -> [{"x-forwarded-for", :inet.ntoa(ip) |> to_string()}]
      end

    [{"user-agent", ua} | xff]
  end

  # -- config ---------------------------------------------------------

  defp enabled? do
    is_binary(events_url()) and is_binary(domain())
  end

  @doc """
  Full URL for backend event POSTs. Explicit `:events_url` wins;
  otherwise we derive `<upstream>/api/event` from `:upstream`.
  Returns `nil` when neither is configured.
  """
  def events_url do
    cfg = config()

    case cfg[:events_url] do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        case cfg[:upstream] do
          up when is_binary(up) and up != "" -> String.trim_trailing(up, "/") <> "/api/event"
          _ -> nil
        end
    end
  end

  @doc "Configured Plausible upstream base URL, or `nil`."
  def upstream, do: config()[:upstream]

  @doc "Configured browser script src, or `nil` when the snippet is disabled."
  def script_src, do: config()[:script_src]

  defp domain, do: config()[:domain]

  defp config do
    Application.get_env(:litte_code, __MODULE__, [])
  end
end
