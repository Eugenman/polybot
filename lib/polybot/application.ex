defmodule Polybot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PolybotWeb.Telemetry,
        Polybot.Repo,
        {DNSCluster, query: Application.get_env(:polybot, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Polybot.PubSub}
      ] ++
        scheduler() ++
        [PolybotWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Polybot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Disabled in tests: the scheduler would call Gamma and Claude on its own.
  defp scheduler do
    if Application.get_env(:polybot, :start_scheduler, true), do: [Polybot.Scheduler], else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PolybotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
