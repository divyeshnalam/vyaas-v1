defmodule VyaasaCampusWeb.Controllers.API.Student.JamController do
  @moduledoc """
  JAM (Just A Minute) session controller for student endpoints.

  Handles JAM session lifecycle including:
  - Session creation and management
  - Topic decision workflow
  - Audio recording and processing
  - Results retrieval
  """

  use VyaasaCampusWeb, :controller

  import VyaasaCampusWeb.Shared.ControllerHelpers
  alias VyaasaCampus.Contexts.Jam
  require Logger

  # Create new JAM session
  def create(conn, %{"jam_session" => jam_session_params}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    jam_session_attrs =
      jam_session_params
      |> Map.put("student_id", current_user.id)
      |> Map.put("tenant_id", current_user.tenant_id)

    case Jam.create_jam_session(jam_session_attrs, tenant_schema) do
      {:ok, jam_session} ->
        # Call Python service to generate topic
        case Jam.generate_topic(jam_session, jam_session_params["preferences"] || %{}) do
          {:ok, _topic_response} ->
            conn
            |> put_status(:created)
            |> json(%{
              jam_session: %{
                id: jam_session.id,
                session_token: jam_session.session_token,
                status: jam_session.status,
                decision_time_seconds: jam_session.decision_time_seconds,
                preparation_time_seconds: jam_session.preparation_time_seconds,
                speech_time_seconds: jam_session.speech_time_seconds
              },
              message: "JAM session created successfully. Topic generation in progress."
            })

          {:error, reason} ->
            Logger.error("Failed to generate topic: #{inspect(reason)}")
            conn
            |> put_status(:created)
            |> json(%{
              jam_session: %{
                id: jam_session.id,
                session_token: jam_session.session_token,
                status: jam_session.status
              },
              message: "JAM session created but topic generation failed. Please try again.",
              warning: "Topic generation failed"
            })
        end

      {:error, changeset} ->
        handle_validation_error(conn, changeset)
    end
  end

  # Get JAM session details
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        if jam_session.student_id == current_user.id do
          conn
          |> json(%{
            jam_session: format_jam_session_response(jam_session)
          })
        else
          handle_forbidden(conn, "Access denied")
        end
    end
  end

  # Update JAM session (for status transitions)
  def update(conn, %{"id" => id, "jam_session" => jam_session_params}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        if jam_session.student_id == current_user.id do
          handle_jam_session_update(conn, jam_session, jam_session_params, tenant_schema)
        else
          handle_forbidden(conn, "Access denied")
        end
    end
  end

  # Start JAM session
  def start(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_start_session(conn, jam_session, current_user, tenant_schema)
    end
  end

  defp handle_start_session(conn, jam_session, current_user, tenant_schema) do
    if jam_session.student_id == current_user.id do
      case Jam.update_jam_session_status(jam_session, "topic_generated", tenant_schema) do
        {:ok, updated_session} ->
          conn
          |> json(%{
            jam_session: format_jam_session_response(updated_session),
            message: "JAM session started successfully"
          })

        {:error, changeset} ->
          handle_validation_error(conn, changeset)
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Decide on topic (accept or change)
  def decide_topic(conn, %{"id" => id, "decision" => decision_params}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_topic_decision(conn, jam_session, current_user, decision_params, tenant_schema)
    end
  end

  defp handle_topic_decision(conn, jam_session, current_user, decision_params, tenant_schema) do
    if jam_session.student_id == current_user.id do
      decision_attrs = %{
        topic_changed: decision_params["topic_changed"] || false,
        actual_decision_time_used: decision_params["actual_decision_time_used"]
      }

      case Jam.update_jam_session_decision(jam_session, decision_attrs, tenant_schema) do
        {:ok, updated_session} ->
          conn
          |> json(%{
            jam_session: format_jam_session_response(updated_session),
            message: "Topic decision recorded successfully"
          })

        {:error, changeset} ->
          handle_validation_error(conn, changeset)
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Start preparation phase
  def start_preparation(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_start_preparation(conn, jam_session, current_user, tenant_schema)
    end
  end

  defp handle_start_preparation(conn, jam_session, current_user, tenant_schema) do
    if jam_session.student_id == current_user.id do
      case Jam.start_preparation(jam_session, tenant_schema) do
        {:ok, updated_session} ->
          conn
          |> json(%{
            jam_session: format_jam_session_response(updated_session),
            message: "Preparation phase started"
          })

        {:error, changeset} ->
          handle_validation_error(conn, changeset)
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Start speaking phase
  def start_speaking(conn, %{"id" => id, "preparation_time_used" => preparation_time_used}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_start_speaking(conn, jam_session, current_user, preparation_time_used, tenant_schema)
    end
  end

  defp handle_start_speaking(conn, jam_session, current_user, preparation_time_used, tenant_schema) do
    if jam_session.student_id == current_user.id do
      case Jam.start_speaking(jam_session, preparation_time_used, tenant_schema) do
        {:ok, updated_session} ->
          conn
          |> json(%{
            jam_session: format_jam_session_response(updated_session),
            message: "Speaking phase started"
          })

        {:error, changeset} ->
          handle_validation_error(conn, changeset)
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Upload audio and complete speaking
  def upload_audio(conn, %{"id" => id, "audio_data" => audio_data}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_upload_audio(conn, jam_session, current_user, audio_data, tenant_schema)
    end
  end

  defp handle_upload_audio(conn, jam_session, current_user, audio_data, tenant_schema) do
    if jam_session.student_id == current_user.id do
      speech_time_used = audio_data["speech_time_used"]
      audio_attrs = %{
        recording_file_path: audio_data["recording_file_path"],
        recording_duration_seconds: audio_data["recording_duration_seconds"],
        audio_quality_score: audio_data["audio_quality_score"],
        noise_level: audio_data["noise_level"]
      }

      case Jam.complete_speaking(jam_session, speech_time_used, audio_attrs, tenant_schema) do
        {:ok, updated_session} ->
          # Process audio asynchronously
          Jam.process_jam_session_async(updated_session, audio_data, tenant_schema)

          conn
          |> json(%{
            jam_session: format_jam_session_response(updated_session),
            message: "Audio uploaded successfully. Processing in progress."
          })

        {:error, changeset} ->
          handle_validation_error(conn, changeset)
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Get JAM session status
  def status(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        if jam_session.student_id == current_user.id do
          conn
          |> json(%{
            status: jam_session.status,
            session_token: jam_session.session_token,
            updated_at: format_datetime_ist(jam_session.updated_at)
          })
        else
          handle_forbidden(conn, "Access denied")
        end
    end
  end

  # Get JAM session results
  def results(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user
    tenant_schema = get_tenant_schema_from_request(conn)

    case Jam.get_jam_session(id, tenant_schema) do
      nil ->
        handle_not_found(conn, "JAM session not found")

      jam_session ->
        handle_get_results(conn, jam_session, current_user)
    end
  end

  defp handle_get_results(conn, jam_session, current_user) do
    if jam_session.student_id == current_user.id do
      if jam_session.status == "completed" do
        conn
        |> json(%{
          jam_session: format_jam_session_response(jam_session),
          results: %{
            final_score: jam_session.final_score,
            clarity_score: jam_session.clarity_score,
            structure_score: jam_session.structure_score,
            relevance_score: jam_session.relevance_score,
            impact_score: jam_session.impact_score,
            confidence_score: jam_session.confidence_score,
            overall_summary: jam_session.overall_summary,
            transcript: jam_session.transcript,
            word_count: jam_session.word_count,
            speech_duration_seconds: jam_session.speech_duration_seconds,
            evaluation_data: jam_session.evaluation_data
          }
        })
      else
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Session not completed",
          message: "Results are only available for completed sessions",
          current_status: jam_session.status
        })
      end
    else
      handle_forbidden(conn, "Access denied")
    end
  end

  # Private helper functions

  defp handle_jam_session_update(conn, jam_session, params, tenant_schema) do
    case params["action"] do
      "start" ->
        Jam.update_jam_session_status(jam_session, "topic_generated", tenant_schema)

      "decide_topic" ->
        decision_attrs = %{
          topic_changed: params["topic_changed"] || false,
          actual_decision_time_used: params["actual_decision_time_used"]
        }
        Jam.update_jam_session_decision(jam_session, decision_attrs, tenant_schema)

      "start_preparation" ->
        Jam.start_preparation(jam_session, tenant_schema)

      "start_speaking" ->
        Jam.start_speaking(jam_session, params["preparation_time_used"], tenant_schema)

      _ ->
        {:error, %{errors: [action: {"Invalid action", []}]}}
    end
    |> case do
      {:ok, updated_session} ->
        conn
        |> json(%{
          jam_session: format_jam_session_response(updated_session),
          message: "JAM session updated successfully"
        })

      {:error, changeset} ->
        handle_validation_error(conn, changeset)
    end
  end

  defp format_jam_session_response(jam_session) do
    %{
      id: jam_session.id,
      session_token: jam_session.session_token,
      status: jam_session.status,
      topic_title: jam_session.topic_title,
      topic_explanation: jam_session.topic_explanation,
      topic_changed: jam_session.topic_changed,
      change_topic_available: jam_session.change_topic_available,
      decision_time_seconds: jam_session.decision_time_seconds,
      preparation_time_seconds: jam_session.preparation_time_seconds,
      speech_time_seconds: jam_session.speech_time_seconds,
      actual_decision_time_used: jam_session.actual_decision_time_used,
      actual_preparation_time_used: jam_session.actual_preparation_time_used,
      actual_speech_time_used: jam_session.actual_speech_time_used,
      recording_active: jam_session.recording_active,
      webrtc_connected: jam_session.webrtc_connected,
      audio_quality_score: jam_session.audio_quality_score,
      noise_level: jam_session.noise_level,
      created_at: format_datetime_ist(jam_session.inserted_at),
      updated_at: format_datetime_ist(jam_session.updated_at),
      completed_at: format_datetime_ist(jam_session.completed_at)
    }
  end

  defp handle_not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end

  defp handle_forbidden(conn, message) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: message})
  end
end
