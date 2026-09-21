# VyaasaCampus Testing Guide

## Overview

This guide provides comprehensive testing strategies, procedures, and best practices for the VyaasaCampus multi-tenant educational platform. The testing framework includes unit tests, integration tests, end-to-end workflows, and automated testing scripts.

## Testing Architecture

```mermaid
graph TB
    subgraph "Testing Pyramid"
        E2E[End-to-End Tests]
        INT[Integration Tests]
        UNIT[Unit Tests]
        
        E2E --> INT
        INT --> UNIT
    end
    
    subgraph "Test Types"
        UT[Unit Tests]
        IT[Integration Tests]
        E2E2[E2E Workflows]
        MAN[Manual Testing]
        PERF[Performance Tests]
        SEC[Security Tests]
    end
    
    subgraph "Test Tools"
        EX[ExUnit]
        PHT[Phoenix.ConnTest]
        ECTO[Ecto.Adapters.SQL.Sandbox]
        WAL[Wallaby]
        CRE[Credo]
        DIAL[Dialyxir]
        SOB[Sobelow]
    end
    
    UT --> EX
    IT --> PHT
    E2E2 --> WAL
    MAN --> ECTO
    PERF --> EX
    SEC --> SOB
```

## Test Structure

```
test/
├── unit/                           # Unit tests for individual modules
│   ├── auth/                      # Authentication logic tests
│   │   ├── auth_test.exs
│   │   ├── guardian_test.exs
│   │   └── scope_test.exs
│   ├── contexts/                  # Business logic tests
│   │   ├── accounts_test.exs
│   │   ├── assessments_test.exs
│   │   ├── students_test.exs
│   │   └── platform_test.exs
│   ├── mail/                      # Email service tests
│   │   ├── email_service_test.exs
│   │   └── templates_test.exs
│   └── schemas/                   # Database schema tests
│       ├── student_test.exs
│       ├── assessment_test.exs
│       └── user_test.exs
├── integration/                   # Integration tests for workflows
│   ├── auth/                      # Authentication flow tests
│   │   ├── login_flow_test.exs
│   │   ├── password_reset_test.exs
│   │   └── token_refresh_test.exs
│   ├── tenant/                    # Multi-tenant workflow tests
│   │   ├── tenant_creation_test.exs
│   │   ├── tenant_isolation_test.exs
│   │   └── tenant_migration_test.exs
│   └── student/                   # Student workflow tests
│       ├── onboarding_test.exs
│       ├── profile_completion_test.exs
│       └── assessment_flow_test.exs
├── web/                           # Web layer tests
│   ├── controllers/               # API controller tests
│   │   ├── auth_controller_test.exs
│   │   ├── student_controller_test.exs
│   │   └── assessment_controller_test.exs
│   ├── plugs/                     # Plug middleware tests
│   │   ├── auth_plug_test.exs
│   │   ├── tenant_plug_test.exs
│   │   └── scope_plug_test.exs
│   └── live_view/                 # LiveView tests
│       ├── student_dashboard_test.exs
│       └── admin_panel_test.exs
├── support/                       # Test utilities and helpers
│   ├── conn_case.ex              # HTTP connection test setup
│   ├── data_case.ex              # Database test setup
│   ├── helpers.ex                # Test data factories
│   └── tenant_case.ex            # Multi-tenant test setup
└── test_helper.exs               # Test configuration
```

## Test Configuration

### Test Helper Setup

**test/test_helper.exs**:
```elixir
ExUnit.start()

# Configure Ecto for testing
Ecto.Adapters.SQL.Sandbox.mode(VyaasaCampus.Repo, :manual)

# Configure test environment
Application.put_env(:vyaasa_campus, :test_mode, true)

# Start test processes
{:ok, _} = Application.ensure_all_started(:ex_machina)
```

### Database Test Setup

**test/support/data_case.ex**:
```elixir
defmodule VyaasaCampus.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias VyaasaCampus.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import VyaasaCampus.DataCase
      import VyaasaCampus.TestHelpers
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(VyaasaCampus.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(VyaasaCampus.Repo, {:shared, self()})
    end

    :ok
  end
end
```

### Multi-Tenant Test Setup

