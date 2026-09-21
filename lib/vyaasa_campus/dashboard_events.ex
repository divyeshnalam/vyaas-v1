defmodule VyaasaCampus.DashboardEvents do
  @moduledoc """
  Centralized PubSub topics + subscribe / broadcast helpers used by the
  Super Admin, Tenant Admin and Student dashboards to receive real-time
  updates whenever the data they display is created, updated or deleted.

  Three audiences:
    * `tenants_topic/0`   — super admin (any tenant lifecycle change)
    * `tenant_topic/1`    — tenant admin (any change inside a tenant schema)
    * `student_topic/1`   — a student's personal dashboard

  All events are broadcast as `{:dashboard_event, payload}` so subscribers
  pattern-match a single message shape.
  """

  alias Phoenix.PubSub

  @pubsub VyaasaCampus.PubSub

  # ---- Topics ---------------------------------------------------------------

  def tenants_topic, do: "dashboard:tenants"

  def tenant_topic(schema_name) when is_binary(schema_name),
    do: "dashboard:tenant:#{schema_name}"

  def student_topic(student_id), do: "dashboard:student:#{student_id}"

  # ---- Subscribe (call from LiveView mount, guarded by connected?/1) -------

  def subscribe_tenants, do: PubSub.subscribe(@pubsub, tenants_topic())

  def subscribe_tenant(schema_name) when is_binary(schema_name),
    do: PubSub.subscribe(@pubsub, tenant_topic(schema_name))

  def subscribe_student(student_id),
    do: PubSub.subscribe(@pubsub, student_topic(student_id))

  # ---- Broadcasts -----------------------------------------------------------

  def broadcast_tenant_event(action, tenant) when action in [:created, :updated, :deleted] do
    publish(tenants_topic(), %{kind: :tenant, action: action, tenant_id: tenant.id})
  end

  def broadcast_student_event(action, schema_name, student_id)
      when action in [:created, :updated, :deleted] and is_binary(schema_name) do
    payload = %{kind: :student, action: action, student_id: student_id}
    publish(tenant_topic(schema_name), payload)
    publish(student_topic(student_id), payload)
  end

  def broadcast_assessment_event(action, schema_name, student_id)
      when is_binary(schema_name) do
    payload = %{kind: :assessment, action: action, student_id: student_id}
    publish(tenant_topic(schema_name), payload)
    publish(student_topic(student_id), payload)
  end

  def broadcast_ats_event(action, schema_name, student_id) when is_binary(schema_name) do
    payload = %{kind: :ats, action: action, student_id: student_id}
    publish(tenant_topic(schema_name), payload)
    publish(student_topic(student_id), payload)
  end

  def broadcast_session_event(kind, action, schema_name, student_id)
      when kind in [:interview, :jam, :behavioral, :psychometric, :case_study, :mini_project] and
             is_binary(schema_name) do
    payload = %{kind: kind, action: action, student_id: student_id}
    publish(tenant_topic(schema_name), payload)
    publish(student_topic(student_id), payload)
  end

  @doc """
  A module's AI8 evaluation was (re)published for a student.

  Broadcast from `Contexts.AI8.publish_evaluation/2` — the single point every
  one of the 8 modules flows through — so dashboards get exactly one reliable
  signal per scored assessment, *after* the row is written. Individual engines
  don't need their own broadcast for score changes.
  """
  def broadcast_ai8_event(schema_name, student_id, module)
      when is_binary(schema_name) and not is_nil(student_id) do
    payload = %{kind: :ai8, action: :published, student_id: student_id, module: module}
    publish(tenant_topic(schema_name), payload)
    publish(student_topic(student_id), payload)
  end

  def broadcast_ai8_event(_schema_name, _student_id, _module), do: :ok

  defp publish(topic, payload) do
    PubSub.broadcast(@pubsub, topic, {:dashboard_event, payload})
  end
end
