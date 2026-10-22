defmodule Taina.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    load_lexicons()

    children = [
      TainaWeb.Telemetry,
      Taina.Repo,
      Taina.Ybira.BlobLock,
      {DNSCluster, query: Application.get_env(:taina, :dns_cluster_query) || :ignore},
      {Taina.RateLimit, clean_period: to_timeout(minute: 10)},
      {Oban, Application.fetch_env!(:taina, Oban)},
      {Phoenix.PubSub, name: Taina.PubSub},
      TainaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Taina.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TainaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # O registro de lexicons (RFC_006, secao 6): kernel primeiro, produto depois
  # (um `id` repetido no produto sobrescreve o do kernel). Le uma vez no boot e
  # fica em `:persistent_term`, so leitura depois. Um lexicon quebrado vira
  # aviso no log, nunca um boot caido.
  defp load_lexicons do
    {_entries, problems} =
      Ypy.Lexicon.Registry.load([
        Application.app_dir(:ypy, "priv/lexicons"),
        Path.expand("../priv/lexicons", __DIR__)
      ])

    Enum.each(problems, fn {path, reason} ->
      Logger.warning("Lexicon invalido ignorado: #{path} (#{inspect(reason)})")
    end)
  end
end
