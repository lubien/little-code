defmodule LitteCode.Links.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  # Custom slugs must be URL-safe and unambiguous:
  #   * lowercase alphanumerics and dashes
  #   * 2–50 chars total
  #   * cannot start or end with a dash
  @slug_regex ~r/^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$/

  # Words that we want to keep free for future top-level routes under `/c/`.
  # Rejected outright even for admins.
  @reserved_slugs ~w(admin api l c up docs new dev robots sitemap assets images fonts)

  schema "links" do
    field :hash, :string
    field :slug, :string
    field :url, :string
    field :views, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Public-facing changeset (URL only). `hash` and `slug` are set
  programmatically by the context and never cast from user input here.
  """
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url])
    |> validate_required([:url])
    |> update_change(:url, &String.trim/1)
    |> validate_length(:url, max: 2048)
    |> validate_url(:url)
  end

  @doc """
  Changeset used when an admin submits a custom slug alongside the URL.
  """
  def admin_changeset(link, attrs) do
    link
    |> changeset(attrs)
    |> cast(attrs, [:slug])
    |> update_change(:slug, &normalize_slug/1)
    |> validate_slug(:slug)
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.downcase(trimmed)
    end
  end

  defp validate_slug(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      slug ->
        cond do
          not Regex.match?(@slug_regex, slug) ->
            add_error(
              changeset,
              field,
              "must be 2–50 lowercase letters, digits, or dashes (no leading or trailing dash)"
            )

          slug in @reserved_slugs ->
            add_error(changeset, field, "is reserved")

          true ->
            changeset
        end
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid http(s) URL"}]
      end
    end)
  end
end
