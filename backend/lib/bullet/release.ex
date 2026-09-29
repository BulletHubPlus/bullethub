defmodule Bullet.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bullet

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Grants a staff role to an existing account, e.g. the first owner:

      bin/bullet eval 'Bullet.Release.promote("voce@exemplo.com", "owner")'
  """
  def promote(email, role) when role in ~w(owner editor support subscriber) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    case Bullet.Accounts.get_user_by_email(email) do
      nil -> IO.puts("no user with e-mail #{email}")
      user -> {:ok, _} = Bullet.Accounts.set_role(user, String.to_existing_atom(role))
    end
  end

  @doc """
  Grants a plan manually until the payment gateway exists (Fase 3):

      bin/bullet eval 'Bullet.Release.grant_subscription("voce@exemplo.com", "padrao", 30)'
  """
  def grant_subscription(email, plan_slug, days \\ 30) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    case Bullet.Accounts.get_user_by_email(email) do
      nil -> IO.puts("no user with e-mail #{email}")
      user -> {:ok, _} = Bullet.Billing.grant(user, plan_slug, days)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
