defmodule VyaasaCampus.Schema.Students.StudentAtsPhase do
  @moduledoc """
  Student ATS Phase schema for automated resume analysis.

  Stores the result of resume scoring (run by the native Elixir
  `VyaasaCampus.AI.ResumeScorer` pipeline). Used for profile completion and
  tenant-admin verification. Contains scoring metadata, parsed personal info,
  skills, work experience, education, and sanity-check results.
  """

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime]
  import Ecto.Changeset
  import VyaasaCampus.Types

  @derive {Jason.Encoder,
           only: [
             :id,
             :student_id,
             :resume_url,
             :status,
             :processed_at,
             :metadata,
             :personal_information,
             :portfolio_and_links,
             :professional_summary,
             :skills,
             :work_experience,
             :projects,
             :education,
             :certifications,
             :languages,
             :achievements_and_activities,
             :sanity_check,
             :extracted_raw_text_snippets,
             :preferred_role,
             :college_id_card_url,
             :profile_picture_url,
             :tenant_id,
             :ats_score,
             :processing_attempts,
             :attempt_number,
             :last_processing_error,
             :processor_metadata,
             :raw_result_json,
             :idempotency_key,
             :callback_received_at,
             :deleted_at,
             :retention_policy_days,
             :inserted_at,
             :updated_at
           ]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "student_ats_phases" do
    # References
    field :student_id, :binary_id
    field :tenant_id, :binary_id

    # Associations
    belongs_to :student, VyaasaCampus.Schema.Students.Student, foreign_key: :student_id, define_field: false

    # Resume Processing Info
    field :resume_url, :string
    # processing -> completed -> failed
    field :status, :string, default: "processing"
    field :processed_at, :utc_datetime

    # Student ATS Fields (moved from students table)
    field :preferred_role, :string
    field :college_id_card_url, :string
    field :profile_picture_url, :string

    # ATS Metadata (scoring and analysis)
    field :metadata, :map, default: %{}
    # Structure: %{
    #   "ts_score" => 76,
    #   "ts_score_max" => 100,
    #   "completeness_score" => 78,
    #   "completeness_score_max" => 100,
    #   "professionalism_score" => 90,
    #   "role_match_score" => 51,
    #   "role_match_breakdown" => %{
    #     "direct_skill_match_percent" => 40,
    #     "contextual_match_percent" => 26,
    #     "overall_similarity_percent" => 74
    #   },
    #   "areas_for_improvement" => %{
    #     "personal_info" => ["Location is missing"],
    #     "summary" => ["Professional Summary is missing"],
    #     "education" => ["Education Entry 1: CGPA is missing"],
    #     "certifications" => ["Not found"],
    #     "achievements" => ["Not found"],
    #     "languages" => ["Not found"]
    #   },
    #   "matching_keywords" => ["js", "scalable", "express", "node", ...],
    #   "missing_keywords" => ["responsible", "jenkins", "deploying", ...]
    # }

    # Personal Information
    field :personal_information, :map, default: %{}
    # Structure: %{
    #   "full_name" => "John Doe",
    #   "contact_number" => "+91XXXXXXXXXX",
    #   "email_address" => "john@example.com",
    #   "location" => "Hyderabad, India"
    # }

    # Portfolio and Links
    field :portfolio_and_links, :map, default: %{}
    # Structure: %{
    #   "linkedin" => "https://linkedin.com/in/...",
    #   "github" => "https://github.com/...",
    #   "other_links" => ["https://portfolio.com", "mailto:x@x.com", ...]
    # }

    # Professional Summary
    field :professional_summary, :map, default: %{}
    # Structure: %{
    #   "summary_text" => "Experienced developer with...",
    #   "total_experience" => "2 years"
    # }

    # Skills (extracted and categorized)
    field :skills, :map, default: %{}
    # Structure: %{
    #   "technical_skills" => ["js", "scalable", "express", "node", "git"],
    #   "non_technical_skills" => ["management", "efficient"],
    #   "other_mentioned_terms" => ["science", "computer", "on"]
    # }

    # Work Experience
    field :work_experience, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "job_index" => 1,
    #     "job_title" => "Software Developer Intern",
    #     "company_name" => "Tech Corp",
    #     "start_date" => "2023-01-01",
    #     "end_date" => "2023-06-30",
    #     "responsibilities" => "Developed web applications..."
    #   }
    # ]

    # Projects
    field :projects, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "project_index" => 1,
    #     "project_name" => "Smart Village Revolution - KLEF initiative",
    #     "technologies_used" => ["React", "Node.js", "MongoDB"],
    #     "description" => "A platform for rural development..."
    #   }
    # ]

    # Education
    field :education, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "education_index" => 1,
    #     "degree" => "Bachelor of Technology",
    #     "institution" => "KL University",
    #     "years" => "2020-2024",
    #     "specialization" => "Computer Science",
    #     "cgpa_or_percentage" => "8.5"
    #   }
    # ]

    # Certifications
    field :certifications, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "certification_name" => "AWS Certified Developer",
    #     "issuing_organization" => "Amazon Web Services",
    #     "issue_date" => "2023-06-01",
    #     "expiry_date" => "2026-06-01"
    #   }
    # ]

    # Languages
    field :languages, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "language" => "English",
    #     "proficiency" => "Native"
    #   }
    # ]

    # Achievements and Activities
    field :achievements_and_activities, {:array, :map}, default: []
    # Structure: [
    #   %{
    #     "achievement" => "Winner of Hackathon 2023",
    #     "description" => "Built an AI-powered solution..."
    #   }
    # ]

    # Sanity Check (validation and quality scores)
    field :sanity_check, :map, default: %{}
    # Structure: %{
    #   "professionalism_score" => 90,
    #   "notes" => "Well-structured resume with clear formatting"
    # }

    # Extracted Raw Text Snippets (for reference and debugging)
    field :extracted_raw_text_snippets, :map, default: %{}
    # Structure: %{
    #   "personal_info_raw" => ["Full Name", "Contact Number", ...],
    #   "links_raw" => ["mailto:x@x.com", "https://linkedin.com/in/...", ...],
    #   "professional_summary_raw" => ["Summary/Objective", "Total Experience"],
    #   "skills_raw" => ["js", "scalable", "express", ...],
    #   "work_experience_raw" => ["Job #1: Software Developer Intern", ...],
    #   "projects_raw" => ["Smart Village Revolution - KLEF initiative", ...],
    #   "education_raw" => ["Education #1: Bachelor of Technology"]
    # }

    # ATS Processing Fields
    field :ats_score, :decimal
    field :processing_attempts, :integer, default: 0
    # attempt_number: increments per re-analysis request to preserve history
    field :attempt_number, :integer, default: 1
    field :last_processing_error, :string
    field :processor_metadata, :map, default: %{}
    field :raw_result_json, :map, default: %{}
    field :idempotency_key, :string
    field :callback_received_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :retention_policy_days, :integer, default: 90

    timestamps()
  end

  @doc """
  Changeset for creating a new ATS phase record
  """
  def changeset(ats_phase, attrs) do
    ats_phase
    |> cast(attrs, [
      :student_id,
      :tenant_id,
      :resume_url,
      :status,
      :processed_at,
      :metadata,
      :personal_information,
      :portfolio_and_links,
      :professional_summary,
      :skills,
      :work_experience,
      :projects,
      :education,
      :certifications,
      :languages,
      :achievements_and_activities,
      :sanity_check,
      :extracted_raw_text_snippets,
      # Student ATS fields (moved from students table)
      :preferred_role,
      :college_id_card_url,
      :profile_picture_url,
      # ATS Processing Fields
      :ats_score,
      :processing_attempts,
      :attempt_number,
      :last_processing_error,
      :processor_metadata,
      :raw_result_json,
      :idempotency_key,
      :callback_received_at,
      :deleted_at,
      :retention_policy_days
    ])
    |> validate_required([:student_id, :tenant_id, :resume_url])
    |> validate_inclusion(:status, ["processing", "completed", "failed", "queued", "manual_review", "errored"])
    |> validate_length(:resume_url, max: max_url_length())
    |> validate_length(:college_id_card_url, max: max_url_length())
    |> validate_length(:profile_picture_url, max: max_url_length())
    |> validate_number(:ats_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:processing_attempts, greater_than_or_equal_to: 0)
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_number(:retention_policy_days, greater_than: 0)
    |> foreign_key_constraint(:student_id)
    |> unique_constraint([:student_id, :attempt_number],
         name: :student_ats_phases_student_id_attempt_index)
  end

  @doc """
  Changeset for creating ATS phase from ResumeScorer response
  """
  def create_from_service_changeset(ats_phase, service_data, student_id, tenant_id) do
    processed_attrs =
      base_attrs(student_id, tenant_id)
      |> Map.merge(extract_service_fields(service_data))
      |> Map.merge(extract_optional_fields(service_data))

    changeset(ats_phase, processed_attrs)
  end

  defp base_attrs(student_id, tenant_id) do
    %{
      student_id: student_id,
      tenant_id: tenant_id,
      status: "completed",
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp extract_service_fields(service_data) do
    extract_basic_fields(service_data)
    |> Map.merge(extract_profile_fields(service_data))
    |> Map.merge(extract_experience_fields(service_data))
    |> Map.merge(extract_analysis_fields(service_data))
  end

  defp extract_basic_fields(service_data) do
    %{
      resume_url: get_in(service_data, ["resume_url"]) || "",
      metadata: service_data["metadata"] || %{}
    }
  end

  defp extract_profile_fields(service_data) do
    %{
      personal_information: service_data["personal_information"] || %{},
      portfolio_and_links: normalize_portfolio(service_data),
      professional_summary: service_data["professional_summary"] || %{},
      skills: service_data["skills"] || %{}
    }
  end

  # Always store portfolio_and_links as a map (%{"other_links" => [...]}) — the
  # service sometimes returns `other_links` as a bare list, which broke readers
  # that expect a map.
  defp normalize_portfolio(service_data) do
    case service_data["portfolio_and_links"] || service_data["other_links"] do
      %{} = map -> map
      list when is_list(list) -> %{"other_links" => list}
      _ -> %{}
    end
  end

  defp extract_experience_fields(service_data) do
    %{
      work_experience: service_data["work_experience"] || [],
      projects: service_data["projects"] || [],
      education: service_data["education"] || [],
      certifications: service_data["certifications"] || [],
      languages: service_data["languages"] || [],
      achievements_and_activities: service_data["achievements_and_activities"] || []
    }
  end

  defp extract_analysis_fields(service_data) do
    %{
      sanity_check: service_data["sanity_check"] || %{},
      extracted_raw_text_snippets: service_data["extracted_raw_text_snippets"] || %{}
    }
  end

  defp extract_optional_fields(service_data) do
    %{
      preferred_role: service_data["preferred_role"],
      college_id_card_url: service_data["college_id_card_url"],
      profile_picture_url: service_data["profile_picture_url"]
    }
  end

  @doc """
  Changeset for updating processing status
  """
  @valid_statuses ["processing", "completed", "failed", "manual_review", "queued", "errored"]

  def status_changeset(ats_phase, status) when status in @valid_statuses do
    attrs = %{status: status}

    attrs =
      if status in ["completed", "failed", "manual_review"],
        do: Map.put(attrs, :processed_at, DateTime.utc_now() |> DateTime.truncate(:second)),
        else: attrs

    ats_phase
    |> cast(attrs, [:status, :processed_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Changeset for updating ATS fields during profile completion
  """
  def update_ats_fields_changeset(ats_phase, attrs) do
    ats_phase
    |> cast(attrs, [
      :preferred_role,
      :college_id_card_url,
      :profile_picture_url,
      :resume_url
    ])
    |> validate_length(:college_id_card_url, max: max_url_length())
    |> validate_length(:profile_picture_url, max: max_url_length())
    |> validate_length(:resume_url, max: max_url_length())
  end

  @doc """
  Get the overall ATS score from metadata or ats_score field
  """
  def get_overall_score(%__MODULE__{ats_score: ats_score}) when not is_nil(ats_score) do
    case ats_score do
      %Decimal{} -> Decimal.to_integer(ats_score)
      score when is_number(score) -> score
      _ -> 0
    end
  end

  def get_overall_score(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["ts_score"] || metadata["completeness_score"] || 0
  end

  def get_overall_score(_), do: 0

  @doc """
  Get the completeness score from metadata
  """
  def get_completeness_score(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["completeness_score"] || 0
  end

  def get_completeness_score(_), do: 0

  @doc """
  Get the professionalism score from metadata
  """
  def get_professionalism_score(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["professionalism_score"] || 0
  end

  def get_professionalism_score(_), do: 0

  @doc """
  Check if ATS processing is completed
  """
  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  @doc """
  Check if ATS processing failed
  """
  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false

  @doc """
  Check if ATS processing is still in progress
  """
  def processing?(%__MODULE__{status: "processing"}), do: true
  def processing?(_), do: false

  @doc """
  Get areas for improvement from metadata
  """
  def get_areas_for_improvement(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["areas_for_improvement"] || metadata["completeness_feedback"] || %{}
  end

  def get_areas_for_improvement(_), do: %{}

  @doc """
  Get matching keywords from metadata
  """
  def get_matching_keywords(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["matching_keywords"] || []
  end

  def get_matching_keywords(_), do: []

  @doc """
  Get missing keywords from metadata
  """
  def get_missing_keywords(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    metadata["missing_keywords"] || []
  end

  def get_missing_keywords(_), do: []
end
