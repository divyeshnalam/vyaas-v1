# Wipes question-bank data (subjects/topics/chapters/questions/curricula/
# branches) for every specialization under one degree — leaving the degree and
# its specializations themselves untouched (those are reference data from
# seed_degrees.exs, not something to delete).
#
# Use this to clear out data seeded before the branch/cross-link fixes (see
# question_bank_live.ex's link_to_curricula/2 and get_or_create_branch/2)
# before re-uploading, rather than trying to repair it in place.
#
# subjects -> topics -> chapters -> qa, and subjects -> curricula_subjects,
# all cascade via ON DELETE CASCADE, so deleting subjects is enough to clear
# everything downstream. curricula and now-orphaned branches are removed
# explicitly after.
#
# Read-only report first; nothing is deleted unless you pass --apply.
#
#   mix run priv/scripts/wipe_question_bank_for_degree.exs                     # dry run, defaults to MBA
#   DEGREE_NAME="MBA" mix run priv/scripts/wipe_question_bank_for_degree.exs --apply

alias VyaasaCampus.Repo

apply? = "--apply" in System.argv()
degree_name = System.get_env("DEGREE_NAME") || "MBA"

case Repo.query("SELECT id FROM public.degrees WHERE name = $1", [degree_name]) do
  {:ok, %{rows: []}} ->
    IO.puts("No degree named #{inspect(degree_name)} found. Nothing to do.")

  {:ok, %{rows: [[degree_id]]}} ->
    {:ok, %{rows: spec_rows}} =
      Repo.query("SELECT id, name FROM public.specializations WHERE degree_id = $1", [degree_id])

    if spec_rows == [] do
      IO.puts("Degree #{degree_name} has no specializations. Nothing to do.")
    else
      spec_ids = Enum.map(spec_rows, &List.first/1)
      spec_names = Enum.map(spec_rows, fn [_id, name] -> name end)

      IO.puts("Degree: #{degree_name}")
      IO.puts("Specializations (#{length(spec_rows)}): #{Enum.join(spec_names, ", ")}\n")

      {:ok, %{rows: [[subject_count]]}} =
        Repo.query("SELECT count(*) FROM public.subjects WHERE specialization_id = ANY($1)", [spec_ids])

      {:ok, %{rows: [[question_count]]}} =
        Repo.query("""
          SELECT count(*) FROM public.qa q
          JOIN public.topics t ON t.id = q.topic_id
          JOIN public.subjects s ON s.id = t.subject_id
          WHERE s.specialization_id = ANY($1)
        """, [spec_ids])

      {:ok, %{rows: curricula_rows}} =
        Repo.query("SELECT id, branch_id, name FROM public.curricula WHERE specialization_id = ANY($1)", [spec_ids])

      # Cross-link check: any of this degree's subjects linked into a curricula
      # OUTSIDE this degree (the exact bug this whole cleanup exists for).
      {:ok, %{rows: cross_links}} =
        Repo.query("""
          SELECT DISTINCT c.name
          FROM public.curricula_subjects cs
          JOIN public.subjects s ON s.id = cs.subject_id
          JOIN public.curricula c ON c.id = cs.curricula_id
          WHERE s.specialization_id = ANY($1) AND c.specialization_id != ALL($1)
        """, [spec_ids])

      IO.puts("Would delete:")
      IO.puts("  #{subject_count} subject(s) (cascades to their topics/chapters/questions)")
      IO.puts("  #{question_count} question(s)")
      IO.puts("  #{length(curricula_rows)} curricula row(s): #{Enum.map_join(curricula_rows, ", ", fn [_, _, n] -> n end)}")

      if cross_links != [] do
        IO.puts("  Also clears wrong cross-links into: #{Enum.map_join(cross_links, ", ", &List.first/1)}")
      end

      if apply? do
        {:ok, %{num_rows: n}} = Repo.query("DELETE FROM public.subjects WHERE specialization_id = ANY($1)", [spec_ids])
        IO.puts("\nDeleted #{n} subject(s) (topics/chapters/questions/links cascaded).")

        {:ok, %{num_rows: nc}} = Repo.query("DELETE FROM public.curricula WHERE specialization_id = ANY($1)", [spec_ids])
        IO.puts("Deleted #{nc} curricula row(s).")

        branch_ids = curricula_rows |> Enum.map(fn [_, bid, _] -> bid end) |> Enum.uniq()

        Enum.each(branch_ids, fn branch_id ->
          {:ok, %{rows: [[remaining]]}} =
            Repo.query("SELECT count(*) FROM public.curricula WHERE branch_id = $1", [branch_id])

          if remaining == 0 do
            Repo.query("DELETE FROM public.branches WHERE id = $1", [branch_id])
          end
        end)

        IO.puts("Removed now-orphaned branch(es).")
        IO.puts("\nDone. #{degree_name}'s degree/specialization rows are untouched — ready to re-upload.")
      else
        IO.puts("\nDry run — nothing deleted. Re-run with --apply to actually delete.")
      end
    end
end
