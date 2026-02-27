defmodule AshJidoConsumer.Repo do
  use AshPostgres.Repo,
    otp_app: :ash_jido_consumer,
    warn_on_missing_ash_functions?: false

  def min_pg_version do
    %Version{major: 13, minor: 0, patch: 0}
  end
end
