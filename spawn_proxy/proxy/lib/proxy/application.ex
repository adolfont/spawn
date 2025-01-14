defmodule Proxy.Application do
  @moduledoc false
  use Application
  require Logger

  alias Actors.Config.Vapor, as: Config

  @impl true
  def start(_type, _args) do
    [time: _time, humanized_duration: humanized_duration, reply: reply] =
      Timer.tc(fn ->
        config = Config.load(__MODULE__)

        children = [
          {Proxy.Supervisor, config}
        ]

        opts = [strategy: :one_for_one, name: Proxy.RootSupervisor]

        Supervisor.start_link(children, opts)
      end)

    with {:ok, pid} <- reply do
      Logger.info("Proxy started successfully in #{humanized_duration}")
      {:ok, pid}
    else
      result ->
        raise RuntimeError, "Failed to start proxy. #{inspect(result)}"
    end
  end
end