**test/support/tenant_case.ex**:
```elixir
defmodule VyaasaCampus.TenantCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import VyaasaCampus.TenantCase
      import VyaasaCampus.TestHelpers
    end
  end

  setup tags do
    # Create test tenant schema
    tenant_schema = "tenant_test_#{System.unique_integer([:positive])}"
    
    # Run tenant migrations
    Ecto.Migrator.run(VyaasaCampus.Repo, :up, 
      to: Ecto.Migrator.migrations(VyaasaCampus.Repo, "priv/repo/tenant_migrations"))
    
    # Set tenant context
    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkin(VyaasaCampus.Repo)
    end)

    {:ok, tenant_schema: tenant_schema}
  end
end
```

## Test Data Factories

### Test Helpers

**test/support/helpers.ex**:
```elixir
defmodule VyaasaCampus.TestHelpers do
  @moduledoc """
  Test data factories and helper functions.
  """

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Contexts.{Accounts, Platform, Students}

  # Platform Admin Factory
  def platform_admin_factory do
    %{
      email: "admin@vyaasa.com",
      password: "admin123",
      first_name: "Platform",
      last_name: "Admin",
      role: "super_admin"
    }
  end

  # Tenant Factory
  def tenant_factory do
    %{
      full_name: "Test University",
      short_name: "Test Uni",
      alias: "test_uni_#{System.unique_integer([:positive])}",
      affiliation_type: "university",
      email: "admin@testuni.edu",
      phone: "+1-555-0123",
      website_url: "https://testuni.edu"
    }
  end

  # Student Factory
  def student_factory(attrs \\ %{}) do
    default_attrs = %{
      email: "student@testuni.edu",
      first_name: "John",
      last_name: "Doe",
      phone: "+1-555-0124",
      registration_id: "STU#{System.unique_integer([:positive])}",
      degree: "Bachelor of Technology",
      specialization: "Computer Science",
      year_of_passing: 2024,
      cgpa: 8.5,
      tenant_id: "test-tenant-id"
    }

    attrs = Enum.into(attrs, default_attrs)
    Students.create_student(attrs)
  end

  # Assessment Factory
  def assessment_factory(attrs \\ %{}) do
    default_attrs = %{
      title: "Test Assessment",
      description: "A test assessment",
      assessment_type: "quiz",
      duration_minutes: 30,
      total_marks: 100,
      passing_marks: 40,
      created_by: "test-user-id",
      tenant_id: "test-tenant-id"
    }

    attrs = Enum.into(attrs, default_attrs)
    Assessments.create_assessment(attrs)
  end

  # JWT Token Factory
  def jwt_token_factory(user_type, user_id, tenant_id \\ nil) do
    claims = %{
      "sub" => user_id,
      "user_type" => user_type,
      "tenant_id" => tenant_id,
      "exp" => System.system_time(:second) + 3600
    }

    VyaasaCampus.Guardian.encode_and_sign(claims)
  end

  # Create test tenant with admin
  def create_test_tenant do
    {:ok, tenant} = Platform.create_tenant(tenant_factory())
    
    tenant_admin = %{
      email: "admin@#{tenant.alias}.edu",
      password: "admin123",
      first_name: "Tenant",
      last_name: "Admin",
      role: "admin",
      tenant_id: tenant.id
    }
    
    {:ok, admin} = Accounts.create_tenant_user(tenant_admin)
    {tenant, admin}
  end

  # Create test student
  def create_test_student(tenant_id) do
    student_attrs = student_factory() |> Map.put(:tenant_id, tenant_id)
    Students.create_student(student_attrs)
  end
end
```

## Unit Tests

### Authentication Tests

**test/unit/auth/auth_test.exs**:
```elixir
defmodule VyaasaCampus.AuthTest do
  use VyaasaCampus.DataCase, async: true
  import VyaasaCampus.TestHelpers

  alias VyaasaCampus.Auth

  describe "authenticate_platform_admin/2" do
    test "authenticates valid credentials" do
      {:ok, admin} = create_platform_admin(platform_admin_factory())
      
      assert {:ok, ^admin} = Auth.authenticate_platform_admin(admin.email, "admin123")
    end

    test "rejects invalid password" do
      {:ok, admin} = create_platform_admin(platform_admin_factory())
      
      assert {:error, :invalid_credentials} = 
        Auth.authenticate_platform_admin(admin.email, "wrong_password")
    end

    test "rejects non-existent user" do
      assert {:error, :invalid_credentials} = 
        Auth.authenticate_platform_admin("nonexistent@example.com", "password")
    end
  end

  describe "authenticate_tenant_user/3" do
    test "authenticates valid tenant user" do
      {tenant, admin} = create_test_tenant()
      
      assert {:ok, ^admin} = Auth.authenticate_tenant_user(admin.email, "admin123", tenant.alias)
    end

    test "rejects user from wrong tenant" do
      {tenant, admin} = create_test_tenant()
      {other_tenant, _} = create_test_tenant()
      
      assert {:error, :invalid_credentials} = 
        Auth.authenticate_tenant_user(admin.email, "admin123", other_tenant.alias)
    end
  end
end
```

