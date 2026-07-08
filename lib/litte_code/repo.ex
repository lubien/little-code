defmodule LitteCode.Repo do
  use Ecto.Repo,
    otp_app: :litte_code,
    adapter: Ecto.Adapters.Postgres
end
