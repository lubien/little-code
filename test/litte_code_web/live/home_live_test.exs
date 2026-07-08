defmodule LitteCodeWeb.HomeLiveTest do
  use LitteCodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LitteCode.Captcha

  describe "home page" do
    test "renders both tabs and the QR panel by default", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "little-co.de"
      assert has_element?(view, "#tab-qr")
      assert has_element?(view, "#tab-shorten")
      assert has_element?(view, "#qr-panel")
      assert has_element?(view, "#qr-preview svg")
    end

    test "footer credits Lubien and Phoenix Framework", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Phoenix Framework"
      assert html =~ "Lubien"
      assert html =~ "https://github.com/lubien"
    end

    test "renders social sharing meta tags", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(property="og:site_name" content="little-co.de")
      assert html =~ ~s(property="og:type" content="website")
      assert html =~ ~s(property="og:image")
      assert html =~ "/images/og-image.png"
      assert html =~ ~s(property="og:image:type" content="image/png")
      assert html =~ ~s(name="twitter:card" content="summary_large_image")
      assert html =~ ~s(<link) and html =~ ~s(rel="canonical")
    end

    test "typing text updates the QR code preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#qr-form", qr: %{text: "hello world"})
        |> render_change()

      assert html =~ "<svg"
      assert has_element?(view, "#qr-preview svg")
    end

    test "clearing text hides the QR preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#qr-form", qr: %{text: ""})
      |> render_change()

      refute has_element?(view, "#qr-preview")
    end
  end

  describe "shorten tab" do
    test "switching to shorten tab reveals the shortener form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      assert has_element?(view, "#shorten-panel")
      assert has_element?(view, "#shorten-form")
    end

    test "rejects invalid URLs on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      html =
        view
        |> form("#shorten-form", link: %{url: "not a url"})
        |> render_change()

      assert html =~ "must be a valid http(s) URL"
    end

    test "submitting without a captcha shows an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      # Simulate a bot posting the raw form event with no captcha payload.
      render_hook(view, "shorten_submit", %{"link" => %{"url" => "https://example.com"}})

      assert render(view) =~ "Please solve the captcha"
      refute has_element?(view, "#shorten-result")
    end

    test "submitting with a wrong captcha answer shows an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      %{token: token} = Captcha.new()

      render_hook(view, "shorten_submit", %{
        "link" => %{"url" => "https://example.com"},
        "captcha_token" => token,
        "captcha_answer" => "999999"
      })

      assert render(view) =~ "Captcha answer was incorrect"
      refute has_element?(view, "#shorten-result")
    end

    test "silently drops requests that fill the honeypot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      %{token: token, question: q} = Captcha.new()

      render_hook(view, "shorten_submit", %{
        "link" => %{"url" => "https://example.com"},
        "captcha_token" => token,
        "captcha_answer" => solve_captcha(q),
        "website" => "i-am-a-bot.example"
      })

      refute has_element?(view, "#shorten-result")
    end

    test "creates a shortened link with a valid captcha answer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=shorten")

      %{token: token, question: q} = Captcha.new()

      render_hook(view, "shorten_submit", %{
        "link" => %{"url" => "https://example.com/hello"},
        "captcha_token" => token,
        "captcha_answer" => solve_captcha(q)
      })

      assert has_element?(view, "#shorten-result")
      assert render(view) =~ "Your short link"

      assert [link] = LitteCode.Repo.all(LitteCode.Links.Link)
      assert link.url == "https://example.com/hello"
    end
  end

  defp solve_captcha(question) do
    [a_str, op, b_str] = String.split(question, " ", trim: true)
    {a, ""} = Integer.parse(a_str)
    {b, ""} = Integer.parse(b_str)

    case op do
      "+" -> Integer.to_string(a + b)
      "-" -> Integer.to_string(a - b)
    end
  end
end
