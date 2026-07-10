defmodule LitteCodeWeb.Api.LinkJSON do
  @moduledoc false

  alias LitteCode.Links.Link

  def show(%{link: %Link{} = link}) do
    %{
      data: %{
        hash: link.hash,
        url: link.url,
        short_url: LitteCodeWeb.Endpoint.url() <> "/l/" <> link.hash,
        views: link.views,
        created_at: link.inserted_at
      }
    }
  end

  def error(%{error: error} = assigns) do
    payload =
      assigns
      |> Map.take([:message, :details])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.put(:error, error)

    payload
  end
end
