defmodule LitteCodeWeb.I18n do
  @moduledoc """
  Locale metadata and helpers used across the router, plugs, LiveViews,
  and the language switcher UI.
  """

  @default_locale "en"

  @locales [
    %{code: "en", label: "English", short: "EN", flag: "🇺🇸"},
    %{code: "pt_BR", label: "Português (Brasil)", short: "PT", flag: "🇧🇷"}
  ]

  @codes Enum.map(@locales, & &1.code)

  @doc "Default application locale."
  @spec default_locale() :: String.t()
  def default_locale, do: @default_locale

  @doc "All supported locales, in display order, with metadata for the UI."
  @spec locales() :: [%{code: String.t(), label: String.t(), short: String.t(), flag: String.t()}]
  def locales, do: @locales

  @doc "List of supported locale codes."
  @spec locale_codes() :: [String.t()]
  def locale_codes, do: @codes

  @doc "Whether the given locale code is one we support."
  @spec supported?(String.t() | nil) :: boolean()
  def supported?(code) when is_binary(code), do: code in @codes
  def supported?(_), do: false

  @doc """
  Normalizes a raw locale code (e.g. from `Accept-Language`) to one of
  our supported locales, or returns the default when nothing matches.
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(code) do
    match_locale(code) || @default_locale
  end

  # Returns the matching supported locale for `code`, or `nil` if there
  # is no genuine match (i.e. we would otherwise fall back to default).
  defp match_locale(code) when is_binary(code) do
    cond do
      supported?(code) ->
        code

      # Try normalizing `pt-BR` → `pt_BR`, `en-US` → `en`, etc.
      String.contains?(code, "-") ->
        [lang, region | _] = String.split(code, "-", parts: 2) ++ [""]
        candidate = "#{lang}_#{String.upcase(region)}"

        cond do
          supported?(candidate) -> candidate
          supported?(lang) -> lang
          true -> nil
        end

      true ->
        lang = code |> String.split("_") |> hd()
        if supported?(lang), do: lang
    end
  end

  defp match_locale(_), do: nil

  @doc "Parses an `Accept-Language` header string and returns the best-matching supported locale."
  @spec from_accept_language(String.t() | nil) :: String.t() | nil
  def from_accept_language(nil), do: nil
  def from_accept_language(""), do: nil

  def from_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_code, q} -> q end, :desc)
    |> Enum.find_value(fn {code, _q} -> match_locale(code) end)
  end

  defp parse_language_entry(entry) do
    case String.split(entry, ";", trim: true) do
      [tag] ->
        {String.trim(tag), 1.0}

      [tag | params] ->
        q =
          params
          |> Enum.find_value(fn param ->
            case String.split(String.trim(param), "=") do
              ["q", value] -> Float.parse(value) |> elem(0)
              _ -> nil
            end
          end) || 1.0

        {String.trim(tag), q}

      _ ->
        nil
    end
  end
end
