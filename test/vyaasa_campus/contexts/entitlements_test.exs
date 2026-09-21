defmodule VyaasaCampus.Contexts.EntitlementsTest do
  @moduledoc """
  Attempt-limit resolution: per-module override → global default → unlimited.

  These rules decide whether a student is let into an exam, so each branch is
  pinned explicitly — particularly that a *missing* entitlement means unlimited
  (so tenants are unaffected until configured) while an explicit 0 means blocked.
  """

  use VyaasaCampus.DataCase, async: false

  alias VyaasaCampus.Contexts.Entitlements

  describe "attempt_limit/2 resolution" do
    test "no entitlements at all means unlimited" do
      assert Entitlements.attempt_limit(%{}, :mcq) == nil
    end

    test "the global default applies to every module" do
      ent = %{"attempts.default" => 3}

      for module <- Entitlements.attempt_modules() do
        assert Entitlements.attempt_limit(ent, module) == 3
      end
    end

    test "a per-module override beats the default" do
      ent = %{"attempts.default" => 3, "attempts.mcq" => 5}

      assert Entitlements.attempt_limit(ent, :mcq) == 5
      assert Entitlements.attempt_limit(ent, :jam) == 3
    end

    test "an explicit zero blocks rather than falling through to the default" do
      ent = %{"attempts.default" => 3, "attempts.case_study" => 0}

      assert Entitlements.attempt_limit(ent, :case_study) == 0
    end

    test "a module with no override and no default is unlimited" do
      assert Entitlements.attempt_limit(%{"attempts.mcq" => 2}, :jam) == nil
    end

    test "accepts atom or string module names" do
      ent = %{"attempts.mini_project" => 1}

      assert Entitlements.attempt_limit(ent, :mini_project) == 1
      assert Entitlements.attempt_limit(ent, "mini_project") == 1
    end
  end

  describe "attempts_key/1" do
    test "nil and :default map to the global key" do
      assert Entitlements.attempts_key(:default) == "attempts.default"
      assert Entitlements.attempts_key(nil) == "attempts.default"
    end

    test "a module maps to its own key" do
      assert Entitlements.attempts_key("interview") == "attempts.interview"
    end
  end

  describe "attempt_modules/0" do
    test "covers all eight AI8 assessments" do
      assert length(Entitlements.attempt_modules()) == 8

      assert Enum.sort(Entitlements.attempt_modules()) ==
               Enum.sort(~w(resume mcq behavioral psychometric jam interview case_study mini_project))
    end
  end
end
