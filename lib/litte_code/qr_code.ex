defmodule LitteCode.QRCode do
  @moduledoc """
  Thin wrapper around `EQRCode` that returns an inline SVG suitable for
  rendering directly into HTML. Uses `viewBox` so the caller controls sizing.
  """

  @max_length 2000

  @doc """
  Generates an SVG string for the given text.

  Returns `nil` for empty text so callers can render an empty state.
  """
  @spec to_svg(String.t() | nil, keyword()) :: String.t() | nil
  def to_svg(text, opts \\ [])
  def to_svg(nil, _opts), do: nil

  def to_svg(text, opts) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        nil

      String.length(trimmed) > @max_length ->
        nil

      true ->
        trimmed
        |> EQRCode.encode()
        |> EQRCode.svg(Keyword.merge([viewbox: true, color: "#0f172a"], opts))
    end
  end
end
