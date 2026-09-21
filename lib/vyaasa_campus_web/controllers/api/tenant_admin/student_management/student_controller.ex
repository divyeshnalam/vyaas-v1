defmodule VyaasaCampusWeb.TenantAdmin.StudentManagement.StudentController do
  @moduledoc """
  Controller for managing students within tenant contexts.

  This controller handles student operations including:
  - Student creation and registration
  - Student listing and retrieval
  - Bulk student creation

  only tenant users can create students in their own tenant only
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers

  require Logger

  import VyaasaCampusWeb.Shared.ErrorHandler,
    except: [format_changeset_errors: 1, validate_uuid: 1, handle_validation_error: 2]

  alias VyaasaCampus.Contexts.StudentAts
  alias VyaasaCampus.Contexts.Students

  # File types a browser will display on its own. Everything else, asked for
  # inline, gets our own preview page instead of a failed render.
  @browser_renderable ~w(.pdf .txt .png .jpg .jpeg .gif .webp)

  @doc """
  Lists all students in the given tenant /api/tenant/students
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
        students = Students.list_students(schema)
        json(conn, students)

      {:error, :unauthorized} ->
        handle_auth_error(
          conn,
          :unauthorized,
          "Authentication is required to access student resources"
        )

      {:error, :tenant_not_found} ->
        handle_tenant_error(
          conn,
          :tenant_not_found,
          tenant_alias,
          "The specified tenant was not found"
        )

      {:error, :access_denied} ->
        handle_authorization_error(
          conn,
          :tenant_access_denied,
          "You do not have access to this tenant's student data"
        )

      {:error, :unknown_user_type} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Unknown user type - access denied to student resources"
        )
    end
  end

  @doc """
  Creates a student using the multi-step onboarding flow (Step 1).
  POST /api/tenant/students

  ## Multi-Step Student Onboarding Process:
  1. Admin creates student with basic info (this endpoint)
  2. Student receives profile completion email with secure token
  3. Student completes profile via ProfileCompletionController
  4. Admin reviews and approves/rejects via approve/3 or reject/3
  5. Approved students receive login credentials

  Only tenant users can create students in their own tenant.
  """
  def create(conn, %{"student" => student_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, tenant_id} <- get_tenant_id_from_alias(tenant_alias),
         {:ok, student_params_with_creator} <- prepare_student_params(student_params, conn, tenant_id),
         {:ok, student} <- create_student_record(student_params_with_creator, tenant_alias, schema) do
      safe_student = student_to_safe_map(student, schema)

      json(conn, %{
        student: safe_student,
        message: "Student created successfully. Profile completion email sent.",
        status: "pending_profile_completion",
        next_step: "Student should check email and complete profile"
      })
    else
      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

      {:error, :unauthorized} ->
        handle_auth_error(conn, :unauthorized, "Authentication is required to create students")

      {:error, :tenant_not_found} ->
        handle_tenant_error(
          conn,
          :tenant_not_found,
          nil,
          "The specified temnant was not found"
        )

      {:error, :access_denied} ->
        handle_authorization_error(
          conn,
          :tenant_access_denied,
          "You do not have access to create students in this tenant"
        )

      {:error, :unknown_user_type} ->
        handle_authorization_error(
          conn,
          :forbidden,
          "Unknown user type - access denied to create students"
        )

      {:error, changeset} ->
        handle_validation_error(
          conn,
          changeset,
          "Student creation failed due to validation errors"
        )
    end
  end

  @doc """
  Bulk creates students using the multi-step onboarding flow with concurrent processing.
  POST /api/tenant/students/bulk

  ## Request Body:
  {
    "students": [
      {
        "email": "student1@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "phone": "+1234567890",
        "registration_id": "REG001",
        "degree": "Computer Science",
        "specialization": "Software Engineering",
        "year_of_passing": 2024,
        "cgpa": 3.8
      }
    ],
    "options": {
      "max_concurrency": 5,
      "timeout": 30000
    }
  }

  ## Response:
  {
    "message": "Bulk creation completed",
    "summary": {
      "total": 10,
      "successful": 8,
      "failed": 2,
      "errors": [...],
      "duration_ms": 150
    },
    "students": [...]
  }
  """
  def bulk_create(conn, %{"students" => students_data} = params) do
    options = Map.get(params, "options", %{})

    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, tenant_id} <- get_tenant_id_from_alias(tenant_alias),
         {:ok, prepared_students} <- prepare_bulk_student_params(students_data, conn, tenant_id),
         {:ok, result} <- process_bulk_creation(prepared_students, tenant_alias, schema, options) do
      json(conn, format_bulk_creation_response(result, schema))
    else
      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

      {:error, :unauthorized} ->
        handle_auth_error(
          conn,
          :unauthorized,
          "Authentication is required to create students"
        )

      {:error, :tenant_not_found} ->
        handle_tenant_error(
          conn,
          :tenant_not_found,
          nil,
          "The specified tenant was not found"
        )

      {:error, :access_denied} ->
        handle_authorization_error(
          conn,
          :tenant_access_denied,
          "You do not have access to create students in this tenant"
        )

      {:error, :too_many_students} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Too many students for bulk creation",
          max_allowed: 1000,
          requested: length(students_data)
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Bulk creation failed", reason: reason})
    end
  end

  def bulk_create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Students data is required"})
  end

  defp prepare_student_params(student_params, conn, tenant_id) do
    student_params_with_creator = add_creator_info(student_params, conn)
    student_params_with_tenant = Map.put(student_params_with_creator, "tenant_id", tenant_id)
    {:ok, student_params_with_tenant}
  end

  defp create_student_record(student_params_with_tenant, tenant_alias, schema) do
    Students.create_student(student_params_with_tenant, tenant_alias, schema)
  end

  @doc """
  Updates a student in the given tenant /api/tenant/students/:id
  only tenant users can update students in their own tenant only
  """
  def update(conn, %{"id" => id, "student" => student_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, student} <- update_student_record(id, student_params, conn, schema) do
      safe_student = student_to_safe_map(student, schema)
      handle_resource_success(conn, safe_student, "student", "updated")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp update_student_record(id, student_params, conn, schema) do
    student_params_with_updater = add_updater_info(student_params, conn)
    Students.update_student(id, student_params_with_updater, schema)
  end

  @doc """
  Lists students with pending approval status /api/tenant/students/pending
  only tenant users can view students in their own tenant only
  """
  def list_pending(conn, _params) do
    # Get tenant alias from header for validation
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    # Validate tenant access
    case validate_tenant_access(conn, tenant_alias) do
      {:ok, schema} ->
        students = Students.list_pending_students(schema)

        # Convert to safe response maps
        safe_students = Enum.map(students, &student_to_safe_map(&1, schema))

        json(conn, %{
          students: safe_students,
          count: length(safe_students)
        })

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
  Approves a student profile /api/tenant/students/:id/approve
  only tenant users can approve students in their own tenant only
  """
  def approve(conn, %{"id" => id, "approval" => approval_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, admin_user_id} <- get_admin_user_id(conn),
         {:ok, student} <- approve_student_record(id, admin_user_id, approval_params, tenant_alias, schema) do
      safe_student = student_to_safe_map(student, schema)
      handle_resource_success(conn, safe_student, "student", "approved")
    else
      error -> handle_common_errors(conn, error)
    end
  end

  defp approve_student_record(id, admin_user_id, approval_params, tenant_alias, schema) do
    admin_notes = Map.get(approval_params, "admin_notes")
    Students.approve_student(id, admin_user_id, admin_notes, tenant_alias, schema)
  end

  @doc """
  Rejects a student profile /api/tenant/students/:id/reject
  only tenant users can reject students in their own tenant only
  """
  def reject(conn, %{"id" => id, "rejection" => rejection_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, admin_user_id} <- get_admin_user_id(conn),
         {:ok, admin_notes, edit_request_notes} <- validate_student_rejection_params(rejection_params),
         {:ok, student} <-
           reject_student_profile(id, admin_user_id, admin_notes, edit_request_notes, tenant_alias, schema) do
      safe_student = student_to_safe_map(student, schema)

      json(conn, %{
        student: safe_student,
        message: "Student profile rejected. Edit request sent with feedback."
      })
    else
      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

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

      {:error, :missing_admin_notes} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{admin_notes: "is required for rejection"}})

      {:error, :missing_edit_request_notes} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{edit_request_notes: "is required for rejection"}})

      {:error, :student_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Student not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp validate_student_rejection_params(rejection_params) do
    admin_notes = Map.get(rejection_params, "admin_notes")
    edit_request_notes = Map.get(rejection_params, "edit_request_notes")

    cond do
      is_nil(admin_notes) or admin_notes == "" ->
        {:error, :missing_admin_notes}

      is_nil(edit_request_notes) or edit_request_notes == "" ->
        {:error, :missing_edit_request_notes}

      true ->
        {:ok, admin_notes, edit_request_notes}
    end
  end

  defp reject_student_profile(id, admin_user_id, admin_notes, edit_request_notes, tenant_alias, schema) do
    Students.reject_student(id, admin_user_id, admin_notes, edit_request_notes, tenant_alias, schema)
  end

  @doc """
  Lists students with pending edit requests /api/tenant/students/edit-requests
  only tenant users can view edit requests in their own tenant only
  """
  def list_edit_requests(conn, _params) do
    # Get tenant alias from header for validation
    tenant_alias =
      case get_req_header(conn, "x-tenant") do
        [alias] -> alias
        _ -> nil
      end

    # Validate tenant access
    case validate_tenant_access(conn, tenant_alias) do
      {:ok, schema} ->
        students = Students.list_pending_edit_requests(schema)

        # Convert to safe response maps
        safe_students = Enum.map(students, &student_to_safe_map(&1, schema))

        json(conn, %{
          students: safe_students,
          count: length(safe_students)
        })

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
  Approves a profile edit request /api/tenant/students/:id/approve-edit
  only tenant users can approve edit requests in their own tenant only
  """
  def approve_edit(conn, %{"id" => id, "approval" => approval_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, admin_user_id} <- get_admin_user_id(conn),
         {:ok, student} <- approve_student_profile_edit(id, admin_user_id, approval_params, tenant_alias, schema) do
      safe_student = student_to_safe_map(student, schema)

      json(conn, %{
        student: safe_student,
        message: "Profile edit request approved successfully."
      })
    else
      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

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

      {:error, :student_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Student not found"})

      {:error, :no_edit_request} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No pending edit request found for this student"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp approve_student_profile_edit(id, admin_user_id, approval_params, tenant_alias, schema) do
    admin_notes = Map.get(approval_params, "admin_notes")
    Students.approve_profile_edit(id, admin_user_id, admin_notes, tenant_alias, schema)
  end

  @doc """
  Rejects a profile edit request /api/tenant/students/:id/reject-edit
  only tenant users can reject edit requests in their own tenant only
  """
  def reject_edit(conn, %{"id" => id, "rejection" => rejection_params}) do
    with {:ok, tenant_alias} <- get_tenant_alias_from_header(conn),
         {:ok, schema} <- validate_tenant_access(conn, tenant_alias),
         {:ok, admin_user_id} <- get_admin_user_id(conn),
         {:ok, admin_notes, rejection_notes} <- validate_rejection_params(rejection_params),
         {:ok, student} <-
           reject_student_profile_edit(id, admin_user_id, admin_notes, rejection_notes, tenant_alias, schema) do
      safe_student = student_to_safe_map(student, schema)

      json(conn, %{
        student: safe_student,
        message: "Profile edit request rejected. Feedback sent to student."
      })
    else
      {:error, :missing_tenant_header} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Tenant header is required"})

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

      {:error, :missing_admin_notes} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{admin_notes: "is required for rejection"}})

      {:error, :missing_rejection_notes} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{rejection_notes: "is required for rejection"}})

      {:error, :student_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Student not found"})

      {:error, :no_edit_request} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No pending edit request found for this student"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp get_admin_user_id(conn) do
    admin_user_id = get_current_user_id(conn)
    {:ok, admin_user_id}
  end

  defp validate_rejection_params(rejection_params) do
    admin_notes = Map.get(rejection_params, "admin_notes")
    rejection_notes = Map.get(rejection_params, "rejection_notes")

    cond do
      is_nil(admin_notes) or admin_notes == "" ->
        {:error, :missing_admin_notes}

      is_nil(rejection_notes) or rejection_notes == "" ->
        {:error, :missing_rejection_notes}

      true ->
        {:ok, admin_notes, rejection_notes}
    end
  end

  defp reject_student_profile_edit(id, admin_user_id, admin_notes, rejection_notes, tenant_alias, schema) do
    Students.reject_profile_edit(id, admin_user_id, admin_notes, rejection_notes, tenant_alias, schema)
  end

  @doc """
  Downloads a student's resume file /api/tenant/students/:student_id/resume/*filename
  only tenant users can download resumes from their own tenant only
  """
  def download_resume(conn, %{"student_id" => student_id, "filename" => filename} = params) do
    tenant_alias = conn.assigns.tenant_alias
    filename_string = normalize_filename(filename)

    case validate_tenant_access(conn, tenant_alias) do
      {:ok, _schema} ->
        handle_resume_download(conn, student_id, filename_string, params["mode"])

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
  Downloads a student's college ID card /api/tenant/students/:student_id/document/id_card
  """
  def download_id_card(conn, %{"student_id" => student_id} = params) do
    tenant_alias = conn.assigns.tenant_alias

    case validate_tenant_access(conn, tenant_alias) do
      {:ok, schema} -> handle_document_download(conn, student_id, :college_id_card_url, schema, params["mode"])
      err -> handle_document_access_error(conn, err)
    end
  end

  @doc """
  Downloads a student's profile photo /api/tenant/students/:student_id/document/profile_photo
  """
  def download_profile_photo(conn, %{"student_id" => student_id} = params) do
    tenant_alias = conn.assigns.tenant_alias

    case validate_tenant_access(conn, tenant_alias) do
      {:ok, schema} -> handle_document_download(conn, student_id, :profile_picture_url, schema, params["mode"])
      err -> handle_document_access_error(conn, err)
    end
  end

  defp upload_base_path do
    Application.get_env(:vyaasa_campus, :upload_base_path, "priv/uploads")
  end

  # === Private Functions ===

  defp student_to_safe_map(student, tenant_schema) do
    # Get ATS fields from ATS table
    ats_fields = StudentAts.get_student_ats_fields(student.id, tenant_schema)

    %{
      id: student.id,
      email: student.email,
      first_name: student.first_name,
      middle_name: student.middle_name,
      last_name: student.last_name,
      phone: student.phone,
      registration_id: student.registration_id,
      degree: student.degree,
      specialization: student.specialization,
      year_of_passing: student.year_of_passing,
      cgpa: student.cgpa,
      tenure: student.tenure,
      current_academic_year: student.current_academic_year,
      location_id: student.location_id,
      status: student.status,
      profile_completed: student.profile_completed,
      profile_submitted_at: student.profile_submitted_at,
      profile_approved_at: student.profile_approved_at,
      profile_rejected_at: student.profile_rejected_at,
      profile_reviewed_at: student.profile_reviewed_at,
      edit_requested_at: student.edit_requested_at,
      approved_by_id: student.approved_by_id,
      admin_notes: student.admin_notes,
      edit_request_notes: student.edit_request_notes,
      email_verified_at: student.email_verified_at,
      last_login_at: student.last_login_at,
      metadata: student.metadata,
      tenant_id: student.tenant_id,
      created_by_id: student.created_by_id,
      created_by_type: student.created_by_type,
      inserted_at: student.inserted_at,
      updated_at: student.updated_at,
      # ATS fields (moved from student table)
      preferred_role: ats_fields.preferred_role,
      resume_url: ats_fields.resume_url,
      college_id_card_url: ats_fields.college_id_card_url,
      profile_picture_url: ats_fields.profile_picture_url
    }
  end

  # === Bulk Creation Helper Functions ===

  defp prepare_bulk_student_params(students_data, conn, tenant_id) do
    # Validate batch size
    if length(students_data) > 1000 do
      {:error, :too_many_students}
    else
      prepared_students =
        Enum.map(students_data, fn student_params ->
          add_creator_info(student_params, conn)
          |> Map.put("tenant_id", tenant_id)
        end)

      {:ok, prepared_students}
    end
  end

  defp process_bulk_creation(students_data, tenant_alias, schema, options) do
    process_concurrent_bulk_creation(students_data, tenant_alias, schema, options)
  end

  defp process_concurrent_bulk_creation(students_data, tenant_alias, schema, options) do
    opts = %{
      max_concurrency: Map.get(options, "max_concurrency", System.schedulers_online()),
      timeout: Map.get(options, "timeout", :infinity)
    }

    case Students.bulk_create_students_concurrent(students_data, tenant_alias, schema, opts) do
      {:ok, %{successes: students, errors: errors, total: total, duration_ms: duration}} ->
        {:ok,
         %{
           students: students,
           summary: %{
             total: total,
             successful: length(students),
             failed: length(errors),
             errors: format_bulk_errors(errors),
             duration_ms: duration
           }
         }}
    end
  end

  defp format_bulk_creation_response(result, tenant_schema) do
    safe_students = Enum.map(result.students, &student_to_safe_map(&1, tenant_schema))

    %{
      message: "Bulk creation completed",
      summary: result.summary,
      students: safe_students
    }
  end

  defp format_bulk_errors(errors) do
    Enum.map(errors, fn error ->
      case error do
        %{student_data: data, error: error_map} when is_map(error_map) ->
          # Handle formatted changeset errors (map of field => messages)
          %{
            email: Map.get(data, "email", "unknown"),
            error: "Validation failed",
            details: error_map
          }

        %{student_data: data, error: changeset} when is_struct(changeset) and changeset.__struct__ == Ecto.Changeset ->
          # Handle actual changeset struct
          %{
            email: Map.get(data, "email", "unknown"),
            error: "Validation failed",
            details: translate_errors(changeset)
          }

        %{student_data: data, error: reason} when is_binary(reason) ->
          %{
            email: Map.get(data, "email", "unknown"),
            error: reason
          }

        _ ->
          %{error: "Unknown error occurred"}
      end
    end)
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{" <> to_string(key) <> "}", to_string(value))
      end)
    end)
  end

  # Helper functions for download_resume

  defp normalize_filename(filename) do
    case filename do
      [single_filename] -> single_filename
      filename_list when is_list(filename_list) -> Path.join(filename_list)
      filename_string when is_binary(filename_string) -> filename_string
    end
  end

  defp handle_resume_download(conn, student_id, filename_string, mode) do
    tenant = conn.assigns.tenant
    relative_path = Path.join([tenant.id, "students", student_id, filename_string])
    full_path = Path.join([upload_base_path(), relative_path])

    if File.exists?(full_path) do
      send_resume_file(conn, full_path, filename_string, mode)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Resume file not found", path: full_path})
    end
  end

  # mode "view" (or an iframe request) opens the file inline in the browser;
  # everything else (including no mode, the download-icon link) forces the
  # browser's save-file prompt.
  defp send_resume_file(conn, full_path, filename_string, mode) do
    sec_fetch_dest = get_req_header(conn, "sec-fetch-dest")
    is_iframe_request = sec_fetch_dest == ["iframe"]
    view? = mode == "view" or is_iframe_request
    ext = filename_string |> Path.extname() |> String.downcase()

    # A browser can only render some of what students upload. Asking it to
    # display a DOCX inline gets a blank tab or a broken PDF viewer (this used
    # to send EVERY resume as application/pdf, whatever it actually was), so
    # those go to a preview page we render ourselves.
    if view? and ext not in @browser_renderable do
      render_document_preview(conn, full_path, filename_string, ext)
    else
      disposition = if view?, do: "inline", else: "attachment"

      conn
      |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename_string}\"")
      |> put_resp_header("content-type", mime_type(filename_string))
      |> send_file(200, full_path)
    end
  end

  # DOCX is read into text and shown; anything else we can't render gets a page
  # explaining why, so the admin sees a straight answer instead of a browser
  # error. Both offer the original file for download.
  defp render_document_preview(conn, full_path, filename, ".docx") do
    case VyaasaCampus.AI.Resume.Extractor.docx_paragraphs_from_file(full_path) do
      {:ok, [_ | _] = paragraphs} ->
        conn
        |> put_document_preview_view()
        |> render(:docx_preview,
          filename: filename,
          paragraphs: paragraphs,
          download_url: original_file_url(conn)
        )

      # A valid DOCX with no text in it — usually a resume built as one big
      # image, or the content living in a text box we don't walk.
      {:ok, []} ->
        preview_unavailable(conn, filename,
          title: "Nothing to show from this document",
          message:
            "The file opened, but no readable text came out of it. That usually means the resume is an image or uses a layout we can't read.",
          hint: "Download it to view the document as the student built it."
        )

      {:error, reason} ->
        # The reason carries an Erlang stacktrace from :zip — useful in the log,
        # not on an admin's screen.
        Logger.warning("Resume preview failed | file=#{filename} | #{inspect(reason)}")

        preview_unavailable(conn, filename,
          title: "This document couldn't be opened",
          message:
            "The file is named .docx but doesn't read as a valid Word document. It may be corrupted, or saved in a different format and renamed.",
          hint: "Download it to check, or ask the student to re-upload their resume as a PDF."
        )
    end
  end

  # .doc is the pre-2007 binary Word format — not a zip, nothing to unpack. It
  # is accepted at upload, so an admin will meet it eventually and deserves a
  # real explanation rather than a broken viewer.
  defp render_document_preview(conn, _full_path, filename, ".doc") do
    preview_unavailable(conn, filename,
      title: "Legacy Word files can't be previewed",
      message:
        "This is the old .doc format, which can't be read in the browser. Only .docx and PDF resumes can be previewed here.",
      hint: "Download the file to open it in Word, or ask the student to re-upload their resume as a PDF."
    )
  end

  defp render_document_preview(conn, _full_path, filename, ext) do
    preview_unavailable(conn, filename,
      title: "This file type can't be previewed",
      message: "#{if ext == "", do: "This file", else: ext} isn't a format the browser can display.",
      hint: "Download the file to open it, or ask the student to re-upload their resume as a PDF."
    )
  end

  defp preview_unavailable(conn, filename, opts) do
    conn
    |> put_status(:unsupported_media_type)
    |> put_document_preview_view()
    |> render(:unavailable,
      filename: filename,
      title: Keyword.fetch!(opts, :title),
      message: Keyword.fetch!(opts, :message),
      hint: Keyword.get(opts, :hint),
      detail: Keyword.get(opts, :detail),
      download_url: original_file_url(conn)
    )
  end

  # These pages come off a JSON pipeline and carry their own markup, so the
  # format has to be forced and the app layout kept out.
  defp put_document_preview_view(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> put_view(html: VyaasaCampusWeb.DocumentPreviewHTML)
    |> put_root_layout(html: false)
    |> put_layout(html: false)
    |> Phoenix.Controller.put_format(:html)
  end

  # Same URL minus `mode=view`, i.e. the download branch of this action. Keeps
  # `tenant=` and anything else the caller sent.
  defp original_file_url(conn) do
    query = conn.query_params |> Map.drop(["mode"]) |> URI.encode_query()

    if query == "", do: conn.request_path, else: "#{conn.request_path}?#{query}"
  end

  # mode "download" forces the browser's save-file prompt; anything else
  # (including no mode) opens the file inline in a new tab.
  defp handle_document_download(conn, student_id, field, schema, mode) do
    case StudentAts.get_by_student_id(student_id, schema) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No documents found for this student"})

      ats_phase ->
        relative_url = Map.get(ats_phase, field)

        if relative_url && String.trim(relative_url) != "" do
          full_path = Path.join(upload_base_path(), relative_url)

          if File.exists?(full_path) do
            filename = Path.basename(full_path)
            disposition = if mode == "download", do: "attachment", else: "inline"

            conn
            |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename}\"")
            |> put_resp_header("content-type", mime_type(filename))
            |> send_file(200, full_path)
          else
            conn
            |> put_status(:not_found)
            |> json(%{error: "File not found on disk"})
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Document not uploaded"})
        end
    end
  end

  defp mime_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg"  -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png"  -> "image/png"
      ".gif"  -> "image/gif"
      ".webp" -> "image/webp"
      ".pdf"  -> "application/pdf"
      ".txt"  -> "text/plain"
      ".doc"  -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      _       -> "application/octet-stream"
    end
  end

  defp handle_document_access_error(conn, {:error, :unauthorized}) do
    conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized access"})
  end

  defp handle_document_access_error(conn, {:error, :tenant_not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "Tenant not found"})
  end

  defp handle_document_access_error(conn, {:error, _}) do
    conn |> put_status(:forbidden) |> json(%{error: "Access denied"})
  end
end
