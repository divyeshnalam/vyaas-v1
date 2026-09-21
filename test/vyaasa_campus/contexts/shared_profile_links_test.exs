defmodule VyaasaCampus.Contexts.SharedProfileLinksTest do
  @moduledoc """
  Covers the short-slug replacement for the old `Phoenix.Token.sign/3`
  shared-profile link: `get_or_create_slug/2` must be idempotent (same
  student/tenant pair always gets the same slug back, no matter how many
  times "Share" is clicked or the QR code regenerated), and `resolve_slug/1`
  must correctly invert it.
  """
  use VyaasaCampus.DataCase

  alias VyaasaCampus.Contexts.SharedProfileLinks
  alias VyaasaCampus.Schema.Students.SharedProfileLink

  @tenant_schema "test"

  describe "get_or_create_slug/2" do
    test "mints a new slug for a student that doesn't have one yet" do
      student_id = Ecto.UUID.generate()

      slug = SharedProfileLinks.get_or_create_slug(student_id, @tenant_schema)

      assert is_binary(slug)
      assert String.length(slug) == 8

      assert Repo.get_by(SharedProfileLink, [slug: slug], prefix: "public")
    end

    test "returns the same slug on every subsequent call for the same student" do
      student_id = Ecto.UUID.generate()

      slug1 = SharedProfileLinks.get_or_create_slug(student_id, @tenant_schema)
      slug2 = SharedProfileLinks.get_or_create_slug(student_id, @tenant_schema)
      slug3 = SharedProfileLinks.get_or_create_slug(student_id, @tenant_schema)

      assert slug1 == slug2
      assert slug2 == slug3
    end

    test "different students in the same tenant get different slugs" do
      slug1 = SharedProfileLinks.get_or_create_slug(Ecto.UUID.generate(), @tenant_schema)
      slug2 = SharedProfileLinks.get_or_create_slug(Ecto.UUID.generate(), @tenant_schema)

      refute slug1 == slug2
    end

    test "the same student_id in two different tenants gets two different slugs" do
      student_id = Ecto.UUID.generate()

      slug1 = SharedProfileLinks.get_or_create_slug(student_id, "test")
      slug2 = SharedProfileLinks.get_or_create_slug(student_id, "other_tenant")

      refute slug1 == slug2
    end
  end

  describe "resolve_slug/1" do
    test "resolves an issued slug back to its student_id and tenant_schema" do
      student_id = Ecto.UUID.generate()
      slug = SharedProfileLinks.get_or_create_slug(student_id, @tenant_schema)

      assert {:ok, %{student_id: ^student_id, tenant_schema: @tenant_schema}} =
               SharedProfileLinks.resolve_slug(slug)
    end

    test "returns :error for an unknown slug" do
      assert :error = SharedProfileLinks.resolve_slug("nosuchslug")
    end
  end
end
