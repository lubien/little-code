defmodule LitteCode.LinksTest do
  use LitteCode.DataCase, async: true

  alias LitteCode.Links
  alias LitteCode.Links.Link

  describe "create_link/1" do
    test "creates a link with a generated hash for a valid URL" do
      assert {:ok, %Link{} = link} = Links.create_link(%{"url" => "https://example.com"})
      assert link.url == "https://example.com"
      assert String.length(link.hash) >= 5
      assert link.views == 0
    end

    test "trims whitespace from the URL" do
      assert {:ok, link} = Links.create_link(%{"url" => "  https://example.com  "})
      assert link.url == "https://example.com"
    end

    test "rejects URLs without a scheme" do
      assert {:error, %Ecto.Changeset{} = cs} = Links.create_link(%{"url" => "example.com"})
      assert %{url: ["must be a valid http(s) URL"]} = errors_on(cs)
    end

    test "rejects non-http schemes" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Links.create_link(%{"url" => "javascript:alert(1)"})

      assert %{url: [_ | _]} = errors_on(cs)
    end

    test "rejects empty URLs" do
      assert {:error, %Ecto.Changeset{} = cs} = Links.create_link(%{"url" => ""})
      assert %{url: ["can't be blank"]} = errors_on(cs)
    end
  end

  describe "get_by_hash/1" do
    test "returns the link when it exists" do
      {:ok, link} = Links.create_link(%{"url" => "https://example.com"})
      assert %Link{id: id} = Links.get_by_hash(link.hash)
      assert id == link.id
    end

    test "returns nil for unknown hashes" do
      assert Links.get_by_hash("nope!") == nil
    end
  end

  describe "increment_views/1" do
    test "atomically increments the view count" do
      {:ok, link} = Links.create_link(%{"url" => "https://example.com"})
      assert :ok = Links.increment_views(link)
      assert :ok = Links.increment_views(link)

      assert Links.get_by_hash(link.hash).views == 2
    end
  end
end