### Context Tests

**test/unit/contexts/students_test.exs**:
```elixir
defmodule VyaasaCampus.Contexts.StudentsTest do
  use VyaasaCampus.DataCase, async: true
  import VyaasaCampus.TestHelpers

  alias VyaasaCampus.Contexts.Students

  describe "create_student/1" do
    test "creates student with valid attributes" do
      {tenant, _} = create_test_tenant()
      student_attrs = student_factory() |> Map.put(:tenant_id, tenant.id)
      
      assert {:ok, student} = Students.create_student(student_attrs)
      assert student.email == student_attrs.email
      assert student.tenant_id == tenant.id
    end

    test "validates required fields" do
      assert {:error, changeset} = Students.create_student(%{})
      assert "can't be blank" in errors_on(changeset).email
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "validates unique email per tenant" do
      {tenant, _} = create_test_tenant()
      student_attrs = student_factory() |> Map.put(:tenant_id, tenant.id)
      
      {:ok, _student} = Students.create_student(student_attrs)
      
      assert {:error, changeset} = Students.create_student(student_attrs)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "approve_student/2" do
    test "approves student profile" do
      {tenant, admin} = create_test_tenant()
      {:ok, student} = create_test_student(tenant.id)
      
      assert {:ok, approved_student} = Students.approve_student(student.id, admin.id)
      assert approved_student.status == "active"
      assert approved_student.profile_approved_at != nil
    end
  end
end
```

## Integration Tests

### Authentication Flow Tests

**test/integration/auth/login_flow_test.exs**:
```elixir
defmodule VyaasaCampus.Integration.Auth.LoginFlowTest do
  use VyaasaCampus.ConnCase
  import VyaasaCampus.TestHelpers

  describe "Platform Admin Login Flow" do
    test "successful login returns JWT token", %{conn: conn} do
      {:ok, admin} = create_platform_admin(platform_admin_factory())
      
      conn = post(conn, "/api/auth/platform-admin/login", %{
        email: admin.email,
        password: "admin123"
      })
      
      assert %{"token" => token, "user" => user} = json_response(conn, 200)
      assert user["email"] == admin.email
      assert user["user_type"] == "admin"
      assert is_binary(token)
    end

    test "failed login returns error", %{conn: conn} do
      conn = post(conn, "/api/auth/platform-admin/login", %{
        email: "nonexistent@example.com",
        password: "wrong_password"
      })
      
      assert %{"error" => "invalid_credentials"} = json_response(conn, 401)
    end
  end

  describe "Tenant User Login Flow" do
    test "successful tenant login with x-tenant header", %{conn: conn} do
      {tenant, admin} = create_test_tenant()
      
      conn = conn
      |> put_req_header("x-tenant", tenant.alias)
      |> post("/api/auth/tenant-user/login", %{
        email: admin.email,
        password: "admin123"
      })
      
      assert %{"token" => token, "user" => user} = json_response(conn, 200)
      assert user["tenant_id"] == tenant.id
    end

    test "login fails without x-tenant header", %{conn: conn} do
      {_tenant, admin} = create_test_tenant()
      
      conn = post(conn, "/api/auth/tenant-user/login", %{
        email: admin.email,
        password: "admin123"
      })
      
      assert %{"error" => "tenant_header_required"} = json_response(conn, 400)
    end
  end
end
```

### Multi-Tenant Isolation Tests

