defmodule SpawnOperator.Handler.ActorHostHandler do
  @moduledoc """
  `ActorHostHandler` handles ActorHost CRD events
  """
  defmacro __using__(_) do
    quote do
      @impl true
      def add(_res), do: :ok

      @impl true
      def modify(_res), do: :ok

      @impl true
      def delete(_res), do: :ok

      @impl true
      def reconcile(_res), do: :ok
    end
  end
end
