defmodule VyaasaCampusWeb.Student.AssessmentController do
  @moduledoc """
  Controller for student assessment operations.

  This controller handles student-specific assessment operations including:
  - Viewing published assessments
  - Starting and taking assessments
  - Submitting assessment attempts
  - Viewing attempt history

  ## Authentication
  Requires student authentication.

  ## Authorization
  - Students can only access assessments in their own tenant
  - Students can only view published assessments
  """

  use VyaasaCampusWeb, :controller
  alias VyaasaCampus.Contexts.Assessments

  @doc """
  Lists published assessments for students /api/student/assessments
  """
  def index_published(conn, _params) do
    schema = get_tenant_schema_from_jwt(conn)
    assessments = Assessments.list_assessments(schema)
    json(conn, %{assessments: assessments})
  end

  @doc """
  Shows a specific published assessment /api/student/assessments/:id
  """
  def show_published(conn, %{"id" => id}) do
    schema = get_tenant_schema_from_jwt(conn)

    case Assessments.get_assessment!(id, schema) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Assessment not found"})

      assessment ->
        if assessment.status == "published" do
          json(conn, %{assessment: assessment})
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Assessment is not available"})
        end
    end
  end

  @doc """
  Starts an assessment attempt /api/student/assessments/:id/start
  """
  def start_attempt(conn, %{"id" => assessment_id}) do
    schema = get_tenant_schema_from_jwt(conn)
    current_user = conn.assigns.current_user

    with {:ok, student} <- get_student_from_user(current_user, schema),
         {:ok, attempt} <- start_assessment_attempt(assessment_id, student.id, schema) do
      conn
      |> put_status(:created)
      |> json(%{
        attempt: attempt,
        message: "Assessment attempt started successfully"
      })
    else
      {:error, :student_access_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "Student access required"})

      {:error, :assessment_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Assessment not found"})

      {:error, :already_started} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Assessment already started"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp start_assessment_attempt(assessment_id, student_id, schema) do
    Assessments.start_assessment(assessment_id, student_id, schema)
  end

  @doc """
  Shows a specific assessment attempt /api/student/attempts/:id
  """
  def show_attempt(conn, %{"id" => attempt_id}) do
    schema = get_tenant_schema_from_jwt(conn)
    current_user = conn.assigns.current_user

    with {:ok, student} <- get_student_from_user(current_user, schema),
         {:ok, attempt} <- get_attempt_if_exists(attempt_id, schema),
         :ok <- validate_attempt_ownership(attempt, student) do
      json(conn, %{attempt: attempt})
    else
      {:error, :student_access_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "Student access required"})

      {:error, :attempt_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Attempt not found"})

      {:error, :access_denied} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  end

  defp get_student_from_user(%VyaasaCampus.Schema.Accounts.User{email: email}, schema) do
    # Query student by email since students now have their own email field
    alias VyaasaCampus.Repo
    alias VyaasaCampus.Schema.Students.Student

    case Repo.get_by(Student, email: email, prefix: schema) do
      nil -> {:error, :student_access_required}
      student -> {:ok, student}
    end
  end

  defp get_student_from_user(%VyaasaCampus.Schema.Students.Student{} = student, _schema),
    do: {:ok, student}

  defp get_student_from_user(_, _), do: {:error, :student_access_required}

  defp get_attempt_if_exists(attempt_id, schema) do
    case Assessments.get_attempt(attempt_id, schema) do
      nil -> {:error, :attempt_not_found}
      attempt -> {:ok, attempt}
    end
  end

  defp validate_attempt_ownership(attempt, student) do
    if attempt.student_id == student.id do
      :ok
    else
      {:error, :access_denied}
    end
  end

  @doc """
  Submits an assessment attempt /api/student/attempts/:id/submit
  """
  def submit_attempt(conn, %{"id" => attempt_id, "answers" => answers}) do
    schema = get_tenant_schema_from_jwt(conn)
    current_user = conn.assigns.current_user

    with {:ok, _student} <- get_student_from_user(current_user, schema),
         {:ok, submitted_attempt} <- submit_assessment_attempt(attempt_id, answers, schema) do
      json(conn, %{
        attempt: submitted_attempt,
        message: "Assessment submitted successfully"
      })
    else
      {:error, :student_access_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "Student access required"})

      {:error, :attempt_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Attempt not found"})

      {:error, :already_submitted} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Assessment already submitted"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp submit_assessment_attempt(attempt_id, answers, schema) do
    Assessments.submit_assessment(attempt_id, answers, schema)
  end

  @doc """
  Lists student's assessment attempts /api/student/my-attempts
  """
  def my_attempts(conn, _params) do
    schema = get_tenant_schema_from_jwt(conn)
    current_user = conn.assigns.current_user

    case get_student_from_user(current_user, schema) do
      {:ok, student} ->
        attempts = Assessments.list_student_attempts(student.id, schema)
        json(conn, %{attempts: attempts})

      {:error, :student_access_required} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Student access required"})
    end
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
