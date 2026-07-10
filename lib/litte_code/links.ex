defmodule LitteCode.Links do
  @moduledoc """
  The Links context handles shortened URL creation, lookup, and view tracking.
  """

  import Ecto.Query, warn: false

  alias LitteCode.Repo
  alias LitteCode.Links.Link

  # Base32 without ambiguous characters (0/O, 1/I/L) — nice for humans + URLs
  @alphabet ~c"23456789abcdefghjkmnpqrstuvwxyz"
  @initial_length 5
  @max_length 12
  @max_attempts_per_length 5

  @doc """
  Returns a changeset for building a new link — handy for form rendering.
  Pass `admin?: true` to expose the `:slug` field.
  """
  def change_link(%Link{} = link \\ %Link{}, attrs \\ %{}, opts \\ []) do
    if Keyword.get(opts, :admin?, false) do
      Link.admin_changeset(link, attrs)
    else
      Link.changeset(link, attrs)
    end
  end

  @doc """
  Creates a shortened link, generating a unique hash for it.

  Options:
    * `:admin?` — when `true`, the `slug` field is accepted and validated.
      When `false` (default), any submitted slug is silently ignored.

  Returns `{:ok, link}` on success, or `{:error, %Ecto.Changeset{}}` on
  validation failure. Returns `{:error, :hash_exhausted}` in the (nearly
  impossible) case of running out of hash space.
  """
  def create_link(attrs, opts \\ []) do
    admin? = Keyword.get(opts, :admin?, false)

    changeset =
      if admin?, do: Link.admin_changeset(%Link{}, attrs), else: Link.changeset(%Link{}, attrs)

    with {:ok, applied} <- Ecto.Changeset.apply_action(changeset, :insert) do
      insert_with_unique_hash(applied, @initial_length, 0)
    end
  end

  defp insert_with_unique_hash(_link, length, _attempt) when length > @max_length do
    {:error, :hash_exhausted}
  end

  defp insert_with_unique_hash(link, length, attempt)
       when attempt >= @max_attempts_per_length do
    insert_with_unique_hash(link, length + 1, 0)
  end

  defp insert_with_unique_hash(link, length, attempt) do
    hash = generate_hash(length)

    %Link{}
    |> Ecto.Changeset.change(url: link.url, hash: hash, slug: link.slug)
    |> Ecto.Changeset.unique_constraint(:hash)
    |> Ecto.Changeset.unique_constraint(:slug,
      name: :links_slug_index,
      message: "is already taken"
    )
    |> Repo.insert()
    |> case do
      {:ok, link} ->
        {:ok, link}

      {:error, changeset} ->
        cond do
          hash_taken?(changeset) -> insert_with_unique_hash(link, length, attempt + 1)
          # Bubble slug collisions back as a normal changeset error so the
          # LiveView / API can render a nice "slug already taken" message.
          true -> {:error, changeset}
        end
    end
  end

  defp hash_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:hash, {_, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp generate_hash(length) do
    for _ <- 1..length, into: "", do: <<Enum.random(@alphabet)>>
  end

  @doc """
  Fetches a link by its hash. Returns `nil` if not found.
  """
  def get_by_hash(hash) when is_binary(hash) do
    Repo.get_by(Link, hash: hash)
  end

  def get_by_hash(_), do: nil

  @doc """
  Fetches a link by its (custom) slug. Returns `nil` if not found.
  """
  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Link, slug: slug)
  end

  def get_by_slug(_), do: nil

  @doc """
  Atomically increments the view counter for a link.
  """
  def increment_views(%Link{id: id}) do
    from(l in Link, where: l.id == ^id, update: [inc: [views: 1]])
    |> Repo.update_all([])

    :ok
  end
end
