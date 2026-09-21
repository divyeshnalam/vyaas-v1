defmodule VyaasaCampus.Contexts.SharedProfileLinks do
  @moduledoc """
  Short, stable, public slugs for the student profile share link — replaces
  a `Phoenix.Token.sign/3` payload (195+ characters, made both the "copy
  link" URL and the QR code unreasonably long) with an 8-character opaque
  code backed by `shared_profile_links` (public schema, like `tenants`,
  since the slug alone must resolve the tenant — there's no tenant segment
  in the shared URL).

  One slug per student, reused across every call — `get_or_create_slug/2`
  is idempotent, unlike the old signed-token approach where the "Share"
  button and the QR code each independently minted a different
  forever-valid token for the same student.
  """

  import Ecto.Query, warn: false

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.SharedProfileLink

  @slug_alphabet ~c"23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
  @slug_length 8

  @doc "Returns the student's existing share slug, or mints and persists a new one."
  def get_or_create_slug(student_id, tenant_schema) do
    case Repo.get_by(SharedProfileLink, [student_id: student_id, tenant_schema: tenant_schema],
           prefix: public_schema()
         ) do
      %SharedProfileLink{slug: slug} ->
        slug

      nil ->
        insert_with_fresh_slug(student_id, tenant_schema)
    end
  end

  @doc "Resolves a slug back to `{student_id, tenant_schema}`, or `:error` if unknown."
  def resolve_slug(slug) do
    case Repo.get_by(SharedProfileLink, [slug: slug], prefix: public_schema()) do
      %SharedProfileLink{student_id: student_id, tenant_schema: tenant_schema} ->
        {:ok, %{student_id: student_id, tenant_schema: tenant_schema}}

      nil ->
        :error
    end
  end

  # Retries on the rare slug collision (unique_constraint on :slug) rather
  # than pre-checking existence — the constraint is the actual guarantee.
  defp insert_with_fresh_slug(student_id, tenant_schema, attempts_left \\ 5)

  defp insert_with_fresh_slug(_student_id, _tenant_schema, 0) do
    raise "SharedProfileLinks: could not generate a unique slug after 5 attempts"
  end

  defp insert_with_fresh_slug(student_id, tenant_schema, attempts_left) do
    attrs = %{slug: generate_slug(), student_id: student_id, tenant_schema: tenant_schema}

    %SharedProfileLink{}
    |> SharedProfileLink.changeset(attrs)
    |> Repo.insert(prefix: public_schema())
    |> case do
      {:ok, %SharedProfileLink{slug: slug}} ->
        slug

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :slug) do
          insert_with_fresh_slug(student_id, tenant_schema, attempts_left - 1)
        else
          # A (tenant_schema, student_id) unique_constraint hit means a
          # concurrent caller just created one — read it back.
          get_or_create_slug(student_id, tenant_schema)
        end
    end
  end

  defp generate_slug do
    1..@slug_length
    |> Enum.map(fn _ -> Enum.random(@slug_alphabet) end)
    |> List.to_string()
  end

  defp public_schema, do: VyaasaCampus.Types.public_schema()
end
