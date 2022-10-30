defmodule Statestores.Adapters.MySQL do
  use Statestores.Adapters.Behaviour

  use Ecto.Repo,
    otp_app: :spawn_statestores,
    adapter: Ecto.Adapters.MyXQL

  alias Statestores.Schemas.{Event, ValueObjectSchema}

  def get_by_key(actor), do: get_by(Event, actor: actor)

  def save(%Event{revision: revision, tags: tags, data_type: type, data: data} = event) do
    %Event{}
    |> Event.changeset(ValueObjectSchema.to_map(event))
    |> insert_or_update!(
      on_conflict: [
        set: [
          revision: revision,
          tags: tags,
          data_type: type,
          data: data,
          updated_at: DateTime.utc_now()
        ]
      ]
    )
    |> case do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}

      other ->
        {:error, other}
    end
  end

  def default_port, do: "3306"

  def migrate() do
    {:ok, _, _} = Ecto.Migrator.with_repo(__MODULE__, &Ecto.Migrator.run(&1, :up, all: true))
  end

  def rollback_migration(version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(__MODULE__, &Ecto.Migrator.run(&1, :down, to: version))
  end
end