**test/integration/tenant/tenant_isolation_test.exs**:
```elixir
defmodule VyaasaCampus.Integration.Tenant.IsolationTest do
  use VyaasaCampus.ConnCase
  import VyaasaCampus.TestHelpers

  describe "Tenant Data Isolation" do
    test "users cannot access other tenant data", %{conn: conn} do
      {tenant1, admin1} = create_test_tenant()
      {tenant2, admin2} = create_test_tenant()
      
      # Create student in tenant1
      {:ok, student1} = create_test_student(tenant1.id)
      
      # Try to access student1 from tenant2 admin
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("user", admin2.id, tenant2.id)}")
      |> put_req_header("x-tenant", tenant2.alias)
      |> get("/api/tenant/students/#{student1.id}")
      
      assert json_response(conn, 404)
    end

    test "platform admin can access all tenant data", %{conn: conn} do
      {:ok, platform_admin} = create_platform_admin(platform_admin_factory())
      {tenant, _} = create_test_tenant()
      {:ok, student} = create_test_student(tenant.id)
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("admin", platform_admin.id)}")
      |> get("/api/platform_admin/tenants/#{tenant.id}/students/#{student.id}")
      
      assert %{"student" => student_data} = json_response(conn, 200)
      assert student_data["id"] == student.id
    end
  end
end
```

## End-to-End Workflow Tests

### Student Onboarding Workflow

**test/integration/student/onboarding_test.exs**:
```elixir
defmodule VyaasaCampus.Integration.Student.OnboardingTest do
  use VyaasaCampus.ConnCase
  import VyaasaCampus.TestHelpers

  describe "Complete Student Onboarding Workflow" do
    test "student can complete full onboarding process", %{conn: conn} do
      {tenant, admin} = create_test_tenant()
      
      # Step 1: Admin creates student
      student_attrs = %{
        email: "newstudent@testuni.edu",
        first_name: "Jane",
        last_name: "Smith",
        phone: "+1-555-0125",
        registration_id: "STU001",
        degree: "Bachelor of Technology",
        specialization: "Computer Science",
        year_of_passing: 2024,
        cgpa: 8.0
      }
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("user", admin.id, tenant.id)}")
      |> put_req_header("x-tenant", tenant.alias)
      |> post("/api/tenant/students", %{student: student_attrs})
      
      assert %{"student" => student_data} = json_response(conn, 200)
      student_id = student_data["id"]
      
      # Step 2: Student completes profile
      profile_data = %{
        token: "profile_token_here",
        profile: %{
          resume_url: "https://example.com/resume.pdf",
          college_id_card_url: "https://example.com/id.jpg",
          profile_picture_url: "https://example.com/photo.jpg",
          preferred_role: "Software Engineer"
        }
      }
      
      conn = conn
      |> put_req_header("x-tenant", tenant.alias)
      |> post("/api/student/profile-completion/submit", profile_data)
      
      assert %{"message" => "Profile completed successfully"} = json_response(conn, 200)
      
      # Step 3: Admin approves student
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("user", admin.id, tenant.id)}")
      |> put_req_header("x-tenant", tenant.alias)
      |> post("/api/tenant/students/#{student_id}/approve", %{
        approval: %{admin_notes: "Profile looks good"}
      })
      
      assert %{"student" => approved_student} = json_response(conn, 200)
      assert approved_student["status"] == "active"
    end
  end
end
```

## API Controller Tests

### Student Controller Tests

**test/web/controllers/student_controller_test.exs**:
```elixir
defmodule VyaasaCampusWeb.StudentControllerTest do
  use VyaasaCampus.ConnCase
  import VyaasaCampus.TestHelpers

  describe "GET /api/student/assessments" do
    test "returns published assessments for student", %{conn: conn} do
      {tenant, admin} = create_test_tenant()
      {:ok, student} = create_test_student(tenant.id)
      {:ok, assessment} = create_assessment(%{
        title: "Math Quiz",
        status: "published",
        tenant_id: tenant.id,
        created_by: admin.id
      })
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("student", student.id, tenant.id)}")
      |> put_req_header("x-tenant", tenant.alias)
      |> get("/api/student/assessments")
      
      assert %{"assessments" => [assessment_data]} = json_response(conn, 200)
      assert assessment_data["id"] == assessment.id
    end

    test "does not return draft assessments", %{conn: conn} do
      {tenant, admin} = create_test_tenant()
      {:ok, student} = create_test_student(tenant.id)
      {:ok, _assessment} = create_assessment(%{
        title: "Draft Quiz",
        status: "draft",
        tenant_id: tenant.id,
        created_by: admin.id
      })
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("student", student.id, tenant.id)}")
      |> put_req_header("x-tenant", tenant.alias)
      |> get("/api/student/assessments")
      
      assert %{"assessments" => []} = json_response(conn, 200)
    end
  end
end
```

## Performance Tests

### Load Testing

