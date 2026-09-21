defmodule VyaasaCampus.Schema.Students.AttemptGrant do
  @moduledoc """
  Extra attempts granted to one student for one assessment module (tenant schema).

  Append-only — grants accumulate and are summed by `Contexts.AttemptGuard`, so
  each stays attributable to the admin who made it and the reason they gave.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :student_id, :module, :extra_attempts, :reason, :granted_by_id, :granted_at]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempt_grants" do
    field :student_id, :binary_id
    field :module, :string
    field :extra_attempts, :integer, default: 1
    field :reason, :string
    field :granted_by_id, :binary_id
    field :granted_at, :utc_datetime

    timestamps()
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:student_id, :module, :extra_attempts, :reason, :granted_by_id, :granted_at])
    |> validate_required([:student_id, :module, :extra_attempts])
    |> validate_number(:extra_attempts, greater_than: 0)
    |> put_granted_at()
  end

  defp put_granted_at(changeset) do
    case get_field(changeset, :granted_at) do
      nil -> put_change(changeset, :granted_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end
end
