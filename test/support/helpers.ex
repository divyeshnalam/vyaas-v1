defmodule VyaasaCampus.TestHelpers do
  @moduledoc """
  Test helpers for creating test data and common test operations.
  """

  import Plug.Conn, only: [put_req_header: 3]

  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.{Role, User, UserRole}
  alias VyaasaCampus.Schema.Assessments.Assessment
  alias VyaasaCampus.Schema.Platform.AdminUser
  alias VyaasaCampus.Schema.Students.Student
  alias VyaasaCampus.Schema.Tenants.{Tenant, TenantLocation}

  @tenant_schema "test"

  # ==================== SHARED TEST DATA ====================
  # These are created once and reused across tests to reduce connection pressure

  def get_shared_admin do
    case :ets.lookup(:test_data, :shared_admin) do
      [{:shared_admin, admin}] ->
        admin

      [] ->
        admin = insert_admin_user(%{email: "shared_admin@test.com"})
        :ets.insert(:test_data, {:shared_admin, admin})
        admin
    end
  end

  def get_shared_tenant do
    case :ets.lookup(:test_data, :shared_tenant) do
      [{:shared_tenant, tenant}] ->
        tenant

      [] ->
        admin = get_shared_admin()
        tenant = insert_tenant(%{alias: "shared_test"}, admin)
        :ets.insert(:test_data, {:shared_tenant, tenant})
        tenant
    end
  end

  def setup_shared_test_data do
    # Initialize ETS table for shared test data
    :ets.new(:test_data, [:set, :public, :named_table])

    # Create shared admin and tenant
    _admin = get_shared_admin()
    _tenant = get_shared_tenant()

    :ok
  end

  def cleanup_shared_test_data do
    # Clean up ETS table if it exists
    :ets.delete(:test_data)
  rescue
    ArgumentError -> :ok
  end

  # ==================== Platform Admin Helpers ====================

  def insert_admin_user(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        email: "admin#{System.unique_integer()}@test.com",
        password: "password123",
        first_name: "Admin",
        last_name: "User",
        role: "superadmin"
      })

    %AdminUser{}
    |> AdminUser.create_changeset(attrs)
    |> Repo.insert!(prefix: "public")
  end

  # ==================== Tenant Helpers ====================

  def insert_tenant(attrs \\ %{}, admin \\ nil) do
    # Use provided admin or get shared admin
    admin = admin || get_shared_admin()

    # Generate unique schema name to avoid conflicts
    unique_suffix = System.unique_integer([:positive])
    unique_alias = "test_uni_#{unique_suffix}"

    attrs =
      Enum.into(attrs, %{
        full_name: "Test University",
        short_name: "TestU",
        alias: unique_alias,
        schema_name: "tenant_#{unique_alias}",
        affiliation_type: "university",
        email: "info@test.edu",
        phone: "+1-555-0123",
        website_url: "https://test.edu",
        status: "active",
        created_by: admin.id
      })

    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert!(prefix: "public")
  end

  def insert_tenant_location(tenant, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Main Campus",
        address: "123 University Ave",
        city: "Test City",
        state: "TS",
        country: "Test Country",
        postal_code: "12345",
        is_primary: true,
        tenant_id: tenant.id
      })

    %TenantLocation{}
    |> TenantLocation.changeset(attrs)
    |> Repo.insert!(prefix: "public")
  end

  # ==================== User Management Helpers ====================

  def insert_role(tenant, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "instructor",
        display_name: "Instructor",
        tenant_id: tenant.id,
        created_by_id: Ecto.UUID.generate(),
        created_by_type: "public"
      })

    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert!(prefix: @tenant_schema)
  end

  def insert_user(tenant, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        email: "user#{System.unique_integer()}@test.com",
        first_name: "Test",
        last_name: "User",
        role: "instructor",
        tenant_id: tenant.id,
        created_by_id: Ecto.UUID.generate(),
        created_by_type: "public"
      })

    %User{}
    |> User.changeset(attrs)
    |> User.password_changeset(%{password: "password123"})
    |> Repo.insert!(prefix: @tenant_schema)
  end

  def insert_user_role(user, role) do
    attrs = %{
      user_id: user.id,
      role_id: role.id,
      assigned_by_id: Ecto.UUID.generate(),
      assigned_by_type: "public"
    }

    %UserRole{}
    |> UserRole.changeset(attrs)
    |> Repo.insert!(prefix: @tenant_schema)
  end

  # ==================== Student Helpers ====================

  def insert_student(tenant, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        email: "student#{System.unique_integer()}@test.com",
        first_name: "Test",
        last_name: "Student",
        phone: "+1-555-0123",
        registration_id: "STU#{System.unique_integer()}",
        degree: "Bachelor of Technology",
        specialization: "Computer Science",
        year_of_passing: 2026,
        cgpa: Decimal.new("8.5"),
        preferred_role: "Software Developer",
        tenant_id: tenant.id,
        created_by_id: Ecto.UUID.generate(),
        created_by_type: "public"
      })

    %Student{}
    |> Student.create_changeset(Map.put(attrs, :password, "password123"))
    |> Repo.insert!(prefix: @tenant_schema)
  end

  def insert_active_student(tenant, attrs \\ %{}) do
    student = insert_student(tenant, attrs)

    # Update to active status
    student
    |> Student.approval_changeset(%{
      status: "active",
      approved_by_id: Ecto.UUID.generate()
    })
    |> Repo.update!(prefix: @tenant_schema)
  end

  # ==================== Assessment Helpers ====================

  def insert_assessment(tenant, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "Test Assessment",
        description: "A test assessment for testing",
        assessment_type: "quiz",
        duration_minutes: 30,
        total_marks: 100,
        passing_marks: 40,
        weightage: Decimal.new("10.0"),
        tenant_id: tenant.id,
        created_by: Ecto.UUID.generate()
      })

    %Assessment{}
    |> Assessment.changeset(attrs)
    |> Repo.insert!(prefix: @tenant_schema)
  end

  def insert_published_assessment(tenant, attrs \\ %{}) do
    assessment = insert_assessment(tenant, attrs)

    # Publish the assessment
    assessment
    |> Assessment.publish_changeset(%{
      status: "published",
      time_period: %{
        "start_date" => DateTime.utc_now() |> DateTime.add(1, :hour),
        "end_date" => DateTime.utc_now() |> DateTime.add(2, :hour)
      }
    })
    |> Repo.update!(prefix: @tenant_schema)
  end

  # ==================== Authentication Helpers ====================

  def authenticate_as(conn, user) do
    token = generate_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  def authenticate_as_admin(conn, admin) do
    token = generate_admin_token(admin)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  def authenticate_as_student(conn, student) do
    token = generate_student_token(student)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp generate_token(user) do
    case Guardian.encode_and_sign(user, %{user_type: "user", tenant_schema: @tenant_schema}) do
      {:ok, token, _claims} -> token
      {:ok, token} -> token
    end
  end

  defp generate_admin_token(admin) do
    case Guardian.encode_and_sign(admin, %{user_type: "admin"}) do
      {:ok, token, _claims} -> token
      {:ok, token} -> token
    end
  end

  defp generate_student_token(student) do
    case Guardian.encode_and_sign(student, %{user_type: "student", tenant_schema: @tenant_schema}) do
      {:ok, token, _claims} -> token
      {:ok, token} -> token
    end
  end

  # ==================== Setup Helpers ====================

  def setup_test_data do
    # Create platform admin
    admin = insert_admin_user()

    # Create tenant
    tenant = insert_tenant(%{}, admin)

    # Create tenant location
    location = insert_tenant_location(tenant)

    # Create role
    role = insert_role(tenant)

    # Create user
    user = insert_user(tenant)

    # Assign role to user
    user_role = insert_user_role(user, role)

    # Create student
    student = insert_student(tenant)

    # Create assessment
    assessment = insert_assessment(tenant)

    %{
      admin: admin,
      tenant: tenant,
      location: location,
      role: role,
      user: user,
      user_role: user_role,
      student: student,
      assessment: assessment
    }
  end

  # ==================== Cleanup Helpers ====================

  def cleanup_test_data do
    # Clean up tenant schema data (handle missing tables gracefully)
    try do
      Repo.query!("DELETE FROM \"#{@tenant_schema}\".students", [], prefix: @tenant_schema)
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM \"#{@tenant_schema}\".user_roles", [], prefix: @tenant_schema)
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM \"#{@tenant_schema}\".users", [], prefix: @tenant_schema)
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM \"#{@tenant_schema}\".roles", [], prefix: @tenant_schema)
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM \"#{@tenant_schema}\".assessments", [], prefix: @tenant_schema)
    rescue
      _ -> :ok
    end

    # Clean up public schema data (handle missing tables gracefully)
    try do
      Repo.query!("DELETE FROM public.tenant_locations", [], prefix: "public")
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM public.tenants", [], prefix: "public")
    rescue
      _ -> :ok
    end

    try do
      Repo.query!("DELETE FROM public.admin_users", [], prefix: "public")
    rescue
      _ -> :ok
    end
  end
end
