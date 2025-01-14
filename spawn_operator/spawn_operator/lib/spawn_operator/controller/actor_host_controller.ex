defmodule SpawnOperator.Controller.ActorHostController do
  require Bonny.API.CRD

  use Bonny.ControllerV2

  step(Bonny.Pluggable.SkipObservedGenerations)
  step(SpawnOperator.Handler.ActorHostHandler)

  @impl true
  def rbac_rules() do
    [
      to_rbac_rule({"", ["node", "nodes"], ["get", "list"]}),
      to_rbac_rule({"v1", ["node", "nodes"], ["get", "list"]}),
      to_rbac_rule({"", ["secrets"], ["*"]}),
      to_rbac_rule({"v1", ["pods"], ["*"]}),
      to_rbac_rule({"apps", ["deployments"], ["*"]}),
      to_rbac_rule({"", ["services", "configmaps"], ["*"]}),
      to_rbac_rule({"autoscaling", ["horizontalpodautoscalers"], ["*"]}),
      to_rbac_rule({"extensions", ["ingresses", "ingressclasses"], ["*"]}),
      to_rbac_rule({"networking.k8s.io", ["ingresses", "ingressclasses"], ["*"]})
    ]
  end
end
