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

  describe "create_link/2 with admin?: true" do
    test "accepts a custom slug" do
      assert {:ok, %Link{slug: "my-link", url: "https://example.com"}} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => "my-link"},
                 admin?: true
               )
    end

    test "normalizes slug to lowercase and trims" do
      {:ok, %Link{slug: "my-link"}} =
        Links.create_link(
          %{"url" => "https://example.com", "slug" => "  MY-Link  "},
          admin?: true
        )
    end

    test "rejects invalid slug characters" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => "My_Link!"},
                 admin?: true
               )

      assert %{slug: [_ | _]} = errors_on(cs)
    end

    test "rejects slugs that start or end with a dash" do
      assert {:error, cs} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => "-nope"},
                 admin?: true
               )

      assert %{slug: [_ | _]} = errors_on(cs)

      assert {:error, cs} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => "nope-"},
                 admin?: true
               )

      assert %{slug: [_ | _]} = errors_on(cs)
    end

    test "rejects reserved slugs" do
      assert {:error, cs} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => "admin"},
                 admin?: true
               )

      assert %{slug: ["is reserved"]} = errors_on(cs)
    end

    test "returns a changeset error when slug is already taken" do
      {:ok, _} =
        Links.create_link(
          %{"url" => "https://example.com/a", "slug" => "taken"},
          admin?: true
        )

      assert {:error, %Ecto.Changeset{} = cs} =
               Links.create_link(
                 %{"url" => "https://example.com/b", "slug" => "taken"},
                 admin?: true
               )

      assert %{slug: ["is already taken"]} = errors_on(cs)
    end

    test "empty / nil slug is treated as \"no slug\"" do
      assert {:ok, %Link{slug: nil}} =
               Links.create_link(
                 %{"url" => "https://example.com", "slug" => ""},
                 admin?: true
               )

      assert {:ok, %Link{slug: nil}} =
               Links.create_link(
                 %{"url" => "https://example.com/2", "slug" => nil},
                 admin?: true
               )
    end
  end

  describe "create_link/2 without admin? flag" do
    test "silently ignores any submitted slug" do
      assert {:ok, %Link{slug: nil}} =
               Links.create_link(%{"url" => "https://example.com", "slug" => "my-link"})
    end
  end

  describe "get_by_slug/1" do
    test "returns the link when a slug matches" do
      {:ok, link} =
        Links.create_link(
          %{"url" => "https://example.com", "slug" => "findme"},
          admin?: true
        )

      assert %Link{id: id} = Links.get_by_slug("findme")
      assert id == link.id
    end

    test "returns nil for unknown slugs" do
      assert Links.get_by_slug("nope") == nil
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
