defmodule VyaasaCampus.ChangesetErrorInterpolationTest do
  @moduledoc """
  Four admin LiveViews (add_college_live, college_config_live, degrees_live,
  jobs_live) built their flash-message error text with
  `Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)` —
  discarding the interpolation opts. Any validation with a template
  variable (validate_number's %{number}, validate_length's %{count}, ...)
  rendered the raw, unsubstituted placeholder straight to the admin, e.g.
  "total_questions: must be greater than %{number}" instead of
  "must be greater than 0". Verified against a real changeset (not a
  synthetic one) since the bug is specifically about opts that Ecto's own
  validators attach, which a hand-built error tuple wouldn't reproduce.

  Pins the fixed interpolation snippet duplicated across all four files —
  not calling their (private) format_errors/changeset_errors functions
  directly, but the exact substitution logic each was changed to use.
  """

  use ExUnit.Case, async: true

  alias VyaasaCampus.Schema.Assessments.AssessmentConfig

  defp interpolate(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end

  test "validate_number's %{number} placeholder is substituted, not leaked" do
    changeset = AssessmentConfig.changeset(%AssessmentConfig{}, %{total_questions: 0})

    errors = interpolate(changeset)

    assert [message] = errors.total_questions
    assert message == "must be greater than 0"
    refute message =~ "%{"
  end

  test "the old (buggy) traverse_errors pattern does leak the placeholder, confirming the fix is real" do
    changeset = AssessmentConfig.changeset(%AssessmentConfig{}, %{total_questions: 0})

    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    assert [message] = errors.total_questions
    assert message =~ "%{number}"
  end
end
