defmodule VyaasaCampus.AuthTest do
  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Auth

  describe "authenticate_student/3" do
    @tag :shared_data
    test "rejects students before admin verification" do
      tenant = insert_tenant()
      insert_student(tenant, %{email: "pending_login@test.com", status: "unverified"})

      assert {:error, :student_not_verified} =
               Auth.authenticate_student("pending_login@test.com", "password123", "test")
    end

    @tag :shared_data
    test "allows verified students to login" do
      tenant = insert_tenant()
      insert_active_student(tenant, %{email: "verified_login@test.com"})

      assert {:ok, student} =
               Auth.authenticate_student("verified_login@test.com", "password123", "test")

      assert student.email == "verified_login@test.com"
    end
  end
end
