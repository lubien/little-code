defmodule LitteCodeWeb.PageController do
  use LitteCodeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
