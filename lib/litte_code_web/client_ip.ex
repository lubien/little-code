defmodule LitteCodeWeb.ClientIp do
  @moduledoc """
  Resolves the real client IP for a request, whether it arrives over HTTP
  or a LiveView WebSocket.

  On HTTP requests this is redundant — the `RemoteIp` plug in the endpoint
  has already rewritten `conn.remote_ip`. On the LiveView socket we don't
  get a plug pipeline, so this helper reads the same headers Fly injects
  on the WebSocket upgrade request.
  """

  @headers ~w(fly-client-ip x-forwarded-for)

  @doc """
  Returns the client IP for a LiveView socket, falling back to the TCP
  peer address (Fly's proxy) if no forwarded headers are present — e.g.
  in local dev where the socket connects straight to Bandit.

  Returns an `:inet` address tuple (e.g. `{127, 0, 0, 1}`).
  """
  def for_socket(socket) do
    if Phoenix.LiveView.connected?(socket) do
      resolve(socket)
    else
      {0, 0, 0, 0}
    end
  end

  defp resolve(socket) do
    with headers when is_list(headers) <-
           Phoenix.LiveView.get_connect_info(socket, :x_headers),
         ip when not is_nil(ip) <- RemoteIp.from(headers, headers: @headers) do
      ip
    else
      _ -> peer_address(socket)
    end
  end

  defp peer_address(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: ip} -> ip
      _ -> {0, 0, 0, 0}
    end
  end
end
