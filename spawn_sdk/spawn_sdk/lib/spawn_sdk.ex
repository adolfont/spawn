defmodule SpawnSdk do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @doc """
  Invokes a function for a actor_name

  ## Opts

  - `system` this is required
  - `ref` attribute attribute will always lookup to see if the referenced actor is already started or not.
  - `payload` attribute is optional.
  - `command` has default values that you can use to get current actor state
    - get, get_state, Get, getState, GetState

  ## Examples

  ```elixir
  iex> SpawnSdk.invoke(
    "actor_name",
    ref: SpawnSdkExample.Actors.AbstractActor,
    system: "spawn-system",
    command: "sum", # "sum" or :sum
    payload: %Io.Eigr.Spawn.Example.MyBusinessMessage{value: 5}
  )
  {:ok, %Io.Eigr.Spawn.Example.MyBusinessMessage{value: 5}}

  iex> SpawnSdk.invoke("actor_name", system: "spawn-system", command: "get")
  {:ok, %Io.Eigr.Spawn.Example.MyBusinessMessage{value: 5}}
  ```
  """
  defdelegate invoke(actor_name, invoke_opts), to: SpawnSdk.System.SpawnSystem

  @doc """
  Spawns a abstract actor

  A abstract actor means that you can spawn dynamically the same actor for multiple different names.
  It is analog to `DynamicSupervisor`

  ## Opts

  - `system` this is required
  - `actor` which actor you will register first argument to

  ## Examples

  ```elixir
  iex> SpawnSdk.spawn_actor(
    "actor_name",
    system: "spawn-system",
    actor: SpawnSdkExample.Actors.AbstractActor
  )
  ```
  """
  defdelegate spawn_actor(actor_name, spawn_actor_opts), to: SpawnSdk.System.SpawnSystem
end
