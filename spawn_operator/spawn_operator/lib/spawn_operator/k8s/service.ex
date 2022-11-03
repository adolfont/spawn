defmodule SpawnOperator.K8s.Service do
  @moduledoc false

  @behaviour SpawnOperator.K8s.Manifest

  @default_actor_host_function_ports [
    %{"name" => "proxy-http", "protocol" => "TCP", "port" => 9000, "targetPort" => "proxy-http"},
    %{"name" => "proxy-https", "protocol" => "TCP", "port" => 9001, "targetPort" => "proxy-https"}
  ]

  @impl true
  def manifest(_system, ns, name, params) do
    host_params = Map.get(params, "host")
    actor_host_function_ports = Map.get(host_params, "ports", [])

    actor_host_function_ports =
      Enum.map(actor_host_function_ports, fn map ->
        if Map.has_key?(map, "containerPort") do
          port = Map.get(map, "containerPort")
          m = Map.delete(map, "containerPort")
          Map.put(m, "port", port)
        else
          map
        end
      end)

    actor_host_function_ports =
      (actor_host_function_ports ++
         @default_actor_host_function_ports)
      |> Enum.uniq()

    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => %{
        "labels" => %{
          "spawn-eigr.io/controller.version" =>
            "#{to_string(Application.spec(:spawn_operator, :vsn))}"
        },
        "name" => "#{name}-svc",
        "namespace" => ns
      },
      "spec" => %{
        "selector" => %{"app" => name},
        "ports" => actor_host_function_ports
      }
    }
  end
end