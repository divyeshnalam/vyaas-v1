defmodule VyaasaCampus.Repo.Migrations.CreateSharedProfileLinks do
  use Ecto.Migration

  @moduledoc """
  Replaces the shared-profile link's `Phoenix.Token.sign/3` payload (a
  195+ character opaque blob, making the shared URL/QR code unreasonably
  long) with a short, DB-backed slug. Lives in the public schema (like
  `tenants`) since the slug alone must resolve both the tenant and the
  student — there's no tenant in the shared URL itself, deliberately.
  """

  def change do
    create table(:shared_profile_links, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :slug, :string, null: false
      add :student_id, :binary_id, null: false
      add :tenant_schema, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shared_profile_links, [:slug])
    create unique_index(:shared_profile_links, [:tenant_schema, :student_id])
  end
end
