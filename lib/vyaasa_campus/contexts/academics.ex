defmodule VyaasaCampus.Contexts.Academics do
  @moduledoc """
  Context for managing degrees, specializations, and tenant academic selections.
  All tables are in the public schema.
  """

  import Ecto.Query, warn: false
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Academics.{Degree, Specialization, TenantDegree, TenantSpecialization}

  # ============================================================================
  # DEGREES (Super Admin)
  # ============================================================================

  def list_degrees do
    Degree
    |> order_by(:name)
    |> Repo.all(prefix: "public")
    |> Repo.preload(:specializations, prefix: "public")
  end

  def list_active_degrees do
    from(d in Degree, where: d.is_active == true, order_by: d.name)
    |> Repo.all(prefix: "public")
  end

  def get_degree!(id), do: Repo.get!(Degree, id, prefix: "public")

  def create_degree(attrs) do
    %Degree{}
    |> Degree.changeset(attrs)
    |> Repo.insert(prefix: "public")
  end

  def update_degree(%Degree{} = degree, attrs) do
    degree
    |> Degree.changeset(attrs)
    |> Repo.update(prefix: "public")
  end

  def delete_degree(%Degree{} = degree) do
    Repo.delete(degree, prefix: "public")
  end

  # ============================================================================
  # SPECIALIZATIONS (Super Admin)
  # ============================================================================

  def list_specializations(degree_id) do
    from(s in Specialization, where: s.degree_id == ^degree_id, order_by: s.name)
    |> Repo.all(prefix: "public")
  end

  def list_active_specializations(degree_id) do
    from(s in Specialization,
      where: s.degree_id == ^degree_id and s.is_active == true,
      order_by: s.name
    )
    |> Repo.all(prefix: "public")
  end

  def get_specialization!(id), do: Repo.get!(Specialization, id, prefix: "public")

  def create_specialization(attrs) do
    %Specialization{}
    |> Specialization.changeset(attrs)
    |> Repo.insert(prefix: "public")
  end

  def update_specialization(%Specialization{} = spec, attrs) do
    spec
    |> Specialization.changeset(attrs)
    |> Repo.update(prefix: "public")
  end

  def delete_specialization(%Specialization{} = spec) do
    Repo.delete(spec, prefix: "public")
  end

  # ============================================================================
  # TENANT DEGREE/SPECIALIZATION SELECTIONS (Tenant Admin)
  # ============================================================================

  def list_tenant_degree_ids(tenant_id) do
    from(td in TenantDegree, where: td.tenant_id == ^tenant_id, select: td.degree_id)
    |> Repo.all(prefix: "public")
  end

  def list_tenant_specialization_ids(tenant_id) do
    from(ts in TenantSpecialization, where: ts.tenant_id == ^tenant_id, select: ts.specialization_id)
    |> Repo.all(prefix: "public")
  end

  def list_tenant_degrees_with_specializations(tenant_id) do
    degree_ids = list_tenant_degree_ids(tenant_id)
    spec_ids = list_tenant_specialization_ids(tenant_id)

    degrees =
      from(d in Degree, where: d.id in ^degree_ids, order_by: d.name)
      |> Repo.all(prefix: "public")

    specializations =
      from(s in Specialization, where: s.id in ^spec_ids, order_by: s.name)
      |> Repo.all(prefix: "public")

    {degrees, specializations}
  end

  @doc """
  Returns degrees and their specializations selected by a tenant,
  formatted as options for student creation forms.
  """
  def get_tenant_degree_options(tenant_id) do
    degree_ids = list_tenant_degree_ids(tenant_id)
    spec_ids = list_tenant_specialization_ids(tenant_id)

    degrees =
      from(d in Degree,
        where: d.id in ^degree_ids and d.is_active == true,
        order_by: d.name,
        select: {d.name, d.name}
      )
      |> Repo.all(prefix: "public")

    specializations =
      from(s in Specialization,
        where: s.id in ^spec_ids and s.is_active == true,
        order_by: s.name,
        select: {s.name, s.name}
      )
      |> Repo.all(prefix: "public")

    {[{"Select degree", ""} | degrees], [{"Select specialization", ""} | Enum.uniq(specializations)]}
  end

  @doc """
  Returns the tenant's specializations grouped by their degree's name, so
  student-creation forms can filter the specialization dropdown down to
  only those belonging to the selected department.
  """
  def get_tenant_specializations_by_degree(tenant_id) do
    spec_ids = list_tenant_specialization_ids(tenant_id)

    from(s in Specialization,
      join: d in Degree, on: d.id == s.degree_id,
      where: s.id in ^spec_ids and s.is_active == true and d.is_active == true,
      order_by: s.name,
      select: {d.name, s.name}
    )
    |> Repo.all(prefix: "public")
    |> Enum.uniq()
    |> Enum.group_by(fn {degree_name, _spec_name} -> degree_name end, fn {_degree_name, spec_name} ->
      {spec_name, spec_name}
    end)
  end

  @doc """
  Find degree_id and specialization_id by their name strings.
  Used when creating/updating students to populate FK fields from form text values.
  """
  def resolve_degree_and_specialization_ids(degree_name, specialization_name) do
    degree_id =
      case Repo.one(
        from(d in Degree, where: d.is_active == true and d.name == ^degree_name, select: d.id, limit: 1),
        prefix: "public"
      ) do
        nil ->
          # Try matching by code
          Repo.one(
            from(d in Degree, where: d.is_active == true and d.code == ^degree_name, select: d.id, limit: 1),
            prefix: "public"
          )
        id -> id
      end

    specialization_id =
      case Repo.one(
        from(s in Specialization, where: s.is_active == true and s.name == ^specialization_name, select: s.id, limit: 1),
        prefix: "public"
      ) do
        nil ->
          Repo.one(
            from(s in Specialization, where: s.is_active == true and s.code == ^specialization_name, select: s.id, limit: 1),
            prefix: "public"
          )
        id -> id
      end

    {degree_id, specialization_id}
  end

  def toggle_tenant_degree(tenant_id, degree_id) do
    case Repo.get_by(TenantDegree, [tenant_id: tenant_id, degree_id: degree_id], prefix: "public") do
      nil ->
        %TenantDegree{}
        |> TenantDegree.changeset(%{tenant_id: tenant_id, degree_id: degree_id})
        |> Repo.insert(prefix: "public")

      existing ->
        # Also remove all specializations for this degree
        spec_ids =
          from(s in Specialization, where: s.degree_id == ^degree_id, select: s.id)
          |> Repo.all(prefix: "public")

        from(ts in TenantSpecialization,
          where: ts.tenant_id == ^tenant_id and ts.specialization_id in ^spec_ids
        )
        |> Repo.delete_all(prefix: "public")

        Repo.delete(existing, prefix: "public")
    end
  end

  def toggle_tenant_specialization(tenant_id, specialization_id) do
    case Repo.get_by(TenantSpecialization, [tenant_id: tenant_id, specialization_id: specialization_id], prefix: "public") do
      nil ->
        %TenantSpecialization{}
        |> TenantSpecialization.changeset(%{tenant_id: tenant_id, specialization_id: specialization_id})
        |> Repo.insert(prefix: "public")

      existing ->
        Repo.delete(existing, prefix: "public")
    end
  end
end
