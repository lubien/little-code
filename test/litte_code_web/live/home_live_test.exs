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
      # SSR renders an initial QR SVG so users see something before JS boots.
      assert has_element?(view, "#qr-preview-wrapper [data-qr-preview] svg")
    end

    test "the QR input opts out of iOS Safari's autocorrect / autocapitalize", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(autocorrect="off")
      assert html =~ ~s(autocapitalize="off")
      assert html =~ ~s(spellcheck="false")
    end

    test "the QR panel wires up the client-side generator hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s|#qr-code-generator[phx-hook="QRPreview"]|)
      assert has_element?(view, "#qr-text-input")
    end

    test "renders Download PNG and Copy image buttons for the QR", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert has_element?(view, "button[data-qr-download]")
      assert has_element?(view, "button[data-qr-copy]")
      assert html =~ "Download PNG"
      assert html =~ "Copy image"
    end

    test "renders the tagline and the ad-free explainer", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Tiny links and pretty QR codes. Nothing else."

      assert html =~
               "I got pissed at QR Code sites so I built my own with no ads and no charges"
    end

    test "renders the language switcher with EN and PT buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#lang-en")
      assert has_element?(view, "#lang-pt_BR")
    end

    test "renders the page in Portuguese when the session locale is pt_BR", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"locale" => "pt_BR"})
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Links minúsculos e QR codes bonitos. Nada mais."
      assert html =~ "Encurtar URL"
    end

    test "honors Accept-Language when there is no session locale", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("accept-language", "pt-BR,pt;q=0.9,en;q=0.7")

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Encurtar URL"
    end

    test "defaults to English when Accept-Language has nothing we support", %{conn: conn} do
      conn = Plug.Conn.put_req_header(conn, "accept-language", "fr-FR,fr;q=0.9")
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Shorten URL"
      refute html =~ "Encurtar URL"
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
