defmodule VyaasaCampusWeb.TenantAdmin.AssessmentManagement.AssessmentController do
  @moduledoc """
  Controller for managing assessments within tenant contexts.

  This controller handles assessment management operations for tenant users including:
  - Assessment creation and management
  - Assessment publishing and archiving
  - Assessment CRUD operations

  ## Authentication
  Requires platform admin or tenant user authentication.

  ## Authorization
  - Platform admins can manage assessments in any tenant
  - Tenant users can manage assessments in their own tenant only
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers
  alias VyaasaCampus.Contexts.Assessments
  alias VyaasaCampus.Contexts.Tenants

  @doc """
  Creates an assessment in the given tenant /api/tenant/assessments
  """
  def create(conn, %{"assessment" => assessment_params}) do
    # Get tenant alias from header for validation
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    # Validate tenant access
    with {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         assessment_params_with_creator <- add_creator_info(assessment_params, conn),
         [tenant_alias] <- get_req_header(conn, "x-tenant"),
         %{id: tenant_id} <- Tenants.get_tenant_by_alias(tenant_alias),
         params <- Map.put(assessment_params_with_creator, "tenant_id", tenant_id),
         [] <-
           Enum.filter(
             [
               "title",
               "assessment_type",
               "duration_minutes",
               "total_marks",
               "passing_marks",
               "tenant_id"
             ],
             fn f ->
               is_nil(Map.get(params, f)) or Map.get(params, f) == ""
             end
           ),
         {:ok, assessment} <- Assessments.create_assessment(params, schema) do
      conn
      |> put_status(:created)
      |> json(%{assessment: assessment, message: "Assessment created successfully"})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized access"})

      {:error, :tenant_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Tenant not found"})

      {:error, :access_denied} ->
        conn |> put_status(:forbidden) |> json(%{error: "Access denied to this tenant"})

      {:error, :unknown_user_type} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid user type"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: translate_errors(changeset)})

      missing when is_list(missing) and missing != [] ->
        errors = Enum.into(missing, %{}, fn f -> {f, "is required"} end)
        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})

      _ ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid request"})
    end
  end

  @doc """
  Lists all assessments in the given tenant /api/tenant/assessments
  """
  def index(conn, _params) do
    # Get tenant alias from header for validation
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    # Validate tenant access
    case validate_tenant_access(conn, tenant_alias) do
      {:ok, schema} ->
        assessments = Assessments.list_assessments(schema)
        json(conn, %{assessments: assessments})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized access"})

      {:error, :tenant_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this tenant"})

      {:error, :unknown_user_type} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid user type"})
    end
  end

  @doc """
  Shows a specific assessment in the given tenant /api/tenant/assessments/:id
  """
  def show(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, assessment} <- get_assessment_if_exists(id, schema) do
      json(conn, %{assessment: assessment})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized access"})

      {:error, :tenant_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tenant not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this tenant"})

      {:error, :unknown_user_type} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid user type"})

      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

      {:error, :assessment_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Assessment not found"})
    end
  end

  defp get_assessment_if_exists(id, schema) do
    case Assessments.get_assessment!(id, schema) do
      nil -> {:error, :assessment_not_found}
      assessment -> {:ok, assessment}
    end
  end

  @doc """
  Updates an assessment in the given tenant /api/tenant/assessments/:id
  """
  def update(conn, %{"id" => id, "assessment" => assessment_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, assessment} <- get_assessment_by_id(id, schema),
         {:ok, updated_assessment} <- update_assessment_record(assessment, assessment_params, schema) do
      handle_resource_success(conn, updated_assessment, "assessment", "updated")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp update_assessment_record(assessment, assessment_params, schema) do
    Assessments.update_assessment(assessment, assessment_params, schema)
  end

  @doc """
  Deletes an assessment in the given tenant /api/tenant/assessments/:id
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, assessment} <- get_assessment_by_id(id, schema),
         {:ok, _deleted_assessment} <- delete_assessment_record(assessment, schema) do
      handle_success(conn, %{}, "Assessment deleted successfully")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp delete_assessment_record(assessment, schema) do
    Assessments.delete_assessment(assessment, schema)
  end

  @doc """
  Publishes an assessment /api/tenant/assessments/:id/publish
  """
  def publish(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, assessment} <- get_assessment_by_id(id, schema),
         {:ok, published_assessment} <- publish_assessment_record(assessment, schema) do
      handle_resource_success(conn, published_assessment, "assessment", "published")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp publish_assessment_record(assessment, schema) do
    Assessments.publish_assessment(assessment, schema)
  end

  @doc """
  Archives an assessment /api/tenant/assessments/:id/archive
  """
  def archive(conn, %{"id" => id}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, assessment} <- get_assessment_by_id(id, schema),
         {:ok, archived_assessment} <- archive_assessment_record(assessment, schema) do
      handle_resource_success(conn, archived_assessment, "assessment", "archived")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp get_assessment_by_id(id, schema) do
    case Assessments.get_assessment!(id, schema) do
      nil -> {:error, :resource_not_found}
      assessment -> {:ok, assessment}
    end
  end

  defp archive_assessment_record(assessment, schema) do
    Assessments.archive_assessment(assessment, schema)
  end

  # === Private Functions ===

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{" <> to_string(key) <> "}", to_string(value))
      end)
    end)
  end
end
