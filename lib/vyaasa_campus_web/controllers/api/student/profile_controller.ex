defmodule VyaasaCampusWeb.Student.ProfileController do
  @moduledoc """
  Controller for handling student profile completion via secure tokens.

  This controller handles:
  - Profile completion via token verification
  - Token validation and expiration checks
  - Profile submission for admin review
  """

  use VyaasaCampusWeb, :controller
  import VyaasaCampusWeb.Shared.ControllerHelpers
  alias VyaasaCampus.Contexts.Students

  @doc """
  Verifies a profile completion token and returns student info if valid.
  GET /api/student/profile-completion/verify?token=xxx
  """
  def verify_token(conn, %{"token" => token}) do
    # Get tenant schema from request
    tenant_schema = get_tenant_schema_from_request(conn)

    case Students.verify_profile_token(token, tenant_schema) do
      {:ok, student} ->
        # Return minimal student info for profile completion
        student_info = %{
          id: student.id,
          email: student.email,
          first_name: student.first_name,
          last_name: student.last_name,
          registration_id: student.registration_id,
          degree: student.degree,
          specialization: student.specialization,
          year_of_passing: student.year_of_passing,
          cgpa: student.cgpa,
          token_valid: true
        }

        json(conn, %{
          student: student_info,
          message: "Token is valid. You can now complete your profile."
        })

      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired token"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Token has expired. Please contact your administrator for a new link."})

      {:error, :profile_already_submitted} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error:
            "Your profile has already been submitted and is awaiting verification. " <>
              "This link can no longer be used."
        })
    end
  end

  @doc """
  Completes student profile via token and submits for admin review.
  POST /api/student/profile-completion/submit
  """
  def submit_profile(conn, %{"token" => token, "profile" => profile_data}) do
    # Get tenant schema from request
    tenant_schema = get_tenant_schema_from_request(conn)

    case Students.update_student_profile(token, profile_data, tenant_schema) do
      {:ok, updated_student} ->
        json(conn, %{
          message: "Profile completed successfully and submitted for review",
          student: %{
            id: updated_student.id,
            email: updated_student.email,
            first_name: updated_student.first_name,
            last_name: updated_student.last_name,
            status: updated_student.status,
            profile_completed: updated_student.profile_completed,
            profile_submitted_at: format_datetime_ist(updated_student.profile_submitted_at)
          }
        })

      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired token"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Token has expired. Please contact your administrator for a new link."})

      {:error, :profile_already_submitted} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error:
            "Your profile has already been submitted and is awaiting verification. " <>
              "This link can no longer be used."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  @doc """
  Resends profile completion email for a student.
  POST /api/student/profile-completion/resend

  Requires admin authentication.
  """
  def resend_profile_email(conn, %{"student_id" => student_id}) do
    # This should be behind admin authentication
    tenant_schema = get_tenant_schema_from_request(conn)
    tenant_alias = get_tenant_alias_from_request(conn)

    case Students.resend_profile_completion_email(student_id, tenant_alias, tenant_schema) do
      {:ok, student_with_token} ->
        json(conn, %{
          message: "Profile completion email sent successfully",
          student_id: student_id,
          email: student_with_token.email
        })

      {:error, :student_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Student not found"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Student is not in a state that allows profile completion"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  @doc """
  Request profile edit for active student.
  POST /api/student/profile/edit-request

  Requires student authentication.
  Active students can request permission to edit their profile.
  Admin will approve/reject the request, then student can edit via token.
  """
  def request_edit(conn, _params) do
    # Get tenant schema from request
    tenant_schema = get_tenant_schema_from_request(conn)
    tenant_alias = get_tenant_alias_from_request(conn)

    # Get student ID from JWT token
    student_id = get_current_user_id(conn)

    case Students.request_profile_edit(student_id, tenant_alias, tenant_schema) do
      {:ok, updated_student} ->
        json(conn, %{
          message: "Profile edit request submitted successfully. Awaiting admin approval.",
          student: %{
            id: updated_student.id,
            email: updated_student.email,
            first_name: updated_student.first_name,
            last_name: updated_student.last_name,
            status: updated_student.status,
            edit_requested_at: format_datetime_ist(updated_student.edit_requested_at)
          }
        })

      {:error, :student_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Student not found"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Only active students can request profile edits"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  # Private functions - now using shared functions from VyaasaCampusWeb.Shared.ControllerHelpers
end
