# One-off cleanup for the question-bank cross-link bug (fixed in
# question_bank_live.ex's link_to_curricula/2): uploading a specialization
# with no existing `curricula` row used to fall back to linking the new
# subject into EVERY branch, including "Computer Science".
#
# This removes only the wrongly-added curricula_subjects rows — links between
# a subject and a curricula whose specialization does not match the subject's
# own specialization_id. Correct links (subject's spec == curricula's spec, or
# either side has no specialization at all — the legacy case) are left alone.
#
# Read-only report first; nothing is deleted unless you pass --apply.
#
#   mix run priv/scripts/fix_question_bank_crosslinks.exs           # dry run
#   mix run priv/scripts/fix_question_bank_crosslinks.exs --apply   # deletes

alias VyaasaCampus.Repo

apply? = "--apply" in System.argv()

{:ok, %{rows: bad_rows}} =
  Repo.query("""
    SELECT cs.subject_id, cs.curricula_id, s.name, sub_spec.name, c.name, cur_spec.name
    FROM public.curricula_subjects cs
    JOIN public.subjects s ON s.id = cs.subject_id
    JOIN public.curricula c ON c.id = cs.curricula_id
    LEFT JOIN public.specializations sub_spec ON sub_spec.id = s.specialization_id
    LEFT JOIN public.specializations cur_spec ON cur_spec.id = c.specialization_id
    WHERE s.specialization_id IS NOT NULL
      AND c.specialization_id IS NOT NULL
      AND s.specialization_id != c.specialization_id
    ORDER BY s.name
  """)

if bad_rows == [] do
  IO.puts("No cross-linked rows found. Nothing to do.")
else
  IO.puts("Found #{length(bad_rows)} wrongly cross-linked curricula_subjects row(s):\n")

  Enum.each(bad_rows, fn [_subj_id, _cur_id, subj_name, subj_spec, cur_name, cur_spec] ->
    IO.puts("  subject \"#{subj_name}\" (#{subj_spec})  →  wrongly linked into curricula \"#{cur_name}\" (#{cur_spec})")
  end)

  if apply? do
    {:ok, %{num_rows: n}} =
      Repo.query("""
        DELETE FROM public.curricula_subjects cs
        USING public.subjects s, public.curricula c
        WHERE cs.subject_id = s.id
          AND cs.curricula_id = c.id
          AND s.specialization_id IS NOT NULL
          AND c.specialization_id IS NOT NULL
          AND s.specialization_id != c.specialization_id
      """)

    IO.puts("\nDeleted #{n} row(s).")
  else
    IO.puts("\nDry run — nothing deleted. Re-run with --apply to remove these rows.")
  end
end
