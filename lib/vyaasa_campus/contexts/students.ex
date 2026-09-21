defmodule VyaasaCampus.Contexts.Students do
  @moduledoc """
  The Students context for managing student users and profiles within a tenant.
  Handles creation, listing, and bulk creation of students, with auditability.

  The `created_by` field in the students table is set here (from `created_by_id` in the API payload)
  before calling the changeset. This ensures the audit trail is preserved and the changeset only
  validates its presence, not how it is derived.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [put_change: 3, change: 2]
  import VyaasaCampus.Types
  require Logger
  alias VyaasaCampus.Auth.PasswordResetService
  alias VyaasaCampus.DashboardEvents
  alias VyaasaCampus.Mail.EmailOrchestrator
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Students.Student

  # ============================================================================
  # PUBLIC API FUNCTIONS
  # ============================================================================

  @doc """
  Returns all students in a tenant schema.
  """
  def list_students(prefix) do
    Student
    |> order_by(desc: :updated_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Bulk creates students in a tenant using the multi-step onboarding flow with concurrent processing.
  Uses Task.async_stream for fault-tolerant concurrent processing following Phoenix 1.8 guidelines.
  Accepts a list of student attribute maps and tenant alias.

  ## Parameters
    - student_data: List of student attribute maps
    - tenant_alias: Tenant alias for email generation
    - prefix: Database schema prefix for tenant isolation
    - opts: Options map with:
      - :max_concurrency (integer) - Max concurrent operations (default: System.schedulers_online())
      - :timeout (integer) - Timeout per operation in ms (default: :infinity)

  ## Returns
    - `{:ok, %{successes: [students], errors: [errors], total: count, duration_ms: ms}}` on completion
    - `{:error, reason}` on critical failure
  """
  def bulk_create_students(student_data, tenant_alias, prefix, opts \\ %{}) when is_list(student_data) do
    bulk_create_students_concurrent(student_data, tenant_alias, prefix, opts)
  end

  @doc """
  Get student by ID in a tenant
  """
  def get_student(id, prefix) do
    Repo.get(Student, id, prefix: prefix)
  end

  @doc """
  Get student by email in a tenant
  """
  def get_student_by_email(email, prefix) do
    import Ecto.Query

    Student
    |> where(email: ^email)
    |> Repo.one(prefix: prefix)
  end

  @doc """
  Update a student's profile (admin function).
  """
  def update_student(id, attrs, prefix) do
    require Logger
    Logger.info("🔄 Students.update_student called - ID: #{id}, prefix: #{prefix}")
    Logger.info("📝 Update attributes: #{inspect(attrs)}")

    case get_student(id, prefix) do
      nil ->
        Logger.error("❌ Student not found: #{id} in schema: #{prefix}")
        {:error, :student_not_found}

      student ->
        Logger.info("✅ Student found: #{student.id}, current status: #{student.status}")

        # For internal updates, convert string keys to atoms directly (trusted source)
        safe_attrs =
          if is_map(attrs) and Map.has_key?(attrs, "status") do
            # External API call - use safe conversion
            safe_atom_conversion(attrs)
          else
            # Internal call with atom keys - use as-is
            attrs
          end

        Logger.info("🔄 Safe attributes: #{inspect(safe_attrs)}")

        with :ok <- guard_status_transition(student, safe_attrs) do
          do_update_student(student, safe_attrs, prefix)
        end
    end
  end

  # Once a student reaches a "verified" or "active" state they should not slip
  # back to a pre-verification status. Reject those transitions explicitly so
  # an admin/API mistake can't downgrade a verified student.
  defp guard_status_transition(student, attrs) do
    new_status = Map.get(attrs, :status) || Map.get(attrs, "status")

    cond do
      is_nil(new_status) ->
        :ok

      to_string(new_status) == to_string(student.status) ->
        :ok

      student.status in ["verified", "active"] and
          to_string(new_status) in ["unverified", "pending", "profile_incomplete"] ->
        require Logger

        Logger.warning(
          "⛔ Blocked status downgrade for student #{student.id}: #{student.status} → #{new_status}"
        )

        {:error, :verified_status_locked}

      true ->
        :ok
    end
  end

  defp do_update_student(student, safe_attrs, prefix) do
    require Logger

    changeset = Student.changeset(student, safe_attrs)
    Logger.info("🔍 Changeset valid?: #{changeset.valid?}")
    Logger.info("🔍 Changeset changes: #{inspect(changeset.changes)}")
    Logger.info("🔍 Changeset errors: #{inspect(changeset.errors)}")

    case Repo.update(changeset, prefix: prefix) do
      {:ok, updated_student} ->
        Logger.info("✅ Student updated successfully!")

        Logger.info(
          "📊 New status: #{updated_student.status}, profile_completed: #{updated_student.profile_completed}"
        )

        DashboardEvents.broadcast_student_event(:updated, prefix, updated_student.id)

        {:ok, updated_student}

      {:error, changeset} ->
        Logger.error("❌ Failed to update student in repository")
        Logger.error("🔍 Repository changeset errors: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Request password reset for a student.
  Delegates to the unified PasswordResetService.
  """
  def request_password_reset(email, tenant_alias, prefix) do
    PasswordResetService.request_password_reset(email, tenant_alias, prefix)
  end

  @doc """
  Reset student password using token.
  Delegates to the unified PasswordResetService.
  """
  def reset_password_with_token(token, new_password, prefix) do
    PasswordResetService.reset_password_with_token(token, new_password, nil, prefix)
  end

  @doc """
  Clear temporary password after first login
  """
  def clear_temp_password(student_id, prefix) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        student
        |> Student.clear_temp_password()
        |> Repo.update(prefix: prefix)
        |> case do
          {:ok, updated_student} ->
            Logger.info("Temporary password cleared for student #{updated_student.email}")
            {:ok, updated_student}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # ============================================================================
  # MULTI-STEP STUDENT ONBOARDING FUNCTIONS
  # ============================================================================

  @doc """
  Creates a partial student with minimal fields (Step 1 of onboarding).
  Sends profile completion email with secure token.

  ## Multi-Step Onboarding Flow
  1. create_partial_student/3 - Creates student with basic info + sends completion email
  2. Student completes profile via token (handled by ProfileCompletionController)
  3. update_student_profile/3 - Updates profile and marks for approval
  4. approve_student/5 or reject_student/5 - Admin approval process

  ## Parameters
    - attrs: Map containing student basic information
    - tenant_alias: String tenant alias for email URLs
    - prefix: String database schema prefix

  ## Returns
    - `{:ok, student}` on success
    - `{:error, changeset}` on validation failure
  """
  def create_partial_student(attrs, tenant_alias, prefix) do
    safe_attrs = safe_atom_conversion(attrs)
    student_attrs = Map.put(safe_attrs, :status, student_status_pending())

    # Auto-resolve degree_id and specialization_id from text fields if not already set
    student_attrs = maybe_resolve_academic_ids(student_attrs)

    case %Student{}
         |> Student.partial_student_changeset(student_attrs)
         |> Repo.insert(prefix: prefix) do
      {:ok, student} ->
        Logger.info("Partial student created: #{student.email}")
        DashboardEvents.broadcast_student_event(:created, prefix, student.id)
        send_profile_completion_email(student, tenant_alias, prefix)

      {:error, changeset} ->
        Logger.error("Failed to create partial student: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Creates a student (alias for create_partial_student)
  """
  def create_student(attrs, tenant_alias, prefix) do
    create_partial_student(attrs, tenant_alias, prefix)
  end

  @doc """
  Generates a profile completion token for a student.
  """
  def generate_profile_token(student, prefix) do
    student
    |> Student.generate_profile_token_changeset()
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, updated_student} ->
        Logger.info("Profile token generated for student: #{updated_student.email}")
        {:ok, updated_student}

      {:error, changeset} ->
        Logger.error("Failed to generate profile token: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Verifies if a profile token is valid and not expired.
  """
  def verify_profile_token(token, prefix) do
    import Ecto.Query

    case Student
         |> where(profile_token: ^token)
         |> Repo.one(prefix: prefix) do
      nil ->
        Logger.warning("Invalid profile token attempted: #{token}")
        {:error, :invalid_token}

      student ->
        cond do
          not profile_completion_allowed?(student) ->
            # The profile has already been submitted (ready for verification) or
            # the student is already verified/active. The link is single-use for
            # onboarding — reject it so documents can't be uploaded again.
            Logger.warning(
              "Profile token reused after submission for student #{student.email} (status: #{student.status})"
            )

            {:error, :profile_already_submitted}

          Student.profile_token_valid?(student) ->
            Logger.info("Profile token verified for student: #{student.email}")
            {:ok, student}

          true ->
            Logger.warning("Expired profile token attempted for student: #{student.email}")
            {:error, :token_expired}
        end
    end
  end

  @doc """
  Finalizes profile submission: flips the student to "unverified" (awaiting
  admin review) and stamps `profile_submitted_at`.

  This is the single point where the profile_token is invalidated — it must
  only be called when the student explicitly clicks "Continue to Verification"
  on the results step. If it fired any earlier (e.g. right after resume
  upload or as soon as ATS scoring finishes), a dropped connection or refresh
  before that click would hit `profile_completion_allowed?/1` and show
  "already submitted" even though the student never confirmed — losing their
  in-progress session for no reason.
  """
  def finalize_profile_submission(student_id, prefix) do
    update_student(
      student_id,
      %{
        status: student_status_unverified(),
        profile_completed: true,
        profile_submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      prefix
    )
  end

  # A profile-completion link is only usable while the student still needs to
  # submit their profile — i.e. they were just invited (`pending`) or were asked
  # to make edits (`profile_incomplete`). Once the profile is submitted
  # (`unverified` = ready for verification), verified, or active, the link is
  # dead. This is the single chokepoint that both the GET verify and the POST
  # submit flow through, so it stops re-uploads regardless of the entry point.
  defp profile_completion_allowed?(student) do
    student.status in [student_status_pending(), student_status_profile_incomplete()]
  end

  @doc """
  Updates student profile via token and marks as pending approval.
  """
  def update_student_profile(token, attrs, prefix) do
    case verify_profile_token(token, prefix) do
      {:ok, student} ->
        safe_attrs = safe_atom_conversion(attrs)

        student
        |> Student.profile_completion_via_token_changeset(safe_attrs)
        |> Repo.update(prefix: prefix)
        |> case do
          {:ok, updated_student} ->
            Logger.info("Profile completed for student: #{updated_student.email}")
            DashboardEvents.broadcast_student_event(:updated, prefix, updated_student.id)
            {:ok, updated_student}

          {:error, changeset} ->
            Logger.error("Failed to update student profile: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists students with pending approval status.
  """
  def list_pending_students(prefix) do
    import Ecto.Query

    Student
    |> where(status: ^student_status_unverified())
    |> order_by([s], desc: s.profile_submitted_at)
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Approves a student profile and sends login credentials.
  """
  def approve_student(student_id, approved_by_id, admin_notes \\ nil, tenant_alias, prefix) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        # Generate temporary password
        temp_password = Student.generate_temp_password()

        # Update student status and set encrypted password
        case student
             |> Student.approval_changeset(%{
               status: student_status_active(),
               approved_by_id: approved_by_id,
               admin_notes: admin_notes
             })
             |> put_change(:encrypted_password, Bcrypt.hash_pwd_salt(temp_password))
             |> put_change(:temp_password, temp_password)
             |> put_change(
               :temp_password_sent_at,
               DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update(prefix: prefix) do
          {:ok, updated_student} ->
            Logger.info("Student approved: #{updated_student.email} by admin: #{approved_by_id}")
            DashboardEvents.broadcast_student_event(:updated, prefix, updated_student.id)
            send_approval_email(updated_student, temp_password, tenant_alias)
            {:ok, updated_student}

          {:error, changeset} ->
            Logger.error("Failed to approve student: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  @doc """
  Verifies a student, issues a temporary password, and emails it.

  This is the single source of truth for the admin "Verify" action so every
  entry point (the dashboard and the students table) behaves identically:
  the student is marked `verified`, a temporary password is generated and set
  as the login password, and the profile-approved email carrying that password
  is sent.

  Returns `{:ok, student, email_result}` where `email_result` is the
  `EmailOrchestrator` result (`{:ok, :email_sent}` | `{:error, reason}`) so the
  caller can surface the *real* delivery status. Returns `{:error, reason}` if
  the database update fails (in which case no email is attempted).
  """
  def verify_student_and_notify(student_id, tenant_alias, prefix) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, verified} <-
           update_student(
             student_id,
             %{status: student_status_verified(), profile_approved_at: now},
             prefix
           ),
         temp_password = Student.generate_temp_password(),
         {:ok, final} <-
           update_student(
             student_id,
             %{
               temp_password: temp_password,
               encrypted_password: Bcrypt.hash_pwd_salt(temp_password),
               temp_password_sent_at: now
             },
             prefix
           ) do
      email_result =
        EmailOrchestrator.send_profile_approved_email(verified, temp_password, tenant_alias)

      case email_result do
        {:ok, :email_sent} ->
          Logger.info("Verify: temp-password email sent to #{verified.email}")

        {:error, reason} ->
          Logger.error(
            "Verify: temp-password email delivery FAILED for #{verified.email}: #{inspect(reason)}"
          )
      end

      {:ok, final, email_result}
    end
  end

  @doc """
  Rejects a student profile with feedback and requests edits.
  """
  def reject_student(
        student_id,
        approved_by_id,
        admin_notes,
        edit_request_notes,
        tenant_alias,
        prefix
      ) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        # Invalidate existing profile token first
        invalidate_profile_token(student, prefix)

        # Generate new profile completion token for edits
        case student
             |> Student.rejection_changeset(%{
               status: student_status_profile_incomplete(),
               approved_by_id: approved_by_id,
               admin_notes: admin_notes,
               edit_request_notes: edit_request_notes
             })
             |> Repo.update(prefix: prefix) do
          {:ok, rejected_student} ->
            Logger.info("Student rejected: #{rejected_student.email} by admin: #{approved_by_id}")

            DashboardEvents.broadcast_student_event(:updated, prefix, rejected_student.id)

            send_rejection_email(
              rejected_student,
              admin_notes,
              edit_request_notes,
              tenant_alias,
              prefix
            )

            {:ok, rejected_student}

          {:error, changeset} ->
            Logger.error("Failed to reject student: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  @doc """
  Resend profile completion email for a student.
  Generates a new token and sends email.
  """
  def resend_profile_completion_email(student_id, tenant_alias, prefix) do
    case get_student(student_id, prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        if student.status in [student_status_pending(), student_status_profile_incomplete()] do
          Logger.info("Resending profile completion email for student: #{student.email}")
          send_profile_completion_email(student, tenant_alias, prefix)
        else
          Logger.warning("Cannot resend email for student #{student.email} with status: #{student.status}")

          {:error, :invalid_status}
        end
    end
  end

  # ============================================================================
  # PROFILE EDIT REQUEST FUNCTIONS (For Active Students)
  # ============================================================================

  @doc """
  Request profile edit for an active student.
  Student submits edit request which goes to admin for approval.
  After admin approval, student will receive a token to edit their profile.
  """
  def request_profile_edit(student_id, tenant_alias, prefix) do
    with {:ok, student} <- get_student_for_edit_request(student_id, prefix),
         :ok <- validate_student_active_status(student),
         {:ok, updated_student} <- create_edit_request_token(student, prefix) do
      send_edit_request_notification(updated_student, tenant_alias, prefix)
      {:ok, updated_student}
    end
  end

  defp get_student_for_edit_request(student_id, prefix) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil -> {:error, :student_not_found}
      student -> {:ok, student}
    end
  end

  defp validate_student_active_status(student) do
    if student.status == student_status_active() do
      :ok
    else
      {:error, :invalid_status}
    end
  end

  defp create_edit_request_token(student, prefix) do
    edit_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, profile_completion_token_expiry(), :hour)

    student
    |> Student.edit_request_changeset(%{
      edit_request_token: edit_token,
      edit_request_token_expires_at: expires_at,
      edit_requested_at: now
    })
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, updated_student} ->
        Logger.info("Profile edit requested by student: #{updated_student.email}")
        {:ok, updated_student}

      {:error, changeset} ->
        Logger.error("Failed to request profile edit: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Approve profile edit request from active student.
  Generates a profile completion token for the student to edit their profile.
  """
  def approve_profile_edit(student_id, approved_by_id, admin_notes \\ nil, tenant_alias, prefix) do
    with {:ok, student} <- get_student_for_edit_approval(student_id, prefix),
         :ok <- validate_edit_request_exists(student),
         {:ok, student_with_token} <- generate_profile_token(student, prefix),
         {:ok, updated_student} <- finalize_edit_approval(student_with_token, approved_by_id, admin_notes, prefix) do
      send_edit_approval_email(updated_student, admin_notes, tenant_alias)
      {:ok, updated_student}
    end
  end

  defp get_student_for_edit_approval(student_id, prefix) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil -> {:error, :student_not_found}
      student -> {:ok, student}
    end
  end

  defp validate_edit_request_exists(student) do
    if student.edit_request_token do
      :ok
    else
      {:error, :no_edit_request}
    end
  end

  defp finalize_edit_approval(student_with_token, approved_by_id, admin_notes, prefix) do
    student_with_token
    |> Student.approve_edit_request_changeset(%{
      approved_by_id: approved_by_id,
      admin_notes: admin_notes
    })
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, updated_student} ->
        Logger.info("Profile edit approved for student: #{updated_student.email}")
        {:ok, updated_student}

      {:error, changeset} ->
        Logger.error("Failed to approve profile edit: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Reject profile edit request from active student.
  """
  def reject_profile_edit(
        student_id,
        approved_by_id,
        admin_notes,
        rejection_notes,
        tenant_alias,
        prefix
      ) do
    with {:ok, student} <- find_student_for_edit_rejection(student_id, prefix),
         {:ok, updated_student} <-
           update_student_edit_rejection(student, approved_by_id, admin_notes, rejection_notes, prefix) do
      send_edit_rejection_email(updated_student, admin_notes, rejection_notes, tenant_alias)
      {:ok, updated_student}
    end
  end

  defp find_student_for_edit_rejection(student_id, prefix) do
    case Repo.get(Student, student_id, prefix: prefix) do
      nil -> {:error, :student_not_found}
      student -> validate_edit_request_token(student)
    end
  end

  defp update_student_edit_rejection(student, approved_by_id, admin_notes, rejection_notes, prefix) do
    student
    |> Student.reject_edit_request_changeset(%{
      approved_by_id: approved_by_id,
      admin_notes: admin_notes,
      edit_request_notes: rejection_notes
    })
    |> Repo.update(prefix: prefix)
    |> case do
      {:ok, updated_student} ->
        Logger.info("Profile edit rejected for student: #{updated_student.email}")
        {:ok, updated_student}

      {:error, changeset} ->
        Logger.error("Failed to reject profile edit: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp validate_edit_request_token(student) do
    if student.edit_request_token do
      {:ok, student}
    else
      {:error, :no_edit_request}
    end
  end

  @doc """
  List students with pending edit requests.
  """
  def list_pending_edit_requests(prefix) do
    import Ecto.Query

    Student
    |> where([s], not is_nil(s.edit_request_token))
    |> where([s], s.status == ^student_status_active())
    |> order_by([s], desc: s.edit_requested_at)
    |> Repo.all(prefix: prefix)
  end

  # ============================================================================
  # BULK OPERATIONS WITH CONCURRENCY AND FAULT TOLERANCE
  # ============================================================================

  @doc """
  Bulk creates students using Task.async_stream for concurrent processing.
  Suitable for smaller to medium batches with good performance characteristics.
  """
  def bulk_create_students_concurrent(student_data, tenant_alias, prefix, opts) do
    max_concurrency = Map.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Map.get(opts, :timeout, :infinity)

    Logger.info("Starting concurrent bulk student creation: #{length(student_data)} students")

    start_time = System.monotonic_time(:millisecond)

    # Use Task.async_stream for concurrent processing with back-pressure
    results =
      student_data
      |> Task.async_stream(
        fn student_attrs ->
          # Each task creates a student and handles its own transaction
          case create_partial_student(student_attrs, tenant_alias, prefix) do
            {:ok, student} ->
              {:success, student}

            {:error, changeset} ->
              {:error, format_changeset_errors(changeset)}
          end
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        # Better performance for large batches
        ordered: false
      )
      |> Enum.to_list()

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Process results and separate successes from errors
    {successes, errors} = process_concurrent_results(results)

    Logger.info(
      "Concurrent bulk student creation completed in #{duration}ms: #{length(successes)} successes, #{length(errors)} errors"
    )

    {:ok,
     %{
       successes: successes,
       errors: errors,
       total: length(student_data),
       duration_ms: duration,
       concurrency_used: max_concurrency
     }}
  end

  @doc """
  Bulk sends emails using Task.async_stream for concurrent delivery.
  """
  def bulk_send_emails(email_jobs, tenant_alias, opts \\ %{}) do
    # Limit email concurrency
    max_concurrency = Map.get(opts, :max_concurrency, 5)
    # 30 seconds per email
    timeout = Map.get(opts, :timeout, 30_000)

    Logger.info("Starting concurrent bulk email sending: #{length(email_jobs)} emails")

    results =
      email_jobs
      |> Task.async_stream(
        fn email_job ->
          send_single_email(email_job, tenant_alias)
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    {successes, errors} = process_concurrent_results(results)

    Logger.info("Bulk email sending completed: #{length(successes)} sent, #{length(errors)} failed")

    {:ok,
     %{
       sent: length(successes),
       failed: length(errors),
       total: length(email_jobs),
       errors: errors
     }}
  end

  @doc """
  Bulk updates students using Task.async_stream for concurrent processing.
  """
  def bulk_update_students(updates, prefix, opts \\ %{}) do
    max_concurrency = Map.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Map.get(opts, :timeout, :infinity)

    Logger.info("Starting concurrent bulk student updates: #{length(updates)} updates")

    results =
      updates
      |> Task.async_stream(
        fn %{student_id: student_id, attrs: attrs} ->
          case update_student(student_id, attrs, prefix) do
            {:ok, student} -> {:success, student}
            {:error, reason} -> {:error, reason}
          end
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    {successes, errors} = process_concurrent_results(results)

    Logger.info("Bulk student updates completed: #{length(successes)} updated, #{length(errors)} failed")

    {:ok,
     %{
       updated: successes,
       errors: errors,
       total: length(updates)
     }}
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  # Helper function to process Task.async_stream results
  defp process_concurrent_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, {:success, item}}, {successes, errors} ->
        {[item | successes], errors}

      {:ok, {:error, error}}, {successes, errors} ->
        {successes, [error | errors]}

      {:exit, reason}, {successes, errors} ->
        {successes, [{:task_timeout, reason} | errors]}

      other, {successes, errors} ->
        {successes, [{:unexpected_result, other} | errors]}
    end)
  end

  # Helper function to send individual emails
  defp send_single_email(%{type: :profile_completion, student: student, profile_url: profile_url}, tenant_alias) do
    EmailOrchestrator.send_profile_completion_email(student, profile_url, tenant_alias)
  end

  defp send_single_email(%{type: :approval, student: student, temp_password: temp_password}, tenant_alias) do
    EmailOrchestrator.send_profile_approved_email(student, temp_password, tenant_alias)
  end

  defp send_single_email(%{type: :password_reset, student: student}, tenant_alias) do
    EmailOrchestrator.send_password_reset_email(student, tenant_alias)
  end

  defp send_single_email(unknown_job, _tenant_alias) do
    Logger.error("Unknown email job type: #{inspect(unknown_job)}")
    {:error, :unknown_email_type}
  end

  # Helper function to format changeset errors for concurrent operations
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc false
  # Mailing functions
  defp send_profile_completion_email(student, tenant_alias, prefix) do
    case generate_profile_token(student, prefix) do
      {:ok, student_with_token} ->
        profile_url = generate_profile_completion_url(student_with_token, tenant_alias)

        case EmailOrchestrator.send_profile_completion_email(
               student_with_token,
               profile_url,
               tenant_alias
             ) do
          {:ok, :email_sent} ->
            Logger.info("Profile completion email sent to: #{student_with_token.email}")

          {:error, reason} ->
            Logger.error(
              "Email delivery FAILED for #{student_with_token.email}: #{inspect(reason)}"
            )
        end

        # Student was persisted regardless of email status; always return ok.
        # Admin can retry via the Resend Invite action in the student detail drawer.
        {:ok, student_with_token}

      {:error, reason} ->
        Logger.error("Failed to generate profile token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  defp send_approval_email(student, temp_password, tenant_alias) do
    EmailOrchestrator.send_profile_approved_email(student, temp_password, tenant_alias)
    Logger.info("Approval email sent to: #{student.email}")
  end

  @doc false
  defp send_rejection_email(student, admin_notes, edit_request_notes, tenant_alias, prefix) do
    case generate_profile_token(student, prefix) do
      {:ok, student_with_token} ->
        profile_url = generate_profile_completion_url(student_with_token, tenant_alias)

        EmailOrchestrator.send_profile_edit_request_email(
          student_with_token,
          profile_url,
          admin_notes,
          edit_request_notes,
          tenant_alias
        )

        Logger.info("Rejection email sent to: #{student_with_token.email}")
        {:ok, student_with_token}

      {:error, reason} ->
        Logger.error("Failed to send rejection email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  defp invalidate_profile_token(student, prefix) do
    student
    |> change(%{
      profile_token: nil,
      profile_token_expires_at: nil
    })
    |> Repo.update(prefix: prefix)
  end

  @doc false
  defp generate_profile_completion_url(student, tenant_alias) do
    base_url = Application.get_env(:vyaasa_campus, :frontend_url, "http://localhost:4000")
    "#{base_url}/profile/#{student.profile_token}/ats?tenant=#{tenant_alias}"
  end

  # ============================================================================
  # PROFILE EDIT REQUEST EMAIL FUNCTIONS
  # ============================================================================

  @doc false
  defp send_edit_request_notification(student, _tenant_alias, _prefix) do
    # Send notification to admin about pending edit request
    # This would typically notify admins about new edit requests
    Logger.info("Edit request notification sent for student: #{student.email}")
    {:ok, :notification_sent}
  end

  @doc false
  defp send_edit_approval_email(student, admin_notes, tenant_alias) do
    EmailOrchestrator.send_profile_edit_approved_email(student, admin_notes, tenant_alias)
    Logger.info("Profile edit approval email sent to: #{student.email}")
  end

  @doc false
  defp send_edit_rejection_email(student, admin_notes, rejection_notes, tenant_alias) do
    EmailOrchestrator.send_profile_edit_rejected_email(
      student,
      admin_notes,
      rejection_notes,
      tenant_alias
    )

    Logger.info("Profile edit rejection email sent to: #{student.email}")
  end

  # ============================================================================
  # ATS BUSINESS RULES FUNCTIONS
  # ============================================================================

  @doc """
  Updates student profile completion status based on ATS results.
  """
  def approve_student_profile(student_id, prefix) do
    case get_student(student_id, prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        student
        |> Student.approval_changeset(%{
          status: student_status_verified(),
          admin_notes: "Auto-approved based on ATS score",
          # System-generated approval
          approved_by_id: "system"
        })
        |> Repo.update(prefix: prefix)
    end
  end

  @doc """
  Rejects student profile with admin notes.
  """
  def reject_student_profile(student_id, admin_notes, prefix) do
    case get_student(student_id, prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        student
        |> Student.rejection_changeset(%{
          status: student_status_profile_incomplete(),
          admin_notes: admin_notes,
          approved_by_id: "system",
          edit_request_notes: "Please review and resubmit based on admin feedback"
        })
        |> Repo.update(prefix: prefix)
    end
  end

  @doc """
  Updates student status to require manual review.
  """
  def require_manual_review(student_id, reason, prefix) do
    case get_student(student_id, prefix) do
      nil ->
        {:error, :student_not_found}

      student ->
        student
        |> change(%{
          status: student_status_unverified(),
          admin_notes: "Manual review required: #{reason}"
        })
        |> Repo.update(prefix: prefix)
    end
  end

  @doc """
  Get student by ID (non-prefixed version for ATS context).
  """
  def get_student(student_id) do
    # This assumes tenant context is handled elsewhere
    # In a real implementation, you'd need tenant context
    Repo.get(Student, student_id)
  end

  # Auto-resolve degree_id and specialization_id from text fields
  defp maybe_resolve_academic_ids(attrs) do
    degree = attrs[:degree] || attrs["degree"]
    specialization = attrs[:specialization] || attrs["specialization"]
    degree_id = attrs[:degree_id] || attrs["degree_id"]
    spec_id = attrs[:specialization_id] || attrs["specialization_id"]

    if (is_nil(degree_id) or degree_id == "") and is_binary(degree) and degree != "" do
      {resolved_degree_id, resolved_spec_id} =
        VyaasaCampus.Contexts.Academics.resolve_degree_and_specialization_ids(
          degree,
          specialization || ""
        )

      attrs
      |> maybe_put(:degree_id, resolved_degree_id)
      |> maybe_put(:specialization_id, if(is_nil(spec_id) or spec_id == "", do: resolved_spec_id, else: spec_id))
    else
      attrs
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
