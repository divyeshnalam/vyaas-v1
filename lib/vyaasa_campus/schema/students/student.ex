defmodule VyaasaCampus.Schema.Students.Student do
  @moduledoc """
  Student schema and changeset functions.

  Defines the student entity with comprehensive profile management including:
  - Basic authentication and contact information
  - Academic information and credentials
  - Multi-step profile completion workflow
  - Document uploads and verification process
  - Skills, experience, and ATS scoring
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @behaviour VyaasaCampus.Schemas.Behaviours.PasswordResettable

  @registration_id_starts_with_alnum ~r/^[[:alnum:]]/
  @registration_id_message "must start with a letter or number"

  @name_format ~r/^[a-zA-Z\s]+$/
  @name_format_message "must contain only letters"

  # we needed to use Jason.Encoder to encode the student schema to json
  @derive {Jason.Encoder,
   only: [
     :id,
     :email,
     :first_name,
     :middle_name,
     :last_name,
     :phone,
     :status,
     :email_verified_at,
     :last_login_at,
     :metadata,
     :registration_id,
     :tenure,
     :degree,
     :specialization,
     :degree_id,
     :specialization_id,
     :year_of_passing,
     :current_academic_year,
     :cgpa,
     :location_id,
     :profile_completed,
     :tenant_id,
     :created_by_id,
     :created_by_type,
     :inserted_at,
     :updated_at,
     # Profile completion fields
     :profile_submitted_at,
     :profile_approved_at,
     :approved_by_id,
     :admin_notes,
     # Profile token fields
     :profile_token,
     :profile_token_sent_at,
     :profile_token_expires_at,
     # New rejection and review tracking fields
     :profile_rejected_at,
     :profile_reviewed_at,
     :edit_requested_at,
     :edit_request_notes
   ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "students" do
    # Basic Authentication & Contact Info (Required for semi-profile)
    field :email, :string
    field :encrypted_password, :string
    field :password, :string, virtual: true
    field :first_name, :string
    field :middle_name, :string
    field :last_name, :string
    field :phone, :string

    # Academic Information (Required for semi-profile)
    field :registration_id, :string
    field :degree, :string
    field :specialization, :string
    field :degree_id, :binary_id
    field :specialization_id, :binary_id
    field :year_of_passing, :integer
    field :cgpa, :decimal

    # Additional Academic Info
    field :tenure, :string
    field :current_academic_year, :string
    field :location_id, :binary_id

    # Status & Workflow
    # pending -> profile_incomplete -> unverified -> verified -> active
    field :status, :string, default: student_status_pending()
    field :profile_completed, :boolean, default: false
    field :profile_submitted_at, :utc_datetime
    field :profile_approved_at, :utc_datetime
    field :profile_rejected_at, :utc_datetime
    field :profile_reviewed_at, :utc_datetime
    field :edit_requested_at, :utc_datetime
    # References admin who approved
    field :approved_by_id, :binary_id
    # For approval/rejection feedback
    field :admin_notes, :string
    # Specific notes for what needs to be edited
    field :edit_request_notes, :string

    # Profile Completion Token (for multi-step onboarding)
    field :profile_token, :string
    field :profile_token_sent_at, :utc_datetime
    field :profile_token_expires_at, :utc_datetime

    # Profile Edit Request Fields (for active students)
    field :edit_request_data, :map, default: %{}
    field :edit_request_token, :string
    field :edit_request_token_expires_at, :utc_datetime

    # Authentication & Security
    field :email_verified_at, :utc_datetime
    field :last_login_at, :utc_datetime
    field :password_reset_token, :string
    field :password_reset_sent_at, :utc_datetime
    field :temp_password, :string
    field :temp_password_sent_at, :utc_datetime
    # Refresh token fields (store only hash and expiry)
    field :refresh_token_hash, :string
    field :current_session_id, :string
    field :refresh_token_expires_at, :utc_datetime

    # System Fields
    field :metadata, :map, default: %{}
    field :tenant_id, :binary_id
    field :created_by_id, :binary_id
    field :created_by_type, :string

    # Associations
    has_one :ats_phase, VyaasaCampus.Schema.Students.StudentAtsPhase, foreign_key: :student_id
    has_many :behavioral_assessments, VyaasaCampus.Schema.Students.StudentBehavioralAssessment, foreign_key: :student_id

    timestamps()
  end

  # Builds a changeset for a student.
  # The context must provide all required fields, including created_by_id and created_by_type.
  def changeset(student, attrs) do
    student
    |> cast(attrs, [
      :email,
      :encrypted_password,
      :first_name,
      :middle_name,
      :last_name,
      :phone,
      :status,
      :email_verified_at,
      :last_login_at,
      :metadata,
      :password_reset_token,
      :password_reset_sent_at,
      :temp_password,
      :temp_password_sent_at,
      :registration_id,
      :tenure,
      :degree,
      :specialization,
      :degree_id,
      :specialization_id,
      :year_of_passing,
      :current_academic_year,
      :cgpa,
      :location_id,
      :profile_completed,
      :tenant_id,
      :created_by_id,
      :created_by_type,
      # Profile completion fields
      :profile_submitted_at,
      :profile_approved_at,
      :approved_by_id,
      :admin_notes,
      # Profile token fields
      :profile_token,
      :profile_token_sent_at,
      :profile_token_expires_at,
      # New rejection and review tracking fields
      :profile_rejected_at,
      :profile_reviewed_at,
      :edit_requested_at,
      :edit_request_notes
    ])
    |> validate_required([
      :email,
      :first_name,
      :last_name,
      :phone,
      :registration_id,
      :degree,
      :specialization,
      :year_of_passing,
      :cgpa,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:cgpa, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:year_of_passing, greater_than: 1900, less_than: 2100)
    |> validate_inclusion(:status, valid_student_statuses())
    |> validate_inclusion(:created_by_type, valid_creator_types())
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:phone, max: max_phone_length())
    |> validate_length(:registration_id, max: 50)
    |> validate_registration_id()
    |> validate_length(:degree, max: max_title_length())
    |> validate_length(:specialization, max: max_title_length())
    |> normalize_name_fields()
    |> validate_name_format()
    |> unique_constraint([:tenant_id, :email], name: :students_tenant_id_email_index)
    |> unique_constraint([:tenant_id, :registration_id],
      name: :students_tenant_id_registration_id_index
    )
  end

  @doc """
  Changeset for student creation with password hashing
  """
  def create_changeset(student, attrs) do
    student
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :middle_name,
      :last_name,
      :phone,
      :status,
      :email_verified_at,
      :last_login_at,
      :metadata,
      :registration_id,
      :tenure,
      :degree,
      :specialization,
      :degree_id,
      :specialization_id,
      :year_of_passing,
      :current_academic_year,
      :cgpa,
      :location_id,
      :profile_completed,
      :tenant_id,
      :created_by_id,
      :created_by_type,
      # Profile completion fields
      :profile_submitted_at,
      :profile_approved_at,
      :approved_by_id,
      :admin_notes,
      # Profile token fields
      :profile_token,
      :profile_token_sent_at,
      :profile_token_expires_at,
      # New rejection and review tracking fields
      :profile_rejected_at,
      :profile_reviewed_at,
      :edit_requested_at,
      :edit_request_notes
    ])
    |> validate_required([
      :email,
      :password,
      :first_name,
      :last_name,
      :phone,
      :registration_id,
      :degree,
      :specialization,
      :year_of_passing,
      :cgpa,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: min_password_length(), max: max_password_length())
    |> validate_number(:cgpa, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:year_of_passing, greater_than: 1900, less_than: 2100)
    |> validate_inclusion(:status, valid_student_statuses())
    |> validate_inclusion(:created_by_type, valid_creator_types())
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:phone, max: max_phone_length())
    |> validate_length(:registration_id, max: 50)
    |> validate_registration_id()
    |> validate_length(:degree, max: max_title_length())
    |> validate_length(:specialization, max: max_title_length())
    |> normalize_name_fields()
    |> validate_name_format()
    |> unique_constraint([:tenant_id, :email], name: :students_tenant_id_email_index)
    |> unique_constraint([:tenant_id, :registration_id],
      name: :students_tenant_id_registration_id_index
    )
    |> put_hashed_password()
  end

  @doc """
  Changeset for profile completion
  Note: ATS fields (resume, documents, preferred_role) are now handled by StudentAtsPhase
  """
  def profile_completion_changeset(student, attrs) do
    student
    |> cast(attrs, [:profile_completed])
    |> put_change(:profile_completed, true)
    |> put_change(:profile_submitted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:status, student_status_unverified())
  end

  @doc """
  Changeset for profile approval
  """
  def approval_changeset(student, attrs) do
    student
    |> cast(attrs, [:status, :admin_notes, :approved_by_id])
    |> validate_required([:status, :approved_by_id])
    |> validate_inclusion(:status, [student_status_verified(), student_status_active()])
    |> put_change(:profile_approved_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:profile_reviewed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for profile rejection with edit request
  """
  def rejection_changeset(student, attrs) do
    student
    |> cast(attrs, [:status, :admin_notes, :approved_by_id, :edit_request_notes])
    |> validate_required([:status, :approved_by_id, :edit_request_notes])
    |> validate_inclusion(:status, [student_status_profile_incomplete()])
    |> put_change(:profile_rejected_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:profile_reviewed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:edit_requested_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for form validation - allows partial validation without requiring all fields
  This is specifically for progressive form filling where users fill fields gradually
  """
  def form_validation_changeset(student, attrs) do
    student
    |> cast(attrs, [
      :email,
      :first_name,
      :middle_name,
      :last_name,
      :phone,
      :registration_id,
      :degree,
      :specialization,
      :degree_id,
      :specialization_id,
      :year_of_passing,
      :current_academic_year,
      :tenure,
      :cgpa
    ])
    # Only validate fields that have values - don't require anything during progressive filling
    |> maybe_validate_email()
    |> maybe_validate_cgpa()
    |> maybe_validate_year_of_passing()
    |> maybe_validate_name_format(:first_name)
    |> maybe_validate_name_format(:last_name)
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:phone, max: max_phone_length())
    |> validate_length(:registration_id, max: 50)
    |> maybe_validate_registration_id()
    |> validate_length(:degree, max: max_title_length())
    |> validate_length(:specialization, max: max_title_length())
  end

  # Helper functions for conditional validation
  defp maybe_validate_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      "" -> changeset
      _email -> validate_format(changeset, :email, ~r/@/, message: "must be a valid email")
    end
  end

  defp maybe_validate_cgpa(changeset) do
    case get_change(changeset, :cgpa) do
      nil -> changeset
      "" -> changeset
      _cgpa -> validate_number(changeset, :cgpa, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    end
  end

  defp maybe_validate_year_of_passing(changeset) do
    case get_change(changeset, :year_of_passing) do
      nil -> changeset
      "" -> changeset
      _year -> validate_number(changeset, :year_of_passing, greater_than: 1900, less_than: 2100)
    end
  end

  defp validate_registration_id(changeset) do
    validate_format(changeset, :registration_id, @registration_id_starts_with_alnum, message: @registration_id_message)
  end

  defp normalize_name_fields(changeset) do
    changeset
    |> normalize_name_field(:first_name)
    |> normalize_name_field(:last_name)
  end

  defp normalize_name_field(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      "" -> changeset
      value ->
        normalized =
          value
          |> String.trim()
          |> String.split(~r/\s+/, trim: true)
          |> Enum.map(&String.downcase/1)
          |> Enum.map(&String.capitalize/1)
          |> Enum.join(" ")

        put_change(changeset, field, normalized)
    end
  end

  defp validate_name_format(changeset) do
    changeset
    |> validate_format(:first_name, @name_format, message: @name_format_message)
    |> validate_format(:last_name, @name_format, message: @name_format_message)
  end

  defp maybe_validate_name_format(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      "" -> changeset
      _value -> validate_format(changeset, field, @name_format, message: @name_format_message)
    end
  end

  defp maybe_validate_registration_id(changeset) do
    case get_change(changeset, :registration_id) do
      nil -> changeset
      "" -> changeset
      _registration_id -> validate_registration_id(changeset)
    end
  end

  @doc """
  Changeset for creating a partial student (minimal fields only)
  """
  def partial_student_changeset(student, attrs) do
    student
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :phone,
      :registration_id,
      :degree,
      :specialization,
      :degree_id,
      :specialization_id,
      :year_of_passing,
      :cgpa,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_required([
      :email,
      :first_name,
      :last_name,
      :phone,
      :registration_id,
      :degree,
      :specialization,
      :year_of_passing,
      :cgpa,
      :tenant_id,
      :created_by_id,
      :created_by_type
    ])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:cgpa, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:year_of_passing, greater_than: 1900, less_than: 2100)
    |> validate_length(:email, max: max_email_length())
    |> validate_length(:first_name, max: max_name_length())
    |> validate_length(:last_name, max: max_name_length())
    |> validate_length(:phone, max: max_phone_length())
    |> validate_length(:registration_id, max: 50)
    |> validate_registration_id()
    |> validate_length(:degree, max: max_title_length())
    |> validate_length(:specialization, max: max_title_length())
    |> normalize_name_fields()
    |> validate_name_format()
    |> validate_inclusion(:created_by_type, valid_creator_types())
    |> put_change(:status, student_status_pending())
    |> put_change(:profile_completed, false)
    |> unique_constraint([:tenant_id, :email], name: :students_tenant_id_email_index)
    |> unique_constraint([:tenant_id, :registration_id],
      name: :students_tenant_id_registration_id_index
    )
  end

  @doc """
  Changeset for generating profile completion token
  """
  def generate_profile_token_changeset(student) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, profile_completion_token_expiry(), :hour)

    student
    |> change(%{
      profile_token: token,
      profile_token_sent_at: now,
      profile_token_expires_at: expires_at
    })
  end

  @doc """
  Changeset for profile completion via token
  Note: ATS fields (resume, documents, preferred_role) are now handled by StudentAtsPhase
  """
  def profile_completion_via_token_changeset(student, attrs) do
    student
    |> cast(attrs, [:profile_completed])
    |> put_change(:profile_completed, true)
    |> put_change(:profile_submitted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:status, student_status_unverified())
    # Clear token after use
    |> put_change(:profile_token, nil)
    |> put_change(:profile_token_expires_at, nil)
  end

  @doc """
  Changeset for profile edit request from active student
  """
  def edit_request_changeset(student, attrs) do
    student
    |> cast(attrs, [:edit_request_token, :edit_request_token_expires_at, :edit_requested_at])
    |> validate_required([
      :edit_request_token,
      :edit_request_token_expires_at,
      :edit_requested_at
    ])
    |> validate_length(:edit_request_token, min: 32)
  end

  @doc """
  Changeset for approving edit request from active student
  Clears edit request data and generates profile completion token
  """
  def approve_edit_request_changeset(student, attrs) do
    student
    |> cast(attrs, [:approved_by_id, :admin_notes])
    |> validate_required([:approved_by_id])
    |> put_change(:profile_approved_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:profile_reviewed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    # Clear edit request data after approval
    |> put_change(:edit_request_data, nil)
    |> put_change(:edit_request_token, nil)
    |> put_change(:edit_request_token_expires_at, nil)
  end

  @doc """
  Changeset for rejecting edit request from active student
  """
  def reject_edit_request_changeset(student, attrs) do
    student
    |> cast(attrs, [:approved_by_id, :admin_notes, :edit_request_notes])
    |> validate_required([:approved_by_id, :edit_request_notes])
    |> put_change(:profile_rejected_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:profile_reviewed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    # Clear edit request data after rejection
    |> put_change(:edit_request_data, nil)
    |> put_change(:edit_request_token, nil)
    |> put_change(:edit_request_token_expires_at, nil)
  end

  @doc """
  Check if profile token is valid and not expired
  """
  def profile_token_valid?(student) do
    case {student.profile_token, student.profile_token_expires_at} do
      {nil, _} ->
        false

      {_, nil} ->
        false

      {token, expires_at} when is_binary(token) and not is_nil(expires_at) ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt

      _ ->
        false
    end
  end

  defp put_hashed_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :encrypted_password, Bcrypt.hash_pwd_salt(password))
  end

  defp put_hashed_password(changeset), do: changeset

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def generate_password_reset_token(student) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    student
    |> change(%{
      password_reset_token: token,
      password_reset_sent_at: now
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def clear_password_reset_token(student) do
    student
    |> change(%{
      password_reset_token: nil,
      password_reset_sent_at: nil
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def set_temp_password(student, temp_password) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    student
    |> change(%{
      temp_password: temp_password,
      temp_password_sent_at: now
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def clear_temp_password(student) do
    student
    |> change(%{
      temp_password: nil,
      temp_password_sent_at: nil
    })
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def password_reset_token_valid?(student) do
    case student.password_reset_sent_at do
      nil ->
        false

      sent_at ->
        # Token expires after configured hours
        DateTime.diff(DateTime.utc_now(), sent_at, :hour) < password_reset_token_expiry()
    end
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def verify_password(student, password) do
    # Always use encrypted_password for verification (temp passwords are hashed and stored there)
    if student.encrypted_password && student.encrypted_password != "" do
      Bcrypt.verify_pass(password, student.encrypted_password)
    else
      false
    end
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def password_changeset(student, attrs) do
    student
    |> create_changeset(attrs)
  end

  @impl VyaasaCampus.Schemas.Behaviours.PasswordResettable
  def generate_temp_password do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
