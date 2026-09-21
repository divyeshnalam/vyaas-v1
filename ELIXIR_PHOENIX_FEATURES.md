# Elixir/Phoenix Features Implementation Guide

## Overview

This document explains how VyaasaCampus leverages various Elixir and Phoenix features to build a robust, scalable multi-tenant educational platform. We utilize OTP principles, Phoenix's real-time capabilities, and Elixir's concurrency model to create a high-performance application.

## OTP (Open Telecom Platform) Features

### 1. **Supervision Trees**

#### Application Supervisor
```elixir
defmodule VyaasaCampus.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Database repository
      VyaasaCampus.Repo,
      
      # Web endpoint
      VyaasaCampusWeb.Endpoint,
      
      # Custom supervisors
      VyaasaCampus.Auth.AuthSupervisor,
      VyaasaCampus.Tenant.TenantSupervisor,
      
      # Background job processing
      {Oban, Application.fetch_env!(:vyaasa_campus, Oban)},
      
      # Telemetry metrics
      {TelemetryMetrics, VyaasaCampus.Telemetry.metrics()}
    ]

    opts = [strategy: :one_for_one, name: VyaasaCampus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Benefits:**
- **Fault Tolerance**: If any process crashes, only that process is restarted
- **Process Isolation**: Each component runs in its own process
- **Scalability**: Easy to add new supervised processes

#### Auth Supervisor
```elixir
defmodule VyaasaCampus.Auth.AuthSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      # Auth server for managing authentication state
      {VyaasaCampus.Auth.AuthServer, []},
      
      # Token cleanup worker
      {VyaasaCampus.Auth.TokenCleanupWorker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### 2. **GenServer for State Management**

#### Auth Server
```elixir
defmodule VyaasaCampus.Auth.AuthServer do
  use GenServer

  # Client API
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def authenticate(credentials) do
    GenServer.call(__MODULE__, {:authenticate, credentials})
  end

  def invalidate_token(token) do
    GenServer.cast(__MODULE__, {:invalidate_token, token})
  end

  # Server callbacks
  def init(_init_arg) do
    state = %{
      active_tokens: %{},
      failed_attempts: %{},
      rate_limits: %{}
    }
    {:ok, state}
  end

  def handle_call({:authenticate, credentials}, _from, state) do
    case VyaasaCampus.Auth.authenticate_user(credentials) do
      {:ok, user} ->
        token = generate_token(user)
        new_state = put_in(state.active_tokens[token], user.id)
        {:reply, {:ok, token, user}, new_state}
      
      {:error, reason} ->
        new_state = update_failed_attempts(state, credentials.email)
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_cast({:invalidate_token, token}, state) do
    new_state = update_in(state.active_tokens, &Map.delete(&1, token))
    {:noreply, new_state}
  end
end
```

**Benefits:**
- **State Management**: Centralized authentication state
- **Concurrency**: Handles multiple authentication requests safely
- **Persistence**: Maintains state across requests

### 3. **DynamicSupervisor for Tenant Management**

```elixir
defmodule VyaasaCampus.Tenant.TenantSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_tenant_worker(tenant_id) do
    child_spec = {VyaasaCampus.Tenant.TenantWorker, tenant_id}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_tenant_worker(tenant_id) do
    case Registry.lookup(VyaasaCampus.Tenant.Registry, tenant_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
```

**Benefits:**
- **Dynamic Scaling**: Start/stop tenant processes as needed
- **Resource Management**: Efficient resource utilization
- **Isolation**: Each tenant runs in its own process

### 4. **Registry for Process Discovery**

```elixir
defmodule VyaasaCampus.Tenant.Registry do
  use Registry, keys: :unique, name: __MODULE__

  def register_tenant(tenant_id, pid) do
    Registry.register(__MODULE__, tenant_id, pid)
  end

  def lookup_tenant(tenant_id) do
    Registry.lookup(__MODULE__, tenant_id)
  end
end
```

## Phoenix Features

### 1. **LiveView for Real-time UI**

#### Student Dashboard
```elixir
defmodule VyaasaCampusWeb.StudentDashboardLive do
  use VyaasaCampusWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(VyaasaCampus.PubSub, "student:#{socket.assigns.current_user.id}")
      Phoenix.PubSub.subscribe(VyaasaCampus.PubSub, "tenant:#{socket.assigns.current_user.tenant_id}")
    end

    socket = assign(socket, %{
      assessments: list_published_assessments(socket.assigns.current_user.tenant_id),
      profile: get_student_profile(socket.assigns.current_user.id),
      notifications: get_recent_notifications(socket.assigns.current_user.id)
    })

    {:ok, socket}
  end

  def handle_event("start_assessment", %{"assessment_id" => assessment_id}, socket) do
    case VyaasaCampus.Contexts.Assessments.start_assessment(
      assessment_id, 
      socket.assigns.current_user.id
    ) do
      {:ok, attempt} ->
        # Broadcast to other connected clients
        Phoenix.PubSub.broadcast(
          VyaasaCampus.PubSub,
          "tenant:#{socket.assigns.current_user.tenant_id}",
          {:assessment_started, attempt}
        )
        
        {:noreply, 
         socket
         |> put_flash(:info, "Assessment started successfully")
         |> push_navigate(to: ~p"/student/assessments/#{assessment_id}/attempt/#{attempt.id}")}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start assessment: #{reason}")}
    end
  end

  def handle_info({:assessment_published, assessment}, socket) do
    {:noreply, 
     update(socket, :assessments, fn assessments -> 
       [assessment | assessments] 
     end)}
  end

  def handle_info({:profile_approved, _profile}, socket) do
    {:noreply, 
     socket
     |> put_flash(:info, "Your profile has been approved!")
     |> assign(:profile, get_student_profile(socket.assigns.current_user.id))}
  end
end
```

**Benefits:**
- **Real-time Updates**: Automatic UI updates without page refresh
- **State Management**: Server-side state management
- **Performance**: Efficient DOM updates
- **User Experience**: Seamless interactions

### 2. **Phoenix Channels for WebSocket Communication**

#### Student Channel
```elixir
defmodule VyaasaCampusWeb.StudentChannel do
  use Phoenix.Channel

  def join("student:" <> student_id, _payload, socket) do
    if authorized?(socket, student_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("tenant:" <> tenant_id, _payload, socket) do
    if user_belongs_to_tenant?(socket.assigns.current_user, tenant_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("assessment_started", payload, socket) do
    # Broadcast to all users in the tenant
    broadcast_from(socket, "assessment_update", payload)
    {:noreply, socket}
  end

  def handle_in("profile_updated", payload, socket) do
    # Notify admins about profile updates
    Phoenix.PubSub.broadcast(
      VyaasaCampus.PubSub,
      "tenant_admins:#{socket.assigns.current_user.tenant_id}",
      {:profile_updated, payload}
    )
    {:noreply, socket}
  end

  def handle_out("assessment_update", payload, socket) do
    push(socket, "assessment_update", payload)
    {:noreply, socket}
  end
end
```

**Benefits:**
- **Real-time Communication**: Instant messaging and updates
- **Scalability**: Handles thousands of concurrent connections
- **Bidirectional**: Client and server can send messages
- **Presence**: Track user presence and activity

### 3. **Phoenix PubSub for Event Broadcasting**

```elixir
defmodule VyaasaCampus.Events do
  @moduledoc """
  Event broadcasting and handling for real-time features.
  """

  def broadcast_assessment_published(tenant_id, assessment) do
    Phoenix.PubSub.broadcast(
      VyaasaCampus.PubSub,
      "tenant:#{tenant_id}",
      {:assessment_published, assessment}
    )
  end

  def broadcast_profile_approved(student_id, tenant_id) do
    Phoenix.PubSub.broadcast(
      VyaasaCampus.PubSub,
      "student:#{student_id}",
      {:profile_approved, student_id}
    )
    
    Phoenix.PubSub.broadcast(
      VyaasaCampus.PubSub,
      "tenant_admins:#{tenant_id}",
      {:profile_approved, student_id}
    )
  end

  def broadcast_ats_processing_complete(student_id, results) do
    Phoenix.PubSub.broadcast(
      VyaasaCampus.PubSub,
      "student:#{student_id}",
      {:ats_processing_complete, results}
    )
  end
end
```

### 4. **Plug Pipeline for Request Processing**

#### Custom Plugs
```elixir
defmodule VyaasaCampusWeb.Plugs.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_auth_token(conn) do
      nil -> 
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"}) |> halt()
      token ->
        case VyaasaCampus.Guardian.resource_from_token(token) do
          {:ok, user, claims} -> 
            conn 
            |> assign(:current_user, user)
            |> assign(:current_claims, claims)
          {:error, _reason} -> 
            conn |> put_status(:unauthorized) |> json(%{error: "invalid_token"}) |> halt()
        end
    end
  end

  defp get_auth_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end

defmodule VyaasaCampusWeb.Plugs.TenantPlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-tenant") do
      [tenant_alias] ->
        case VyaasaCampus.Contexts.Platform.get_tenant_by_alias(tenant_alias) do
          {:ok, tenant} -> assign(conn, :current_tenant, tenant)
          {:error, _reason} -> 
            conn |> put_status(:bad_request) |> json(%{error: "invalid_tenant"}) |> halt()
        end
      [] ->
        conn |> put_status(:bad_request) |> json(%{error: "tenant_header_required"}) |> halt()
    end
  end
end
```

#### Router Configuration
```elixir
defmodule VyaasaCampusWeb.Router do
  use VyaasaCampusWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug VyaasaCampusWeb.Plugs.AuthPlug
  end

  pipeline :tenant_api do
    plug :accepts, ["json"]
    plug VyaasaCampusWeb.Plugs.AuthPlug
    plug VyaasaCampusWeb.Plugs.TenantPlug
  end

  scope "/api", VyaasaCampusWeb do
    pipe_through :api

    # Public endpoints
    post "/auth/platform-admin/login", AuthController, :platform_admin_login
    post "/auth/tenant-user/login", AuthController, :tenant_user_login
    post "/auth/student/login", AuthController, :student_login
  end

  scope "/api/tenant", VyaasaCampusWeb do
    pipe_through :tenant_api

    # Tenant-scoped endpoints
    resources "/students", StudentController
    resources "/assessments", AssessmentController
    resources "/users", UserController
  end
end
```

## Background Job Processing with Oban

### 1. **Job Definition**

```elixir
defmodule VyaasaCampus.Jobs.AtsResumeProcessor do
  use Oban.Worker, queue: :ats_processing, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"student_id" => student_id, "resume_url" => resume_url}}) do
    case VyaasaCampus.Contexts.Ats.process_resume(student_id, resume_url) do
      {:ok, result} -> 
        # Notify user of completion
        VyaasaCampus.Events.broadcast_ats_processing_complete(student_id, result)
        {:ok, result}
      
      {:error, reason} -> 
        {:error, reason}
    end
  end
end

defmodule VyaasaCampus.Jobs.EmailSender do
  use Oban.Worker, queue: :emails, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_type" => email_type, "recipient" => recipient, "data" => data}}) do
    case VyaasaCampus.Mail.EmailService.send_email(email_type, recipient, data) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### 2. **Job Scheduling**

```elixir
defmodule VyaasaCampus.Jobs.Scheduler do
  use Oban.Worker, queue: :scheduled

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_type" => "cleanup_expired_tokens"}}) do
    VyaasaCampus.Auth.cleanup_expired_tokens()
    :ok
  end

  def perform(%Oban.Job{args: %{"job_type" => "cleanup_old_ats_data"}}) do
    VyaasaCampus.Contexts.Ats.cleanup_old_data()
    :ok
  end
end
```

### 3. **Oban Configuration**

```elixir
# config/config.exs
config :vyaasa_campus, Oban,
  repo: VyaasaCampus.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Daily cleanup at 2 AM
       {"0 2 * * *", VyaasaCampus.Jobs.Scheduler, args: %{job_type: "cleanup_expired_tokens"}},
       # Weekly ATS data cleanup
       {"0 3 * * 0", VyaasaCampus.Jobs.Scheduler, args: %{job_type: "cleanup_old_ats_data"}}
     ]}
  ],
  queues: [
    default: 10,
    emails: 5,
    ats_processing: 3,
    cleanup: 1
  ]
