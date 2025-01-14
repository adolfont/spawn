defmodule Actors.Actor.Entity.Invocation do
  @moduledoc """
  Handles Invocation functions for Actor Entity
  All the public functions here assumes they are executing inside a GenServer
  """
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Actors.Actor.Entity.EntityState

  alias Eigr.Functions.Protocol.Actors.{
    Actor,
    ActorId,
    ActorSystem,
    Command,
    FixedTimerCommand
  }

  alias Eigr.Functions.Protocol.{
    ActorInvocation,
    ActorInvocationResponse,
    Broadcast,
    Context,
    Forward,
    InvocationRequest,
    Pipe,
    SideEffect,
    Workflow,
    Noop
  }

  alias Phoenix.PubSub

  alias Spawn.Utils.AnySerializer

  @http_host_interface Actors.Actor.Interface.Http
  @host_interface_map %{
    "sdk" => SpawnSdk.Interface,
    "http" => @http_host_interface,
    "default" => @http_host_interface
  }

  @default_actions [
    "get",
    "Get",
    "get_state",
    "getState",
    "GetState"
  ]

  @default_init_actions [
    "init",
    "Init",
    "setup",
    "Setup"
  ]

  def timer_invoke(
        %FixedTimerCommand{command: %Command{name: cmd} = _command} = timer,
        %EntityState{
          system: _actor_system,
          actor: %Actor{id: caller_actor_id} = actor
        } = state
      ) do
    invocation = %InvocationRequest{
      actor: actor,
      command_name: cmd,
      payload: {:noop, Noop.new()},
      async: true,
      caller: caller_actor_id
    }

    invoke_result = invoke({invocation, []}, state)

    :ok = handle_timers([timer])

    case invoke_result do
      {:reply, _res, state} -> {:noreply, state}
      {:reply, _res, state, opts} -> {:noreply, state, opts}
    end
  end

  def handle_timers(timers) when is_list(timers) do
    if length(timers) > 0 do
      timers
      |> Stream.map(fn %FixedTimerCommand{seconds: delay} = timer_command ->
        Process.send_after(self(), {:invoke_timer_command, timer_command}, delay)
      end)
      |> Stream.run()
    end

    :ok
  catch
    error -> Logger.error("Error on handle timers #{inspect(error)}")
  end

  def handle_timers(nil), do: :ok

  def handle_timers([]), do: :ok

  def broadcast_invoke(
        command,
        payload,
        %ActorInvocation{actor: %ActorId{name: caller_actor_name, system: actor_system}},
        %EntityState{
          system: actor_system,
          actor: %Actor{id: %ActorId{name: actor_name} = _id} = actor
        } = state
      ) do
    Logger.debug(
      "Actor [#{actor_name}] Received Broadcast Event [#{inspect(payload)}] to perform Action [#{command}]"
    )

    invocation = %InvocationRequest{
      actor: actor,
      command_name: command,
      payload: payload,
      async: true,
      caller: ActorId.new(name: caller_actor_name, system: actor_system)
    }

    case invoke({invocation, []}, state) do
      {:reply, _res, state} -> {:noreply, state}
      {:reply, _res, state, opts} -> {:noreply, state, opts}
    end
  end

  def broadcast_invoke(
        payload,
        %EntityState{
          system: _actor_system,
          actor: %Actor{id: %ActorId{name: actor_name} = _id} = _actor
        } = state
      ) do
    Logger.debug(
      "Actor [#{actor_name}] Received Broadcast Event [#{inspect(payload)}] without command. Just ignoring"
    )

    {:noreply, state}
  end

  def invoke_init(
        %EntityState{
          system: actor_system,
          actor:
            %Actor{
              id: %ActorId{name: actor_name, parent: parent} = id,
              state: actor_state,
              commands: commands
            } = _actor
        } = state
      ) do
    if length(commands) <= 0 do
      Logger.warning("Actor [#{actor_name}] has not registered any Actions")
      {:noreply, state, :hibernate}
    else
      init_command =
        Enum.filter(commands, fn cmd -> Enum.member?(@default_init_actions, cmd.name) end)
        |> Enum.at(0)

      case init_command do
        nil ->
          {:noreply, state, :hibernate}

        _ ->
          interface = get_interface(actor_system)

          metadata = %{}

          request =
            ActorInvocation.new(
              actor: %ActorId{name: actor_name, system: actor_system, parent: parent},
              command_name: init_command.name,
              payload: Noop.new(),
              current_context:
                Context.new(
                  metadata: metadata,
                  caller: id,
                  self: ActorId.new(name: actor_name, system: actor_system),
                  state: actor_state
                ),
              caller: id
            )

          interface.invoke_host(request, state, @default_actions)
          |> case do
            {:ok, _response, new_state} ->
              {:noreply, new_state}

            {:error, _reason, new_state} ->
              {:noreply, new_state, :hibernate}
          end
      end
    end
  end

  @doc """
  Invoke function, receives a request and calls invoke host with the response
  """
  def invoke(
        {%InvocationRequest{
           actor:
             %Actor{
               id: %ActorId{name: actor_name} = id
             } = _actor,
           metadata: metadata,
           command_name: command,
           payload: payload,
           caller: caller
         }, opts},
        %EntityState{
          system: actor_system,
          actor: %Actor{state: actor_state, commands: commands, timer_commands: timers}
        } = state
      ) do
    ctx = Keyword.get(opts, :span_ctx, OpenTelemetry.Ctx.new())

    Tracer.with_span ctx, "#{actor_name} invocation handler", kind: :server do
      if length(commands) <= 0 do
        Logger.warning("Actor [#{actor_name}] has not registered any Actions")
      end

      all_commands =
        commands ++ Enum.map(timers, fn %FixedTimerCommand{command: cmd} = _timer_cmd -> cmd end)

      Tracer.set_attributes([
        {:invoked_command, command},
        {:actor_declared_commands, length(all_commands)}
      ])

      case Enum.member?(@default_actions, command) or
             Enum.any?(all_commands, fn cmd -> cmd.name == command end) do
        true ->
          interface = get_interface(actor_system)

          metadata = if is_nil(metadata), do: %{}, else: metadata
          current_state = Map.get(actor_state || %{}, :state)

          request =
            ActorInvocation.new(
              actor: id,
              command_name: command,
              payload: payload,
              current_context:
                Context.new(
                  metadata: metadata,
                  caller: caller,
                  self: id,
                  state: current_state
                ),
              caller: caller
            )

          Tracer.with_span "invoke-host" do
            interface.invoke_host(request, state, @default_actions)
            |> case do
              {:ok, response, state} ->
                Tracer.add_event("successful-invocation", [
                  {:ok, "#{inspect(response.updated_context.metadata)}"}
                ])

                {:reply, {:ok, do_response(request, response, state)}, state}

              {:error, reason, state} ->
                Tracer.add_event("failure-invocation", [
                  {:error, "#{inspect(reason)}"}
                ])

                {:reply, {:error, reason}, state, :hibernate}
            end
          end

        false ->
          {:reply, {:error, "Command [#{command}] not found for Actor [#{actor_name}]"}, state,
           :hibernate}
      end
    end
  end

  defp do_response(
         _request,
         %ActorInvocationResponse{workflow: workflow} = response,
         _state
       )
       when is_nil(workflow) or workflow == %{} do
    response
  end

  defp do_response(request, response, state) do
    do_run_workflow(request, response, state)
  end

  defp do_run_workflow(
         _request,
         %ActorInvocationResponse{workflow: workflow} = response,
         _state
       )
       when is_nil(workflow) or workflow == %{} do
    response
  end

  defp do_run_workflow(
         request,
         %ActorInvocationResponse{
           workflow: %Workflow{broadcast: broadcast, effects: effects} = _workflow
         } = response,
         _state
       ) do
    Tracer.with_span "run-workflow" do
      do_side_effects(effects)
      do_broadcast(request, broadcast)
      do_handle_routing(request, response)
    end
  end

  defp do_handle_routing(
         _request,
         %ActorInvocationResponse{
           workflow: %Workflow{routing: routing} = _workflow
         } = response
       )
       when is_nil(routing),
       do: response

  defp do_handle_routing(
         %ActorInvocation{
           actor: %ActorId{name: caller_actor_name, system: system_name}
         },
         %ActorInvocationResponse{
           payload: payload,
           workflow:
             %Workflow{
               routing: {:pipe, %Pipe{actor: actor_name, command_name: cmd} = _pipe} = _workflow
             } = response
         }
       ) do
    Tracer.with_span "run-pipe-routing" do
      invocation = %InvocationRequest{
        system: %ActorSystem{name: system_name},
        actor: %Actor{id: ActorId.new(name: actor_name, system: system_name)},
        command_name: cmd,
        payload: payload,
        caller: ActorId.new(name: caller_actor_name, system: system_name)
      }

      try do
        case Actors.invoke(invocation, span_ctx: OpenTelemetry.Tracer.current_span_ctx()) do
          {:ok, response} -> response
          error -> error
        end
      catch
        error ->
          Logger.warning(
            "Error during Pipe request to Actor #{system_name}:#{actor_name}. Error: #{inspect(error)}"
          )

          response
      end
    end
  end

  defp do_handle_routing(
         %ActorInvocation{
           actor: %ActorId{name: caller_actor_name, system: system_name},
           payload: payload
         } = _request,
         %ActorInvocationResponse{
           workflow:
             %Workflow{
               routing:
                 {:forward, %Forward{actor: actor_name, command_name: cmd} = _pipe} = _workflow
             } = response
         }
       ) do
    Tracer.with_span "run-forward-routing" do
      invocation = %InvocationRequest{
        system: %ActorSystem{name: system_name},
        actor: %Actor{id: ActorId.new(name: actor_name, system: system_name)},
        command_name: cmd,
        payload: payload,
        caller: ActorId.new(name: caller_actor_name, system: system_name)
      }

      try do
        case Actors.invoke(invocation, span_ctx: OpenTelemetry.Tracer.current_span_ctx()) do
          {:ok, response} -> response
          error -> error
        end
      catch
        error ->
          Logger.warning(
            "Error during Forward request to Actor #{system_name}:#{actor_name}. Error: #{inspect(error)}"
          )

          response
      end
    end
  end

  def do_broadcast(_request, broadcast) when is_nil(broadcast) or broadcast == %{} do
    :ok
  end

  def do_broadcast(
        request,
        %Broadcast{channel_group: channel, command_name: command, payload: payload} = _broadcast
      ) do
    Tracer.with_span "run-broadcast" do
      Tracer.add_event("publish", [{"channel", channel}])
      Tracer.set_attributes([{:command, command}])

      spawn(fn -> publish(channel, command, payload, request) end)
    end
  end

  defp publish(channel, command, payload, _request) when is_nil(command) do
    PubSub.broadcast(
      :actor_channel,
      channel,
      {:receive, parse_external_broadcast_message(payload)}
    )
  end

  defp publish(channel, command, payload, request) do
    PubSub.broadcast(
      :actor_channel,
      channel,
      {:receive, command, payload, request}
    )
  end

  defp parse_external_broadcast_message({:value, %Google.Protobuf.Any{} = any}) do
    AnySerializer.unpack_unknown(any)
  end

  defp parse_external_broadcast_message(_any), do: %{}

  def do_side_effects(effects) when effects == [] do
    :ok
  end

  def do_side_effects(effects) when is_list(effects) do
    Tracer.with_span "handle-side-effects" do
      try do
        spawn(fn ->
          effects
          |> Flow.from_enumerable(min_demand: 1, max_demand: System.schedulers_online())
          |> Flow.map(fn %SideEffect{
                           request:
                             %InvocationRequest{
                               actor: %Actor{id: %ActorId{name: actor_name} = _id} = _actor,
                               system: %ActorSystem{name: system_name}
                             } = invocation
                         } ->
            try do
              Actors.invoke(invocation, span_ctx: Tracer.current_span_ctx())
            catch
              error ->
                Logger.warning(
                  "Error during Side Effect request to Actor #{system_name}:#{actor_name}. Error: #{inspect(error)}"
                )

                :ok
            end
          end)
          |> Flow.run()
        end)
      catch
        error ->
          Logger.warning("Error during Side Effect request. Error: #{inspect(error)}")
          :ok
      end
    end
  end

  defp get_interface(system_name) do
    if :persistent_term.get(system_name, false) do
      @host_interface_map["sdk"]
    else
      @host_interface_map[System.get_env("PROXY_HOST_INTERFACE", "default")]
    end
  end
end
