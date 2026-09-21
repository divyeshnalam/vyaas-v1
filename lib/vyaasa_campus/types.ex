defmodule VyaasaCampus.Types do
  @moduledoc """
  Centralized types and constants for the VyaasaCampus application.

  This module provides a single source of truth for all status values,
  types, and constants used throughout the application. This eliminates
  magic strings and ensures consistency across the codebase.

  """

  # ============================================================================
  # USER STATUSES
  # ============================================================================

  @user_status_pending "pending"
  @user_status_active "active"
  @user_status_inactive "inactive"
  @user_status_suspended "suspended"

  @valid_user_statuses [
    @user_status_pending,
    @user_status_active,
    @user_status_inactive,
    @user_status_suspended
  ]

  # ============================================================================
  # STUDENT STATUSES
  # ============================================================================

  @student_status_pending "pending"
  @student_status_profile_incomplete "profile_incomplete"
  @student_status_unverified "unverified"
  @student_status_verified "verified"
  @student_status_active "active"

  @valid_student_statuses [
    @student_status_pending,
    @student_status_profile_incomplete,
    @student_status_unverified,
    @student_status_verified,
    @student_status_active
  ]

  # ============================================================================
  # TENANT STATUSES
  # ============================================================================

  @tenant_status_active "active"
  @tenant_status_inactive "inactive"
  @tenant_status_suspended "suspended"

  @valid_tenant_statuses [
    @tenant_status_active,
    @tenant_status_inactive,
    @tenant_status_suspended
  ]

  # ============================================================================
  # ASSESSMENT STATUSES
  # ============================================================================

  @assessment_status_draft "draft"
  @assessment_status_published "published"
  @assessment_status_active "active"
  @assessment_status_completed "completed"
  @assessment_status_archived "archived"

  @valid_assessment_statuses [
    @assessment_status_draft,
    @assessment_status_published,
    @assessment_status_active,
    @assessment_status_completed,
    @assessment_status_archived
  ]

  # ============================================================================
  # ASSESSMENT TYPES
  # ============================================================================

  @assessment_type_quiz "quiz"
  @assessment_type_exam "exam"
  @assessment_type_assignment "assignment"
  @assessment_type_project "project"
  @assessment_type_practice "practice"
  @assessment_type_behavioural "behavioural"

  @valid_assessment_types [
    @assessment_type_quiz,
    @assessment_type_exam,
    @assessment_type_assignment,
    @assessment_type_project,
    @assessment_type_practice,
    @assessment_type_behavioural
  ]

  # ============================================================================
  # ASSESSMENT ATTEMPT STATUSES
  # ============================================================================

  @attempt_status_started "started"
  @attempt_status_in_progress "in_progress"
  @attempt_status_submitted "submitted"
  @attempt_status_evaluated "evaluated"
  @attempt_status_completed "completed"

  @valid_attempt_statuses [
    @attempt_status_started,
    @attempt_status_in_progress,
    @attempt_status_submitted,
    @attempt_status_evaluated,
    @attempt_status_completed
  ]

  # ============================================================================
  # USER ROLES
  # ============================================================================

  @role_admin "admin"
  @role_instructor "instructor"
  @role_student "student"
  @role_superadmin "superadmin"

  @valid_user_roles [
    @role_admin,
    @role_instructor,
    @role_student,
    @role_superadmin
  ]

  # ============================================================================
  # AFFILIATION TYPES
  # ============================================================================

  @affiliation_type_university "university"
  @affiliation_type_college "college"
  @affiliation_type_school "school"
  @affiliation_type_institute "institute"
  @affiliation_type_corporate "corporate"

  @valid_affiliation_types [
    @affiliation_type_university,
    @affiliation_type_college,
    @affiliation_type_school,
    @affiliation_type_institute,
    @affiliation_type_corporate
  ]

  # ============================================================================
  # USER TYPES
  # ============================================================================

  @user_type_admin "admin"
  @user_type_user "user"
  @user_type_student "student"

  @valid_user_types [
    @user_type_admin,
    @user_type_user,
    @user_type_student
  ]

  # ============================================================================
  # CREATOR TYPES
  # ============================================================================

  @creator_type_public "public"
  @creator_type_tenant "tenant"

  @valid_creator_types [
    @creator_type_public,
    @creator_type_tenant
  ]

  # ============================================================================
  # EMAIL TEMPLATES
  # ============================================================================

  @email_template_welcome "welcome"
  @email_template_password_reset "password_reset"
  @email_template_profile_completion "profile_completion"
  @email_template_profile_approved "profile_approved"
  @email_template_profile_edit_request "profile_edit_request"
  @email_template_tenant_creation "tenant_creation"

  @valid_email_templates [
    @email_template_welcome,
    @email_template_password_reset,
    @email_template_profile_completion,
    @email_template_profile_approved,
    @email_template_profile_edit_request,
    @email_template_tenant_creation
  ]

  # ============================================================================
  # TOKEN EXPIRATION TIMES (in hours)
  # ============================================================================

  @password_reset_token_expiry 24
  @profile_completion_token_expiry 48
  @temp_password_expiry 24

  # ============================================================================
  # VALIDATION CONSTANTS
  # ============================================================================

  @max_email_length 255
  @max_name_length 100
  @max_phone_length 20
  @max_description_length 1000
  @max_title_length 200
  @min_password_length 6
  @max_password_length 128
  @max_token_length 64
  @max_url_length 500

  # ============================================================================
  # DATABASE CONSTANTS
  # ============================================================================

  @tenant_schema_prefix "tenant_"
  @public_schema "public"

  # ============================================================================
  # EXPORT ALL CONSTANTS
  # ============================================================================

  # User statuses
  def user_status_pending, do: @user_status_pending
  def user_status_active, do: @user_status_active
  def user_status_inactive, do: @user_status_inactive
  def user_status_suspended, do: @user_status_suspended
  def valid_user_statuses, do: @valid_user_statuses

  # Student statuses
  def student_status_pending, do: @student_status_pending
  def student_status_profile_incomplete, do: @student_status_profile_incomplete
  def student_status_unverified, do: @student_status_unverified
  def student_status_verified, do: @student_status_verified
  def student_status_active, do: @student_status_active
  def valid_student_statuses, do: @valid_student_statuses

  # Tenant statuses
  def tenant_status_active, do: @tenant_status_active
  def tenant_status_inactive, do: @tenant_status_inactive
  def tenant_status_suspended, do: @tenant_status_suspended
  def valid_tenant_statuses, do: @valid_tenant_statuses

  # Assessment statuses
  def assessment_status_draft, do: @assessment_status_draft
  def assessment_status_published, do: @assessment_status_published
  def assessment_status_active, do: @assessment_status_active
  def assessment_status_completed, do: @assessment_status_completed
  def assessment_status_archived, do: @assessment_status_archived
  def valid_assessment_statuses, do: @valid_assessment_statuses

  # Assessment types
  def assessment_type_quiz, do: @assessment_type_quiz
  def assessment_type_exam, do: @assessment_type_exam
  def assessment_type_assignment, do: @assessment_type_assignment
  def assessment_type_project, do: @assessment_type_project
  def assessment_type_practice, do: @assessment_type_practice
  def assessment_type_behavioural, do: @assessment_type_behavioural
  def valid_assessment_types, do: @valid_assessment_types

  # Attempt statuses
  def attempt_status_started, do: @attempt_status_started
  def attempt_status_in_progress, do: @attempt_status_in_progress
  def attempt_status_submitted, do: @attempt_status_submitted
  def attempt_status_evaluated, do: @attempt_status_evaluated
  def attempt_status_completed, do: @attempt_status_completed
  def valid_attempt_statuses, do: @valid_attempt_statuses

  # User roles
  def role_admin, do: @role_admin
  def role_instructor, do: @role_instructor
  def role_student, do: @role_student
  def role_superadmin, do: @role_superadmin
  def valid_user_roles, do: @valid_user_roles

  # Affiliation types
  def affiliation_type_university, do: @affiliation_type_university
  def affiliation_type_college, do: @affiliation_type_college
  def affiliation_type_school, do: @affiliation_type_school
  def affiliation_type_institute, do: @affiliation_type_institute
  def affiliation_type_corporate, do: @affiliation_type_corporate
  def valid_affiliation_types, do: @valid_affiliation_types

  # User types
  def user_type_admin, do: @user_type_admin
  def user_type_user, do: @user_type_user
  def user_type_student, do: @user_type_student
  def valid_user_types, do: @valid_user_types

  # Creator types
  def creator_type_public, do: @creator_type_public
  def creator_type_tenant, do: @creator_type_tenant
  def valid_creator_types, do: @valid_creator_types

  # Email templates
  def email_template_welcome, do: @email_template_welcome
  def email_template_password_reset, do: @email_template_password_reset
  def email_template_profile_completion, do: @email_template_profile_completion
  def email_template_profile_approved, do: @email_template_profile_approved
  def email_template_profile_edit_request, do: @email_template_profile_edit_request
  def email_template_tenant_creation, do: @email_template_tenant_creation
  def valid_email_templates, do: @valid_email_templates

  # Token expiration times
  def password_reset_token_expiry, do: @password_reset_token_expiry
  def profile_completion_token_expiry, do: @profile_completion_token_expiry
  def temp_password_expiry, do: @temp_password_expiry

  # Validation constants
  def max_email_length, do: @max_email_length
  def max_name_length, do: @max_name_length
  def max_phone_length, do: @max_phone_length
  def max_description_length, do: @max_description_length
  def max_title_length, do: @max_title_length
  def min_password_length, do: @min_password_length
  def max_password_length, do: @max_password_length
  def max_token_length, do: @max_token_length
  def max_url_length, do: @max_url_length

  # Database constants
  def tenant_schema_prefix, do: @tenant_schema_prefix
  def public_schema, do: @public_schema

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  @doc """
  Safely converts string keys to atoms with validation.
  Prevents atom table DoS attacks by limiting key length and validating input.
  """
  def safe_atom_conversion(attrs) when is_map(attrs) do
    attrs
    |> Enum.filter(fn {k, _v} ->
      # Only convert string keys that are reasonable length and safe
      # Only allow alphanumeric characters and underscores for safety
      is_binary(k) and byte_size(k) <= 50 and String.valid?(k) and
        String.match?(k, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)
    end)
    |> Enum.map(fn {k, v} ->
      # Use String.to_existing_atom for safety, fallback to string key if atom doesn't exist
      try do
        atom = String.to_existing_atom(k)
        {atom, v}
      rescue
        # Keep as string key if atom doesn't exist
        ArgumentError -> {k, v}
      end
    end)
    |> Enum.into(%{})
  end

  def safe_atom_conversion(attrs), do: attrs

  @doc """
  Validates if a status is valid for a given type.
  """
  def valid_status?(status, :user), do: status in @valid_user_statuses
  def valid_status?(status, :student), do: status in @valid_student_statuses
  def valid_status?(status, :tenant), do: status in @valid_tenant_statuses
  def valid_status?(status, :assessment), do: status in @valid_assessment_statuses
  def valid_status?(status, :attempt), do: status in @valid_attempt_statuses
  def valid_status?(_, _), do: false

  @doc """
  Validates if a type is valid for a given category.
  """
  def valid_type?(type, :assessment), do: type in @valid_assessment_types
  def valid_type?(type, :user_role), do: type in @valid_user_roles
  def valid_type?(type, :affiliation), do: type in @valid_affiliation_types
  def valid_type?(type, :user), do: type in @valid_user_types
  def valid_type?(type, :creator), do: type in @valid_creator_types
  def valid_type?(_, _), do: false
end