```

## Telemetry and Monitoring

### 1. **Custom Telemetry Events**

```elixir
defmodule VyaasaCampus.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      
      # Database metrics
      summary("vyaasa_campus.repo.query.total_time",
        unit: {:native, :millisecond}
      ),
      counter("vyaasa_campus.repo.query.count"),
      
      # Custom application metrics
      counter("vyaasa_campus.auth.login.count"),
      counter("vyaasa_campus.auth.login.failed.count"),
      counter("vyaasa_campus.tenant.created.count"),
      counter("vyaasa_campus.student.registered.count"),
      counter("vyaasa_campus.assessment.started.count"),
      counter("vyaasa_campus.assessment.completed.count"),
      
      # ATS processing metrics
      counter("vyaasa_campus.ats.processing.started.count"),
      counter("vyaasa_campus.ats.processing.completed.count"),
      counter("vyaasa_campus.ats.processing.failed.count"),
      summary("vyaasa_campus.ats.processing.duration",
        unit: {:native, :millisecond}
      ),
      
      # JAM session metrics
      counter("vyaasa_campus.jam.session.created.count"),
      counter("vyaasa_campus.jam.session.completed.count"),
      summary("vyaasa_campus.jam.session.duration",
        unit: {:native, :millisecond}
      )
    ]
  end
