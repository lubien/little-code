defmodule LitteCode.Links.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "links" do
    field :hash, :string
    field :url, :string
    field :views, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset used when a visitor submits a URL to be shortened.

  `hash` is set programmatically by the context, so it is intentionally
  excluded from `cast/3`.
  """
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url])
    |> validate_required([:url])
    |> update_change(:url, &String.trim/1)
    |> validate_length(:url, max: 2048)
    |> validate_url(:url)
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