**test/performance/load_test.exs**:
```elixir
defmodule VyaasaCampus.Performance.LoadTest do
  use ExUnit.Case, async: false
  import VyaasaCampus.TestHelpers

  @concurrent_users 100
  @requests_per_user 10

  test "handles concurrent student logins" do
    {tenant, _} = create_test_tenant()
    
    # Create multiple students
    students = for i <- 1..@concurrent_users do
      {:ok, student} = create_test_student(tenant.id)
      student
    end
    
    # Simulate concurrent logins
    tasks = for student <- students do
      Task.async(fn ->
        for _ <- 1..@requests_per_user do
          # Simulate login request
          {:ok, _token} = Auth.authenticate_student(student.email, "password", tenant.alias)
        end
      end)
    end
    
    # Wait for all tasks to complete
    results = Task.await_many(tasks, 30_000)
    
    # Verify all requests succeeded
    assert length(results) == @concurrent_users
  end
end
```

## Security Tests

### Authentication Security Tests

**test/security/auth_security_test.exs**:
```elixir
defmodule VyaasaCampus.Security.AuthSecurityTest do
  use VyaasaCampus.ConnCase
  import VyaasaCampus.TestHelpers

  describe "JWT Token Security" do
    test "rejects expired tokens", %{conn: conn} do
      expired_claims = %{
        "sub" => "user_id",
        "exp" => System.system_time(:second) - 3600  # Expired 1 hour ago
      }
      
      {:ok, expired_token, _} = VyaasaCampus.Guardian.encode_and_sign(expired_claims)
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{expired_token}")
      |> get("/api/auth/me")
      
      assert json_response(conn, 401)
    end

    test "rejects malformed tokens", %{conn: conn} do
      conn = conn
      |> put_req_header("authorization", "Bearer invalid_token")
      |> get("/api/auth/me")
      
      assert json_response(conn, 401)
    end

    test "rejects tokens without proper claims", %{conn: conn} do
      invalid_claims = %{"sub" => "user_id"}  # Missing required claims
      
      {:ok, invalid_token, _} = VyaasaCampus.Guardian.encode_and_sign(invalid_claims)
      
      conn = conn
      |> put_req_header("authorization", "Bearer #{invalid_token}")
      |> get("/api/auth/me")
      
      assert json_response(conn, 401)
    end
  end

  describe "Tenant Isolation Security" do
    test "prevents cross-tenant data access", %{conn: conn} do
      {tenant1, admin1} = create_test_tenant()
      {tenant2, _admin2} = create_test_tenant()
      
      # Try to access tenant1 data with tenant2 credentials
      conn = conn
      |> put_req_header("authorization", "Bearer #{jwt_token_factory("user", admin1.id, tenant2.id)}")
      |> put_req_header("x-tenant", tenant2.alias)
      |> get("/api/tenant/students")
      
      # Should return empty results, not tenant1 data
      assert %{"students" => []} = json_response(conn, 200)
    end
  end
end
```

## Test Scripts

### Automated Test Scripts

The project includes interactive shell scripts for testing complete workflows:

**scripts/1_tenant_setup.sh**:
```bash
#!/bin/bash
# Test tenant creation and setup workflow

echo "Testing Tenant Setup Workflow..."

# Test platform admin login
echo "1. Testing platform admin login..."
PLATFORM_TOKEN=$(curl -s -X POST http://localhost:4000/api/auth/platform-admin/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@vyaasa.com", "password": "admin123"}' | \
  jq -r '.token')

if [ "$PLATFORM_TOKEN" = "null" ]; then
  echo "❌ Platform admin login failed"
  exit 1
fi
echo "✅ Platform admin login successful"

# Test tenant creation
echo "2. Testing tenant creation..."
TENANT_RESPONSE=$(curl -s -X POST http://localhost:4000/api/platform_admin/tenants \
  -H "Authorization: Bearer $PLATFORM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant": {
      "full_name": "Test University",
      "short_name": "Test Uni",
      "alias": "test_uni",
      "affiliation_type": "university",
      "email": "admin@testuni.edu"
    }
  }')

TENANT_ID=$(echo $TENANT_RESPONSE | jq -r '.tenant.id')
if [ "$TENANT_ID" = "null" ]; then
  echo "❌ Tenant creation failed"
  exit 1
fi
echo "✅ Tenant created successfully: $TENANT_ID"

echo "🎉 Tenant setup workflow completed successfully!"
```

## Running Tests

### Basic Test Commands

