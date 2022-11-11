defmodule Actors.Registry.LoadBalance.Strategies.Random do
  @behaviour Actors.Registry.LoadBalance.Strategy

  @impl Actors.Registry.LoadBalance.Strategy
  def next_host(hosts, opts \\ [])

  def next_host(hosts, _opts) when is_nil(hosts), do: {:not_found, nil, []}

  def next_host([], _opts), do: {:not_found, nil, []}

  def next_host(hosts, _opts) when is_list(hosts) and length(hosts) > 0 do
    {:ok, Enum.random(hosts), hosts}
  end
end