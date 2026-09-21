defmodule VyaasaCampusWeb.Shared.ErrorHandler do
  @moduledoc """
  Centralized error handling for consistent error responses across controllers.

  This module provides standardized error handling functions that ensure:
  - Consistent error message formats
  - Appropriate HTTP status codes
  - Proper error categorization
  - Detailed error information when appropriate
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc """
  Handles authentication errors with consistent messaging.
  """
  def handle_auth_error(conn, error_type, details \\ nil) do
    error_config = get_auth_error_config(error_type, details)

    conn
    |> put_status(:unauthorized)
    |> json(error_config)
  end

  defp get_auth_error_config(error_type, details) do
    config = get_auth_error_mapping(error_type)

    %{
      error: config.error,
      message: details || config.default_message,
      code: config.code
    }
  end

  defp get_auth_error_mapping(error_type) do
    case error_type do
      :unauthorized ->
        %{
          error: "Authentication Required",
          default_message: "Please provide valid authentication credentials",
          code: "AUTH_REQUIRED"
        }

      :invalid_credentials ->
        %{
          error: "Invalid Credentials",
          default_message: "The provided email or password is incorrect",
          code: "INVALID_CREDENTIALS"
        }

      :token_expired ->
        %{
          error: "Token Expired",
          default_message: "Your authentication token has expired. Please log in again",
          code: "TOKEN_EXPIRED"
        }

      :invalid_token ->
        %{
          error: "Invalid Token",
          default_message: "The provided authentication token is invalid",
          code: "INVALID_TOKEN"
        }

      :refresh_token_invalid ->
        %{
          error: "Invalid Refresh Token",
          default_message: "The refresh token is invalid or has expired",
          code: "INVALID_REFRESH_TOKEN"
        }
    end
  end

  @doc """
  Handles authorization errors with consistent messaging.
  """
  def handle_authorization_error(conn, error_type, details \\ nil) do
    case error_type do
      :forbidden ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Access Denied",
          message: details || "You do not have permission to access this resource",
          code: "ACCESS_DENIED"
        })

      :admin_required ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Admin Access Required",
          message: details || "This operation requires administrator privileges",
          code: "ADMIN_REQUIRED"
        })

      :tenant_access_denied ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Tenant Access Denied",
          message: details || "You do not have access to this tenant",
          code: "TENANT_ACCESS_DENIED"
        })

      :student_access_required ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Student Access Required",
          message: details || "This resource is only accessible to students",
          code: "STUDENT_ACCESS_REQUIRED"
        })
    end
  end

  @doc """
  Handles resource not found errors.
  """
  def handle_not_found_error(conn, resource_type, resource_id, details \\ nil) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "#{resource_type} Not Found",
      message: details || "#{resource_type} with ID '#{resource_id}' was not found",
      code: "#{String.upcase(resource_type)}_NOT_FOUND",
      resource_type: resource_type,
      resource_id: resource_id
    })
  end

  @doc """
  Handles validation errors from Ecto changesets.
  """
  def handle_validation_error(conn, changeset, custom_message \\ nil) do
    errors = format_changeset_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "Validation Error",
      message: custom_message || "The provided data contains validation errors",
      code: "VALIDATION_ERROR",
      details: errors
    })
  end

  @doc """
  Handles parameter validation errors.
  """
  def handle_parameter_error(conn, missing_params, custom_message \\ nil) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "Missing Required Parameters",
      message:
        custom_message ||
          "The following required parameters are missing: #{Enum.join(missing_params, ", ")}",
      code: "MISSING_PARAMETERS",
      missing_parameters: missing_params
    })
  end

  @doc """
  Handles tenant-related errors.
  """
  def handle_tenant_error(conn, error_type, tenant_alias, details \\ nil) do
    case error_type do
      :tenant_not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "Tenant Not Found",
          message: details || "Tenant with alias '#{tenant_alias}' was not found",
          code: "TENANT_NOT_FOUND",
          tenant_alias: tenant_alias
        })

      :tenant_header_required ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Tenant Header Required",
          message: details || "The 'x-tenant' header is required for this operation",
          code: "TENANT_HEADER_REQUIRED"
        })

      :tenant_already_exists ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Tenant Already Exists",
          message: details || "A tenant with alias '#{tenant_alias}' already exists",
          code: "TENANT_ALREADY_EXISTS",
          tenant_alias: tenant_alias
        })
    end
  end

  @doc """
  Handles user-related errors.
  """
  def handle_user_error(conn, error_type, user_id, details \\ nil) do
    case error_type do
      :user_not_found ->
        handle_not_found_error(conn, "User", user_id, details)

      :user_already_exists ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "User Already Exists",
          message: details || "A user with the provided email already exists",
          code: "USER_ALREADY_EXISTS"
        })

      :invalid_user_type ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Invalid User Type",
          message: details || "The specified user type is not valid",
          code: "INVALID_USER_TYPE"
        })
    end
  end

  @doc """
  Handles student-related errors.
  """
  def handle_student_error(conn, error_type, student_id, details \\ nil) do
    case error_type do
      :student_not_found ->
        handle_not_found_error(conn, "Student", student_id, details)

      :student_already_exists ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Student Already Exists",
          message: details || "A student with the provided registration ID already exists",
          code: "STUDENT_ALREADY_EXISTS"
        })

      :profile_token_invalid ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "Invalid Profile Token",
          message: details || "The profile completion token is invalid or has expired",
          code: "INVALID_PROFILE_TOKEN"
        })

      :profile_token_expired ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "Profile Token Expired",
          message:
            details ||
              "The profile completion token has expired. Please contact your administrator",
          code: "PROFILE_TOKEN_EXPIRED"
        })
    end
  end

  @doc """
  Handles assessment-related errors.
  """
  def handle_assessment_error(conn, error_type, assessment_id, details \\ nil) do
    case error_type do
      :assessment_not_found ->
        handle_not_found_error(conn, "Assessment", assessment_id, details)

      :assessment_not_published ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "Assessment Not Published",
          message: details || "This assessment is not available for students",
          code: "ASSESSMENT_NOT_PUBLISHED",
          assessment_id: assessment_id
        })

      :attempt_already_exists ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "Attempt Already Exists",
          message: details || "You have already started an attempt for this assessment",
          code: "ATTEMPT_ALREADY_EXISTS",
          assessment_id: assessment_id
        })

      :attempt_not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "Attempt Not Found",
          message: details || "The specified assessment attempt was not found",
          code: "ATTEMPT_NOT_FOUND"
        })
    end
  end

  @doc """
  Handles general server errors.
  """
  def handle_server_error(conn, error_type, details \\ nil) do
    case error_type do
      :internal_error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Internal Server Error",
          message: details || "An unexpected error occurred while processing your request",
          code: "INTERNAL_ERROR"
        })

      :database_error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Database Error",
          message: details || "A database error occurred while processing your request",
          code: "DATABASE_ERROR"
        })

      :email_error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Email Service Error",
          message: details || "Failed to send email. Please try again later",
          code: "EMAIL_ERROR"
        })
    end
  end

  @doc """
  Formats Ecto changeset errors for JSON response with user-friendly messages.
  """
  def format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &format_error_message/1)
  end

  # Formats a single error message with user-friendly text.
  defp format_error_message({msg, opts}) do
    case classify_error_message(msg, opts) do
      {:unique_constraint, constraint_name} ->
        format_unique_constraint_error(constraint_name)

      {:basic_validation, error_type} ->
        format_basic_validation_error(error_type)

      {:association_error, error_type} ->
        format_association_error(error_type)

      {:length_validation, msg, opts} ->
        format_length_validation_error(msg, opts)

      {:number_validation, msg, opts} ->
        format_number_validation_error(msg, opts)

      {:inclusion_error, opts} ->
        format_inclusion_error(opts)

      {:general_invalid} ->
        "This value is invalid"

      {:default, msg, opts} ->
        format_default_error_message(msg, opts)
    end
  end

  defp classify_error_message("has already been taken", opts) do
    if Keyword.get(opts, :constraint) == :unique do
      {:unique_constraint, Keyword.get(opts, :constraint_name)}
    else
      {:default, "has already been taken", opts}
    end
  end

  defp classify_error_message(msg, opts) do
    cond do
      basic_validation_error?(msg) ->
        {:basic_validation, msg}

      association_error?(msg) ->
        {:association_error, msg}

      length_validation_error?(msg) ->
        {:length_validation, msg, opts}

      number_validation_error?(msg) ->
        {:number_validation, msg, opts}

      inclusion_error?(msg, opts) ->
        {:inclusion_error, opts}

      msg == "is invalid" ->
        {:general_invalid}

      true ->
        {:default, msg, opts}
    end
  end

  defp basic_validation_error?(msg) do
    msg in ["can't be blank", "has invalid format", "must be accepted", "is reserved", "does not match confirmation"]
  end

  defp association_error?(msg) do
    msg in ["is still associated with this entry", "are still associated with this entry"]
  end

  defp length_validation_error?(msg) do
    String.contains?(msg, "should be") and String.contains?(msg, "character(s)")
  end

  defp number_validation_error?(msg) do
    String.contains?(msg, "must be") and String.contains?(msg, "than")
  end

  defp inclusion_error?(msg, opts) do
    msg == "is invalid" and Keyword.has_key?(opts, :inclusion)
  end

  defp format_default_error_message(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp format_basic_validation_error("can't be blank"), do: "This field is required"
  defp format_basic_validation_error("has invalid format"), do: "This value has an invalid format"
  defp format_basic_validation_error("must be accepted"), do: "This field must be accepted"
  defp format_basic_validation_error("is reserved"), do: "This value is reserved and cannot be used"
  defp format_basic_validation_error("does not match confirmation"), do: "This value does not match the confirmation"

  defp format_association_error("is still associated with this entry"),
    do: "This record is still associated with other data and cannot be deleted"

  defp format_association_error("are still associated with this entry"),
    do: "These records are still associated with other data and cannot be deleted"

  defp format_length_validation_error("should be %{count} character(s)", count: count),
    do: "Must be exactly #{count} characters"

  defp format_length_validation_error("should be at least %{count} character(s)", count: count),
    do: "Must be at least #{count} characters"

  defp format_length_validation_error("should be at most %{count} character(s)", count: count),
    do: "Must be at most #{count} characters"

  defp format_number_validation_error("must be greater than %{number}", number: number),
    do: "Must be greater than #{number}"

  defp format_number_validation_error("must be less than %{number}", number: number), do: "Must be less than #{number}"

  defp format_number_validation_error("must be greater than or equal to %{number}", number: number),
    do: "Must be greater than or equal to #{number}"

  defp format_number_validation_error("must be less than or equal to %{number}", number: number),
    do: "Must be less than or equal to #{number}"

  defp format_inclusion_error(inclusion: valid_values), do: "Must be one of: #{Enum.join(valid_values, ", ")}"

  # Formats unique constraint error messages based on constraint name.
  defp format_unique_constraint_error(constraint_name) do
    constraint_messages = %{
      "users_tenant_id_email_index" => "A user with this email already exists in this tenant",
      "students_tenant_id_email_index" => "A student with this email already exists in this tenant",
      "students_tenant_id_registration_id_index" => "A student with this registration ID already exists in this tenant",
      "roles_tenant_id_name_index" => "A role with this name already exists in this tenant",
      "user_roles_user_id_role_id_index" => "This role is already assigned to this user",
      "tenants_alias_index" => "A tenant with this alias already exists",
      "tenants_schema_name_index" => "A tenant with this schema name already exists",
      "platform_admins_email_index" => "A platform admin with this email already exists"
    }

    Map.get(constraint_messages, constraint_name, "This value is already taken")
  end

  @doc """
  Validates required parameters in a request.
  Returns {:ok, params} if all required params are present, {:error, missing_params} otherwise.
  """
  def validate_required_params(params, required_params) do
    missing_params =
      Enum.filter(required_params, fn param ->
        is_nil(Map.get(params, param)) or Map.get(params, param) == ""
      end)

    case missing_params do
      [] -> {:ok, params}
      missing -> {:error, missing}
    end
  end

  @doc """
  Validates UUID format.
  Returns {:ok, uuid} if valid, {:error, :invalid_uuid} otherwise.
  """
  def validate_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end
end
