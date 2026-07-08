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
  """
  def change_link(%Link{} = link \\ %Link{}, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  @doc """
  Creates a shortened link, generating a unique hash for it.

  The hash starts at #{@initial_length} characters and grows on collisions.
  """
  def create_link(attrs) do
    changeset = Link.changeset(%Link{}, attrs)

    with {:ok, url} <- Ecto.Changeset.apply_action(changeset, :insert) do
      insert_with_unique_hash(url, @initial_length, 0)
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
    |> Ecto.Changeset.change(url: link.url, hash: hash)
    |> Ecto.Changeset.unique_constraint(:hash)
    |> Repo.insert()
    |> case do
      {:ok, link} ->
        {:ok, link}

      {:error, changeset} ->
        if hash_taken?(changeset) do
          insert_with_unique_hash(link, length, attempt + 1)
        else
          {:error, changeset}
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
  Atomically increments the view counter for a link.
  """
  def increment_views(%Link{id: id}) do
    from(l in Link, where: l.id == ^id, update: [inc: [views: 1]])
    |> Repo.update_all([])

    :ok
  end
end
