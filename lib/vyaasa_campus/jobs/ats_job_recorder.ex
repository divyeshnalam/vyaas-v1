defmodule VyaasaCampus.Jobs.AtsJobRecorder do
  @moduledoc """
  Marks a student's ATS phase "errored" the moment Oban permanently gives up
  on its resume-scoring job — closing the loop that `Oban.Plugins.Lifeline`
  opens.

  Lifeline rescues a job orphaned by a node crash/restart mid-execution (state
  stuck at `executing`) back to `available` for a retry. If it keeps failing
  through all of `AtsResumeProcessor`'s `max_attempts`, Oban marks the job
  `discarded` — but nothing tells the student's `ats_phase` about that unless
  a live `perform/1` call happened to run
  `AtsUpload.update_processing_attempt/3` on its way out. A job that dies
  from a crash/orphan on every attempt never reaches that code, and the
  phase is left at status "processing"/"queued" forever with no explanation.

  This is a `:telemetry` handler on Oban's own job-lifecycle events, so it
  catches a discard regardless of *why* the job gave up — exhausted retries,
  a worker-initiated `{:discard, reason}`, or repeated Lifeline rescues.
  """

  require Logger

  alias VyaasaCampus.Contexts.StudentAts

  @handler_id "ats-job-recorder"
  @ats_queue "ats_processing"
  @terminal_statuses ~w(completed failed manual_review errored)

  @doc """
  Attach the handler. Called at application boot — idempotent (detaches any
  prior handler with the same id first) so a hot-reload or repeated
  Application.start/2 in tests can't raise on a duplicate attach.
  """
  def attach do
    :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      [[:oban, :job, :exception], [:oban, :job, :stop]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event(_event, _measurements, %{state: :discard, job: %{queue: @ats_queue} = job}, _config) do
    record_discard(job)
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  defp record_discard(%{args: %{"ats_phase_id" => ats_phase_id, "tenant_schema" => tenant_schema}}) do
    case StudentAts.get_by_id(ats_phase_id, tenant_schema) do
      nil ->
        :ok

      %{status: status} when status in @terminal_statuses ->
        :ok

      ats_phase ->
        Logger.warning(
          "ATS | Job for phase #{ats_phase_id} discarded — marking errored (was stuck at #{inspect(ats_phase.status)})"
        )

        StudentAts.update_status(ats_phase, "errored", tenant_schema)
        :ok
    end
  rescue
    e ->
      Logger.error("AtsJobRecorder failed to record a discard: #{Exception.message(e)}")
      :ok
  end

  defp record_discard(_job), do: :ok
end
