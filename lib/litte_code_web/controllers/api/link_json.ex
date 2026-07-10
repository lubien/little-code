defmodule LitteCodeWeb.Api.LinkJSON do
  @moduledoc false

  alias LitteCode.Links.Link

  def show(%{link: %Link{} = link}) do
    %{
      data: %{
        hash: link.hash,
        slug: link.slug,
        url: link.url,
        short_url: short_url(link),
        views: link.views,
        created_at: link.inserted_at
      }
    }
  end

  def error(%{error: error} = assigns) do
    assigns
    |> Map.take([:message, :details])
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.put(:error, error)
  end

  defp short_url(%Link{slug: slug, hash: hash}) do
    base = LitteCodeWeb.Endpoint.url()
    if slug, do: base <> "/c/" <> slug, else: base <> "/l/" <> hash
  end
end
