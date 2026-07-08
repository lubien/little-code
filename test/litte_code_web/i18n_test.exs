defmodule LitteCodeWeb.I18nTest do
  use ExUnit.Case, async: true

  alias LitteCodeWeb.I18n

  describe "supported?/1" do
    test "accepts known locales" do
      assert I18n.supported?("en")
      assert I18n.supported?("pt_BR")
    end

    test "rejects unknown locales" do
      refute I18n.supported?("fr")
      refute I18n.supported?("pt")
      refute I18n.supported?(nil)
      refute I18n.supported?("")
    end
  end

  describe "normalize/1" do
    test "returns supported codes verbatim" do
      assert I18n.normalize("en") == "en"
      assert I18n.normalize("pt_BR") == "pt_BR"
    end

    test "converts BCP-47 tags to gettext form" do
      assert I18n.normalize("pt-BR") == "pt_BR"
      assert I18n.normalize("pt-br") == "pt_BR"
    end

    test "falls back to the language when the region isn't supported" do
      assert I18n.normalize("en-US") == "en"
      assert I18n.normalize("en-GB") == "en"
    end

    test "falls back to default for unknown locales" do
      assert I18n.normalize("fr") == "en"
      assert I18n.normalize("zh-CN") == "en"
      assert I18n.normalize(nil) == "en"
    end
  end

  describe "from_accept_language/1" do
    test "returns nil for empty header" do
      assert I18n.from_accept_language(nil) == nil
      assert I18n.from_accept_language("") == nil
    end

    test "prefers the highest quality supported locale" do
      # Portuguese preferred, English fallback — should return pt_BR.
      assert I18n.from_accept_language("pt-BR,pt;q=0.9,en;q=0.8") == "pt_BR"
    end

    test "picks English when no Portuguese variant is present" do
      assert I18n.from_accept_language("en-US,en;q=0.9") == "en"
    end

    test "skips locales we don't support" do
      assert I18n.from_accept_language("fr-FR,fr;q=0.9,en;q=0.5") == "en"
    end

    test "returns nil when the header has no supported locale" do
      assert I18n.from_accept_language("fr-FR,fr;q=0.9,zh-CN;q=0.5") == nil
    end
  end
end
