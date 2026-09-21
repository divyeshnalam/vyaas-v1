defmodule VyaasaCampus.Schema.Tenants.Subscription do
  @moduledoc """
  A tenant's subscription window (public schema).

  Today this only carries the period that attempt allowances reset on — set by
  the super admin, no billing attached. When real subscriptions land, a plan
  populates `plan_key`/`status` and rolls the period forward; enforcement and
  reset semantics stay as they are.

  A NULL period means "no reset" — attempts are counted over all time.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset

  @statuses ~w(active past_due cancelled)

  @derive {Jason.Encoder,
           only: [:id, :tenant_id, :plan_key, :status, :period_start, :period_end, :metadata]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tenant_subscriptions" do
    field :tenant_id, :binary_id
    field :plan_key, :string, default: "custom"
    field :status, :string, default: "active"
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:tenant_id, :plan_key, :status, :period_start, :period_end, :metadata])
    |> validate_required([:tenant_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_period()
    |> unique_constraint(:tenant_id)
  end

  defp validate_period(changeset) do
    start = get_field(changeset, :period_start)
    finish = get_field(changeset, :period_end)

    if start && finish && DateTime.compare(finish, start) != :gt do
      add_error(changeset, :period_end, "must be after the period start")
    else
      changeset
    end
  end
end
