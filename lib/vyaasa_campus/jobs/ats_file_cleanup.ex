defmodule VyaasaCampus.Jobs.AtsFileCleanup do
  @moduledoc """
  Scheduled job to clean up old ATS files and records based on retention policy.

  This job:
  - Marks old records for deletion based on retention_policy_days
  - Physically deletes files from filesystem for marked records
  - Runs periodically to maintain disk space

  Note: This job should be scheduled in your Oban configuration, not in the worker itself.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 3,
    priority: 0

  alias VyaasaCampus.Contexts.AtsUpload

  @impl Oban.Worker
  def perform(_job) do
    # Step 1: Mark expired records for deletion
    AtsUpload.mark_for_deletion_expired_files()

    # Step 2: Physically delete files for marked records
    AtsUpload.cleanup_deleted_files()

    {:ok, :cleanup_completed}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1h, 4h, 9h
    attempt * attempt * 60 * 60
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(1)
end
