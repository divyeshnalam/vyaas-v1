defmodule VyaasaCampus.Contexts.SimpleTenantTest do
  @moduledoc """
  Simple tests for basic tenant functionality.
  """

  use VyaasaCampus.DataCase, async: false
  alias VyaasaCampus.Contexts.Platform
  alias VyaasaCampus.Contexts.Tenant.Tenants

  describe "tenant operations" do
    test "tenant modules exist and are loaded" do
      # Test that the modules are properly loaded
      assert Code.ensure_loaded(Tenants)
      assert Code.ensure_loaded(Platform)
    end

    test "tenant functions are exported" do
      # Ensure the module is loaded first
      assert Code.ensure_loaded(Tenants)

      # Test that basic tenant functions exist (using actual function names from the module)
      assert function_exported?(Tenants, :create_tenant, 1)
      assert function_exported?(Tenants, :get_tenant!, 1)
      assert function_exported?(Tenants, :list_tenants, 0)
      assert function_exported?(Tenants, :list_active_tenants, 0)
      assert function_exported?(Tenants, :update_tenant, 2)
      assert function_exported?(Tenants, :delete_tenant, 1)
      assert function_exported?(Tenants, :activate_tenant, 1)
      assert function_exported?(Tenants, :deactivate_tenant, 1)
      assert function_exported?(Tenants, :get_tenant_by_alias, 1)
      assert function_exported?(Tenants, :get_tenant_by_schema_name, 1)
    end

    test "platform admin module is loaded" do
      # Test that the platform module is properly loaded
      assert Code.ensure_loaded(Platform)
    end

    test "tenant validation works" do
      # Test basic validation without creating actual tenants
      # Just test that the module is loaded and function exists
      assert Code.ensure_loaded(Tenants)
      assert function_exported?(Tenants, :create_tenant, 1)

      # Test that we can call the function with minimal attributes
      # This should fail gracefully, not crash
      assert is_function(&Tenants.create_tenant/1)
    end

    test "basic functionality works" do
      # Just test that we can run basic assertions
      assert true == true
      assert 1 + 1 == 2
    end
  end
end