```bash
# Run all tests
mix test

# Run specific test categories
mix test test/unit/
mix test test/integration/
mix test test/web/

# Run specific test file
mix test test/unit/contexts/students_test.exs

# Run tests with coverage
mix test --cover

# Run tests with detailed output
mix test --trace

# Run tests in parallel (where safe)
mix test --max-failures 1
```

### Test Environment Setup

```bash
# Set up test database
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate

# Run tests
MIX_ENV=test mix test
```

### Continuous Integration

**GitHub Actions Example**:
```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: vyaasa_campus_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '25.0'
    
    - name: Set up Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18'
    
    - name: Install dependencies
      run: |
        mix deps.get
        cd assets && npm install
    
    - name: Run tests
      run: mix test
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost/vyaasa_campus_test
```

## Test Data Management

### Database Cleanup

```elixir
# test/support/data_case.ex
defmodule VyaasaCampus.DataCase do
  # ... existing code ...

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(VyaasaCampus.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(VyaasaCampus.Repo, {:shared, self()})
    end

    # Clean up test data
    on_exit(fn ->
      cleanup_test_data()
    end)

    :ok
  end

  defp cleanup_test_data do
    # Clean up any test-specific data
    VyaasaCampus.Repo.delete_all(VyaasaCampus.Schema.Students.Student)
    VyaasaCampus.Repo.delete_all(VyaasaCampus.Schema.Assessments.Assessment)
  end
end
```

### Test Data Factories

```elixir
# test/support/factories.ex
defmodule VyaasaCampus.Factories do
  use ExMachina.Ecto, repo: VyaasaCampus.Repo

  def platform_admin_factory do
    %VyaasaCampus.Schema.Platform.PlatformAdmin{
      email: sequence(:email, &"admin#{&1}@vyaasa.com"),
      encrypted_password: Bcrypt.hash_pwd_salt("password123"),
      first_name: "Platform",
      last_name: "Admin",
      role: "super_admin",
      status: "active"
    }
  end

  def tenant_factory do
    %VyaasaCampus.Schema.Tenants.Tenant{
      full_name: sequence(:full_name, &"University #{&1}"),
      short_name: sequence(:short_name, &"Uni#{&1}"),
      alias: sequence(:alias, &"uni_#{&1}"),
      affiliation_type: "university",
      email: sequence(:email, &"admin#{&1}@university.edu"),
      status: "active"
    }
  end
end
```

## Best Practices

### Test Organization

1. **Unit Tests**: Test individual functions and modules in isolation
2. **Integration Tests**: Test workflows and component interactions
3. **End-to-End Tests**: Test complete user journeys
4. **Performance Tests**: Test system performance under load
5. **Security Tests**: Test authentication and authorization

### Test Naming

```elixir
# Good test names
test "authenticates valid platform admin credentials"
test "rejects invalid password for existing user"
test "creates student with valid attributes"
test "validates unique email per tenant"

# Avoid vague test names
test "works"
test "does stuff"
test "test 1"
```

### Test Data

```elixir
# Use factories for consistent test data
def test "creates student" do
  student_attrs = student_factory()
  assert {:ok, student} = Students.create_student(student_attrs)
end

# Use meaningful test data
def test "validates email format" do
  invalid_attrs = %{email: "invalid-email"}
  assert {:error, changeset} = Students.create_student(invalid_attrs)
  assert "has invalid format" in errors_on(changeset).email
end
```

### Assertions

```elixir
# Use specific assertions
assert {:ok, student} = Students.create_student(attrs)
assert student.email == attrs.email
assert student.status == "pending"

# Avoid generic assertions
assert result  # Too vague
assert result != nil  # Better but still vague
```

## Debugging Tests

### Common Issues

1. **Database Connection Errors**:
   ```bash
   # Check if test database exists
   MIX_ENV=test mix ecto.create
   MIX_ENV=test mix ecto.migrate
   ```

2. **Async Test Issues**:
   ```elixir
   # Use :async: false for tests that modify global state
   use VyaasaCampus.DataCase, async: false
   ```

3. **Test Data Conflicts**:
   ```elixir
   # Use unique identifiers in test data
   email: "user#{System.unique_integer()}@example.com"
   ```

### Debug Commands

```bash
# Run specific test with detailed output
mix test test/unit/contexts/students_test.exs --trace

# Run tests with IEx
iex -S mix test

# Check test database
MIX_ENV=test mix ecto.migrate

# Reset test database
MIX_ENV=test mix ecto.reset
```

This comprehensive testing guide ensures the VyaasaCampus platform is thoroughly tested across all layers and scenarios.