end
```

### 2. **Telemetry Event Emission**

```elixir
defmodule VyaasaCampus.Contexts.Auth do
  def authenticate_user(credentials) do
    :telemetry.span([:vyaasa_campus, :auth, :login], %{email: credentials.email}, fn ->
      case do_authenticate(credentials) do
        {:ok, user} = result ->
          :telemetry.execute([:vyaasa_campus, :auth, :login], %{success: 1}, %{user_id: user.id})
          {result, %{user_id: user.id}}
        
        {:error, reason} = result ->
          :telemetry.execute([:vyaasa_campus, :auth, :login, :failed], %{failure: 1}, %{reason: reason})
          {result, %{reason: reason}}
      end
    end)
  end
end
```

## Ecto and Database Features

### 1. **Multi-tenant Queries**

```elixir
defmodule VyaasaCampus.Contexts.Tenant.Schema do
  alias VyaasaCampus.Repo

  def query_in_tenant(schema_name, queryable) do
    Repo.all(queryable, prefix: schema_name)
  end

  def get_in_tenant(schema_name, queryable, id) do
    Repo.get(queryable, id, prefix: schema_name)
  end

  def insert_in_tenant(schema_name, changeset) do
    Repo.insert(changeset, prefix: schema_name)
  end

  def update_in_tenant(schema_name, changeset) do
    Repo.update(changeset, prefix: schema_name)
  end

  def delete_in_tenant(schema_name, struct) do
    Repo.delete(struct, prefix: schema_name)
  end

  def transaction_in_tenant(schema_name, fun) do
    Repo.transaction(fun, prefix: schema_name)
  end
