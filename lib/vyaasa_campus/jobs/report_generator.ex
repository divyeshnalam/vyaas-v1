defmodule VyaasaCampus.Jobs.ReportGenerator do
  @moduledoc """
  Oban worker that generates an assessment report PDF and emails it to the
  student. Enqueued after an assessment is submitted; runs on the
  `:ai_reports` queue.

  ## Args
      %{
        "report_type" => "mcq",
        "attempt_id" => "uuid",
        "tenant_schema" => "tenant_abc",
        "tenant_alias" => "ABC"
      }
  """

  use Oban.Worker,
    queue: :ai_reports,
    max_attempts: 3,
    priority: 2,
    # Dedupe only against in-flight jobs: a double-submit while a report is still
    # pending/running won't enqueue twice, but a deliberate "Resend" after the job
    # has completed always creates a fresh job (and a fresh email).
    unique: [
      keys: [:report_type, :attempt_id],
      period: 300,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Mail.EmailOrchestrator
  alias VyaasaCampus.Reports

  # Human-readable email title per report type.
  @report_titles %{
    mcq: "MCQ Assessment Report",
    jam: "JAM Session Report",
    psychometric: "Personality (Big Five) Report",
    behavioral: "Behavioral Assessment Report",
    interview: "Interview Feedback Report",
    case_study: "Case Study Report",
    mini_project: "Mini Project Report",
    ai8: "AI8 Profile Report",
    resume: "Resume Analysis Report",
    employability_card: "Employability Card",
    certificate: "Vyaasa Certification"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, attempt: attempt, args: args}) do
    report_type = parse_type(args["report_type"])
    record_id = args["attempt_id"]
    tenant_schema = args["tenant_schema"]
    tenant_alias = args["tenant_alias"]

    Logger.info(
      "REPORT_JOB | start | job=#{job_id} attempt=#{attempt} type=#{report_type} " <>
        "record=#{record_id} tenant=#{tenant_schema} alias=#{inspect(tenant_alias)}"
    )

    with {:ok, context} <- Reports.load_context(report_type, record_id, tenant_schema),
         {:ok, pdf} <- Reports.generate_pdf(report_type, record_id, tenant_schema),
         {:ok, res} <- deliver(report_type, context, pdf, tenant_alias) do
      Logger.info("REPORT_JOB | done | job=#{job_id} type=#{report_type} result=#{inspect(res)}")
      :ok
    else
      {:error, reason} when reason in [:attempt_not_found, :not_found, :no_record] ->
        Logger.warning("REPORT_JOB | discard — record not found | job=#{job_id} type=#{report_type} record=#{record_id}")
        :discard

      {:error, reason} ->
        Logger.error("REPORT_JOB | FAILED | job=#{job_id} attempt=#{attempt} type=#{report_type} record=#{record_id} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Enqueues report generation + email delivery for a completed assessment record.
  `report_type` is any type supported by `Reports.load_context/3`; `record_id`
  is that type's primary key (mcq attempt, jam/interview session, behavioral or
  psychometric assessment, case_study session, …).
  """
  def enqueue(report_type, record_id, tenant_schema, tenant_alias) do
    %{
      "report_type" => to_string(report_type),
      "attempt_id" => to_string(record_id),
      "tenant_schema" => tenant_schema,
      "tenant_alias" => tenant_alias
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Fire-and-forget enqueue for use at a context's completion point. Derives the
  tenant alias from the schema and never raises — a failure to enqueue must not
  break the assessment submission (the student still sees their score).
  """
  def enqueue_safe(report_type, record_id, tenant_schema) do
    tenant_alias =
      case Tenants.get_tenant_by_schema_name(tenant_schema) do
        %{alias: a} -> a
        _ -> nil
      end

    case enqueue(report_type, record_id, tenant_schema, tenant_alias) do
      {:ok, %Oban.Job{id: id}} ->
        Logger.info("Report job enqueued: #{id} (#{report_type}/record=#{record_id})")

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue #{report_type} report job: #{inspect(reason)}")
    end

    :ok
  rescue
    e ->
      Logger.error("Exception enqueuing #{report_type} report job: #{inspect(e)}")
      :ok
  end

  # Generic delivery: every loader returns `context.student`; email is skipped
  # (not failed) when the student has no address on file.
  defp deliver(type, context, pdf, tenant_alias) do
    student = Map.get(context, :student)

    if is_nil(student) or is_nil(Map.get(student, :email)) do
      Logger.warning("REPORT_JOB | email skipped — student/email missing | type=#{type} student?=#{not is_nil(student)}")
      {:ok, :skipped}
    else
      Logger.info("REPORT_JOB | sending email | type=#{type} to=#{student.email} pdf_bytes=#{byte_size(pdf)}")
      result =
        EmailOrchestrator.send_report_email(student, pdf, %{
          report_type: type,
          report_title: Map.get(@report_titles, type, "Assessment Report"),
          assessment_title: assessment_title(type, context),
          tenant_alias: tenant_alias,
          filename: Reports.filename(type, context)
        })

      Logger.info("REPORT_JOB | email result | type=#{type} to=#{student.email} result=#{inspect(result)}")
      result
    end
  end

  # The specific assessment name shown in the email subject/body.
  defp assessment_title(:mcq, %{assessment: %{title: title}}) when is_binary(title), do: title
  defp assessment_title(:jam, %{session: %{topic_title: topic}}) when is_binary(topic), do: topic
  defp assessment_title(:psychometric, _), do: "Big Five Personality Assessment"
  defp assessment_title(:behavioral, _), do: "Behavioral Assessment"
  defp assessment_title(:interview, _), do: "Mock Interview"
  defp assessment_title(:case_study, _), do: "Case Study"
  defp assessment_title(:mini_project, %{role_title: role}) when is_binary(role), do: role
  defp assessment_title(:mini_project, _), do: "Domain Mini Project"
  defp assessment_title(:ai8, _), do: "AI8 Profile"
  defp assessment_title(:resume, _), do: "Resume Analysis"
  defp assessment_title(:employability_card, %{score: score}) when is_number(score), do: "AI8 Score: #{score}/100"
  defp assessment_title(:employability_card, _), do: "Employability Card"
  defp assessment_title(:certificate, %{score: score}) when is_number(score), do: "AI8 Score: #{score}/100"
  defp assessment_title(:certificate, _), do: "Certificate of Career Readiness"
  defp assessment_title(_, _), do: "your recent assessment"

  defp parse_type(type) when is_atom(type), do: type
  defp parse_type(other), do: String.to_existing_atom(to_string(other))

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # 30s, 120s, 270s
    attempt * attempt * 30
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)
end