end
```

### 2. **Custom Ecto Types**

```elixir
defmodule VyaasaCampus.Types do
  @moduledoc """
  Custom Ecto types for the application.
  """

  defmodule EncryptedBinary do
    @behaviour Ecto.Type

    def type, do: :binary

    def cast(value) when is_binary(value), do: {:ok, value}
    def cast(_), do: :error

    def load(value) when is_binary(value) do
      {:ok, decrypt(value)}
    end

    def dump(value) when is_binary(value) do
      {:ok, encrypt(value)}
    end

    defp encrypt(value), do: :crypto.crypto_one_time(:aes_256_gcm, key(), value, true)
    defp decrypt(value), do: :crypto.crypto_one_time(:aes_256_gcm, key(), value, false)
    defp key, do: Application.get_env(:vyaasa_campus, :encryption_key)
  end

  defmodule UserType do
    @behaviour Ecto.Type

    def type, do: :string

    def cast("admin"), do: {:ok, :admin}
    def cast("user"), do: {:ok, :user}
    def cast("student"), do: {:ok, :student}
    def cast(_), do: :error

    def load(value), do: {:ok, String.to_atom(value)}
    def dump(value), do: {:ok, Atom.to_string(value)}
  end
end
```

### 3. **Database Migrations with Triplex**

```elixir
# Public migration
defmodule VyaasaCampus.Repo.Migrations.CreatePublicTables do
  use Ecto.Migration

  def change do
    create table(:platform_admins, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :encrypted_password, :string, null: false
      # ... other fields
    end

    create unique_index(:platform_admins, [:email])
  end
end

# Tenant migration
defmodule VyaasaCampus.Repo.TenantMigrations.CreateTenantTables do
  use Ecto.Migration

  def change do
    create table(:students, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :tenant_id, :uuid, null: false
      # ... other fields
    end

    create unique_index(:students, [:tenant_id, :email])
  end
end
```

## Guardian JWT Authentication

### 1. **Guardian Configuration**

```elixir
defmodule VyaasaCampus.Guardian do
  use Guardian, otp_app: :vyaasa_campus

  def subject_for_token(user, _claims) do
    {:ok, user.id}
  end

  def resource_from_claims(claims) do
    user_id = claims["sub"]
    user_type = claims["user_type"]
    tenant_id = claims["tenant_id"]
    
    case user_type do
      "admin" -> 
        VyaasaCampus.Contexts.Accounts.get_platform_admin(user_id)
      "user" -> 
        VyaasaCampus.Contexts.Accounts.get_tenant_user(user_id, tenant_id)
      "student" -> 
        VyaasaCampus.Contexts.Students.get_student(user_id, tenant_id)
    end
  end

  def build_claims(claims, resource, opts) do
    claims = Map.put(claims, "user_type", get_user_type(resource))
    claims = Map.put(claims, "tenant_id", resource.tenant_id)
    claims = Map.put(claims, "exp", System.system_time(:second) + opts[:ttl])
    {:ok, claims}
  end

  defp get_user_type(%VyaasaCampus.Schema.Platform.PlatformAdmin{}), do: "admin"
  defp get_user_type(%VyaasaCampus.Schema.Accounts.User{}), do: "user"
  defp get_user_type(%VyaasaCampus.Schema.Students.Student{}), do: "student"
end
```

### 2. **Token Generation and Validation**

```elixir
defmodule VyaasaCampus.Auth.TokenManager do
  def generate_token(user) do
    VyaasaCampus.Guardian.encode_and_sign(user, %{}, ttl: {30, :minutes})
  end

  def generate_refresh_token(user) do
    VyaasaCampus.Guardian.encode_and_sign(user, %{}, ttl: {30, :days})
  end

  def validate_token(token) do
    VyaasaCampus.Guardian.resource_from_token(token)
  end

  def refresh_token(refresh_token) do
    case VyaasaCampus.Guardian.resource_from_token(refresh_token) do
      {:ok, user, _claims} -> generate_token(user)
      {:error, _reason} -> {:error, :invalid_token}
    end
  end
end
```

## Performance Optimizations

### 1. **Connection Pooling**

```elixir
# config/config.exs
config :vyaasa_campus, VyaasaCampus.Repo,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
  pool_timeout: 30_000,
  timeout: 30_000,
  ownership_timeout: 30_000
```

### 2. **Query Optimization**

```elixir
defmodule VyaasaCampus.Contexts.Students do
  def list_students_with_assessments(tenant_id) do
    Student
    |> where([s], s.tenant_id == ^tenant_id)
    |> preload([:assessment_attempts, :ats_phases])
    |> Repo.all(prefix: get_tenant_schema(tenant_id))
  end

  def get_student_with_profile(student_id, tenant_id) do
    Student
    |> where([s], s.id == ^student_id and s.tenant_id == ^tenant_id)
    |> preload([:ats_phases, :assessment_attempts])
    |> Repo.one(prefix: get_tenant_schema(tenant_id))
  end
end
```

### 3. **Caching Strategy**

```elixir
defmodule VyaasaCampus.Cache do
  @moduledoc """
  Application-level caching for frequently accessed data.
  """

  def get_tenant_config(tenant_id) do
    case :ets.lookup(:tenant_cache, tenant_id) do
      [{^tenant_id, config}] -> {:ok, config}
      [] -> 
        case VyaasaCampus.Contexts.Platform.get_tenant(tenant_id) do
          {:ok, tenant} -> 
            :ets.insert(:tenant_cache, {tenant_id, tenant})
            {:ok, tenant}
          error -> error
        end
    end
  end

  def invalidate_tenant_cache(tenant_id) do
    :ets.delete(:tenant_cache, tenant_id)
  end
end
```

This comprehensive implementation showcases how VyaasaCampus leverages Elixir and Phoenix features to create a robust, scalable, and maintainable multi-tenant educational platform. The combination of OTP principles, real-time capabilities, and Phoenix's web framework provides a solid foundation for building complex applications.
