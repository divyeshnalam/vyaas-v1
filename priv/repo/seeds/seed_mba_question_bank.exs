# ---------------------------------------------------------------------------
# MBA Question Bank seed
#
# Imports the MBA question archive (FINANCE / HR / MARKETING branches) into the
# public question bank, split by branch into the matching MBA specialisations,
# then wires up curricula (specialisation-specific selection) and role
# blueprints (job role -> MCQ subjects).
#
# Idempotent: safe to run multiple times and across environments (dev, prod).
# Everything is resolved BY NAME, so it works regardless of environment-specific
# UUIDs / ids.
#
# Usage (run where the app's DB credentials live — e.g. the dev/prod box):
#
#     MBA_RAR=/path/to/MBA.rar mix run priv/repo/seeds/seed_mba_question_bank.exs
#
# Requires `unrar` on PATH for .rar archives (`.zip` needs no extra tools).
# Defaults MBA_RAR to ~/Downloads/MBA.rar when unset.
# ---------------------------------------------------------------------------
alias VyaasaCampus.Repo
require Logger

archive = System.get_env("MBA_RAR") || Path.expand("~/Downloads/MBA.rar")
degree_name = System.get_env("MBA_DEGREE") || "MBA"

# BRANCH folder in the archive -> specialisation name under the degree
branch_to_spec = %{
  "FINANCE" => "Finance",
  "HR" => "Human Resources",
  "MARKETING" => "Marketing"
}

# Per-role total questions a generated assessment should pull (distributed
# across that specialisation's subjects). Admins can retune later in the UI.
role_question_total = String.to_integer(System.get_env("MBA_ROLE_QUESTIONS") || "30")

unless File.exists?(archive) do
  IO.puts("ERROR: archive not found at #{archive}. Set MBA_RAR=/path/to/MBA.rar")
  System.halt(1)
end

# --- Resolve degree + specialisations by name -------------------------------
degree_id =
  case Repo.query("SELECT id::text FROM public.degrees WHERE name ILIKE $1 LIMIT 1", [degree_name]) do
    {:ok, %{rows: [[id] | _]}} -> id
    _ ->
      IO.puts("ERROR: degree #{inspect(degree_name)} not found in public.degrees")
      System.halt(1)
  end

{:ok, degree_uuid} = Ecto.UUID.dump(degree_id)

spec_ids =
  branch_to_spec
  |> Map.values()
  |> Enum.uniq()
  |> Map.new(fn name ->
    id =
      case Repo.query("SELECT id::text FROM public.specializations WHERE name = $1 AND degree_id = $2 LIMIT 1", [name, degree_uuid]) do
        {:ok, %{rows: [[id] | _]}} -> id
        _ ->
          IO.puts("ERROR: specialisation #{inspect(name)} not found under degree #{degree_name}")
          System.halt(1)
      end

    {name, id}
  end)

IO.puts("Degree #{degree_name} = #{degree_id}")
Enum.each(spec_ids, fn {n, id} -> IO.puts("  spec #{n} = #{id}") end)

# --- Extract archive --------------------------------------------------------
dir = Path.join(System.tmp_dir!(), "mba_seed_#{:erlang.unique_integer([:positive])}")
File.rm_rf(dir)
File.mkdir_p!(dir)

case Path.extname(archive) |> String.downcase() do
  ".zip" ->
    {:ok, _} = :zip.unzip(String.to_charlist(archive), [{:cwd, String.to_charlist(dir)}])

  _ ->
    case System.cmd("unrar", ["x", "-o+", archive, dir <> "/"], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, code} ->
        IO.puts("ERROR: unrar failed (#{code}): #{String.slice(out, 0, 300)}")
        System.halt(1)
    end
end

txts =
  Path.wildcard(Path.join(dir, "**/*.txt"))
  |> Enum.reject(&String.starts_with?(Path.basename(&1), "."))

# --- Helpers ----------------------------------------------------------------
labels = ~w(a b c d e f g h)

parse = fn c ->
  case Jason.decode(c) do
    {:ok, l} when is_list(l) -> l
    _ ->
      m = Regex.replace(~r/\]\s*\[/, c, ",")
      case Jason.decode(m) do
        {:ok, l} when is_list(l) -> l
        _ -> []
      end
  end
end

norm_diff = fn d ->
  case String.downcase(String.trim(to_string(d || "medium"))) do
    x when x in ["beginner", "easy", "basic"] -> "easy"
    x when x in ["intermediate", "medium", "moderate"] -> "medium"
    x when x in ["advanced", "hard", "difficult", "expert"] -> "hard"
    _ -> "medium"
  end
end

gen_code = fn name, prefix ->
  base = name |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "") |> String.slice(0, 8)
  prefix <> base <> Integer.to_string(:rand.uniform(99_999))
end

subj_cache = :ets.new(:subj, [:set, :public])
chap_cache = :ets.new(:chap, [:set, :public])
topic_cache = :ets.new(:topic, [:set, :public])

get_subject = fn name, spec_uuid ->
  key = {spec_uuid, name}
  case :ets.lookup(subj_cache, key) do
    [{_, id}] -> id
    [] ->
      id =
        case Repo.query("SELECT id FROM public.subjects WHERE name=$1 AND specialization_id=$2 LIMIT 1", [name, spec_uuid]) do
          {:ok, %{rows: [[id] | _]}} -> id
          _ ->
            {:ok, %{rows: [[id] | _]}} =
              Repo.query("INSERT INTO public.subjects (name,code,specialization_id,inserted_at,updated_at) VALUES ($1,$2,$3,NOW(),NOW()) RETURNING id", [name, gen_code.(name, "S"), spec_uuid])
            id
        end
      :ets.insert(subj_cache, {key, id})
      id
  end
end

get_chapter = fn name, subject_id ->
  if is_nil(name) or name == "" do
    nil
  else
    key = {subject_id, name}
    case :ets.lookup(chap_cache, key) do
      [{_, id}] -> id
      [] ->
        id =
          case Repo.query("SELECT id FROM public.chapters WHERE name=$1 AND subject_id=$2 LIMIT 1", [name, subject_id]) do
            {:ok, %{rows: [[id] | _]}} -> id
            _ ->
              case Repo.query("INSERT INTO public.chapters (name,code,subject_id,inserted_at,updated_at) VALUES ($1,$2,$3,NOW(),NOW()) RETURNING id", [name, gen_code.(name, "C"), subject_id]) do
                {:ok, %{rows: [[id] | _]}} -> id
                _ -> nil
              end
          end
        :ets.insert(chap_cache, {key, id})
        id
    end
  end
end

get_topic = fn name, subject_id, chapter_id ->
  key = {subject_id, name}
  case :ets.lookup(topic_cache, key) do
    [{_, id}] -> id
    [] ->
      id =
        case Repo.query("SELECT id FROM public.topics WHERE name=$1 AND subject_id=$2 LIMIT 1", [name, subject_id]) do
          {:ok, %{rows: [[id] | _]}} -> id
          _ ->
            case Repo.query("INSERT INTO public.topics (name,subject_id,chapter_id,type,weightage,inserted_at,updated_at) VALUES ($1,$2,$3,'topic',1.0,NOW(),NOW()) RETURNING id", [name, subject_id, chapter_id]) do
              {:ok, %{rows: [[id] | _]}} -> id
              _ -> nil
            end
        end
      :ets.insert(topic_cache, {key, id})
      id
  end
end

insert_qa_batch = fn rows ->
  rows
  |> Enum.chunk_every(500)
  |> Enum.reduce(0, fn chunk, acc ->
    {ph, params, _n} =
      Enum.reduce(chunk, {[], [], 0}, fn {q, a, opts, diff, tid}, {phs, ps, n} ->
        {["($#{n + 1},$#{n + 2},$#{n + 3},$#{n + 4},'multiple_choice',1.0,$#{n + 5},NOW(),NOW())" | phs],
         [tid, diff, opts, a, q | ps], n + 5}
      end)

    sql = "INSERT INTO public.qa (question,answer,options,difficulty_level,type,weightage,topic_id,inserted_at,updated_at) VALUES " <> Enum.join(Enum.reverse(ph), ",")

    case Repo.query(sql, Enum.reverse(params)) do
      {:ok, %{num_rows: nr}} -> acc + nr
      {:error, e} ->
        Logger.error("qa batch failed: #{inspect(e) |> String.slice(0, 200)}")
        acc
    end
  end)
end

# --- Part A: import questions (split by branch) -----------------------------
IO.puts("\n== Part A: importing questions from #{archive} (#{length(txts)} files) ==")
t0 = System.monotonic_time(:millisecond)

stats =
  Enum.reduce(txts, %{}, fn f, acc ->
    parts = Path.relative_to(f, dir) |> String.split("/") |> Enum.reject(&(&1 == ""))
    branch = Enum.at(parts, 1)
    spec_name = branch_to_spec[branch]

    if is_nil(spec_name) do
      acc
    else
      {:ok, spec_uuid} = Ecto.UUID.dump(spec_ids[spec_name])
      subject_name = Enum.at(parts, 2) || branch
      chapter_name = if length(parts) >= 5, do: Enum.at(parts, 3), else: nil
      questions = parse.(File.read!(f) |> String.replace("\r\n", "\n"))

      if questions == [] do
        Map.update(acc, {spec_name, :bad}, 1, &(&1 + 1))
      else
        subject_id = get_subject.(subject_name, spec_uuid)
        chapter_id = get_chapter.(chapter_name, subject_id)

        by_topic =
          Enum.group_by(questions, fn q ->
            case String.trim(to_string(q["topic"] || chapter_name || subject_name)) do
              "" -> subject_name
              t -> t
            end
          end)

        inserted =
          Enum.reduce(by_topic, 0, fn {topic_name, qs}, ins ->
            topic_id = get_topic.(topic_name, subject_id, chapter_id)

            if is_nil(topic_id) do
              ins
            else
              existing =
                case Repo.query("SELECT question FROM public.qa WHERE topic_id=$1", [topic_id]) do
                  {:ok, %{rows: rows}} -> MapSet.new(rows, fn [q] -> q end)
                  _ -> MapSet.new()
                end

              {rows, _seen} =
                Enum.reduce(qs, {[], existing}, fn q, {rws, seen} ->
                  question = q["question"]

                  cond do
                    is_nil(question) or question == "" -> {rws, seen}
                    MapSet.member?(seen, question) -> {rws, seen}
                    true ->
                      opts = (q["options"] || []) |> Enum.with_index() |> Enum.into(%{}, fn {o, i} -> {Enum.at(labels, i, "x"), o} end)
                      ak = case Enum.find(opts, fn {_k, v} -> v == (q["correct_answer"] || "") end) do
                        {k, _} -> k
                        nil -> "a"
                      end
                      {[{question, ak, opts, norm_diff.(q["difficulty"]), topic_id} | rws], MapSet.put(seen, question)}
                  end
                end)

              ins + insert_qa_batch.(Enum.reverse(rows))
            end
          end)

        Map.update(acc, {spec_name, :q}, inserted, &(&1 + inserted))
      end
    end
  end)

IO.puts("Imported in #{Float.round((System.monotonic_time(:millisecond) - t0) / 1000, 1)}s")
Enum.each(branch_to_spec, fn {_b, spec_name} ->
  IO.puts("  #{spec_name}: new_questions=#{Map.get(stats, {spec_name, :q}, 0)} skipped_files=#{Map.get(stats, {spec_name, :bad}, 0)}")
end)

# --- Part B: curricula (specialisation-specific selection) ------------------
IO.puts("\n== Part B: curricula ==")

# A branch is one SPECIALIZATION's row in the admin "Branches" tab — matching
# how "Computer Science"/"Information Technology" already appear as separate
# branches under the "B.Tech" qualification, not one combined "B.Tech" branch.
# One shared branch per degree used to collapse all of MBA's specializations
# into a single "MBA" row and hide their per-specialization counts.
qualification_id =
  case Repo.query("SELECT id FROM public.qualifications WHERE name=$1 LIMIT 1", [degree_name]) do
    {:ok, %{rows: [[id] | _]}} -> id
    _ ->
      {:ok, %{rows: [[id] | _]}} =
        Repo.query("INSERT INTO public.qualifications (name,inserted_at,updated_at) VALUES ($1,NOW(),NOW()) RETURNING id", [degree_name])
      id
  end

Enum.each(branch_to_spec, fn {_b, spec_name} ->
  {:ok, spec_uuid} = Ecto.UUID.dump(spec_ids[spec_name])
  cname = "#{degree_name} #{spec_name}"

  # Scoped by (name, qualification_id) together, not name alone — several
  # degrees can share a specialization name (MBA and B.Tech both have an
  # "Information Technology" specialization); matching on name alone would
  # silently merge two unrelated specializations' question pools.
  branch_id =
    case Repo.query("SELECT id FROM public.branches WHERE name=$1 AND qualification_id=$2 LIMIT 1", [spec_name, qualification_id]) do
      {:ok, %{rows: [[id] | _]}} -> id
      _ ->
        {:ok, %{rows: [[id] | _]}} =
          Repo.query("INSERT INTO public.branches (name,code,qualification_id,inserted_at,updated_at) VALUES ($1,$2,$3,NOW(),NOW()) RETURNING id", [spec_name, gen_code.(spec_name, "B"), qualification_id])
        id
    end

  curricula_id =
    case Repo.query("SELECT id FROM public.curricula WHERE specialization_id=$1 LIMIT 1", [spec_uuid]) do
      {:ok, %{rows: [[id] | _]}} -> id
      _ ->
        {:ok, %{rows: [[id] | _]}} =
          Repo.query("INSERT INTO public.curricula (name,code,branch_id,specialization_id,inserted_at,updated_at) VALUES ($1,$2,$3,$4,NOW(),NOW()) RETURNING id", [cname, gen_code.(cname, "CU"), branch_id, spec_uuid])
        id
    end

  {:ok, %{num_rows: linked}} =
    Repo.query(
      """
      INSERT INTO public.curricula_subjects (curricula_id, subject_id, branch_id, inserted_at, updated_at)
      SELECT $1, s.id, $2, NOW(), NOW() FROM public.subjects s WHERE s.specialization_id = $3
      ON CONFLICT DO NOTHING
      """,
      [curricula_id, branch_id, spec_uuid]
    )

  IO.puts("  #{spec_name}: curricula=#{curricula_id} newly_linked_subjects=#{linked}")
end)

# --- Part C: role blueprints (job role -> MCQ subjects) ---------------------
IO.puts("\n== Part C: role blueprints ==")

industry_name = System.get_env("MBA_INDUSTRY") || "Management"

industry_id =
  case Repo.query("SELECT id FROM public.industries WHERE name=$1 LIMIT 1", [industry_name]) do
    {:ok, %{rows: [[id] | _]}} -> id
    _ ->
      {:ok, %{rows: [[id] | _]}} =
        Repo.query("INSERT INTO public.industries (name,code,is_active,inserted_at,updated_at) VALUES ($1,$2,true,NOW(),NOW()) RETURNING id", [industry_name, gen_code.(industry_name, "IND")])
      id
  end

Enum.each(branch_to_spec, fn {_b, spec_name} ->
  {:ok, spec_uuid} = Ecto.UUID.dump(spec_ids[spec_name])

  # Role title MUST match a student's preferred_role text (case-insensitive) for
  # role-based selection to kick in.
  role_id =
    case Repo.query("SELECT id FROM public.job_roles WHERE lower(title)=lower($1) AND industry_id=$2 LIMIT 1", [spec_name, industry_id]) do
      {:ok, %{rows: [[id] | _]}} -> id
      _ ->
        {:ok, %{rows: [[id] | _]}} =
          Repo.query("INSERT INTO public.job_roles (title,code,experience_level,is_active,industry_id,inserted_at,updated_at) VALUES ($1,$2,'entry',true,$3,NOW(),NOW()) RETURNING id", [spec_name, gen_code.(spec_name, "JR"), industry_id])
        id
    end

  # Subjects for this specialisation that actually have questions.
  {:ok, %{rows: subj_rows}} =
    Repo.query(
      """
      SELECT s.id FROM public.subjects s
      WHERE s.specialization_id = $1
        AND EXISTS (SELECT 1 FROM public.topics t JOIN public.qa q ON q.topic_id=t.id WHERE t.subject_id=s.id)
      ORDER BY s.id
      """,
      [spec_uuid]
    )

  subject_ids = Enum.map(subj_rows, fn [id] -> id end)

  if subject_ids == [] do
    IO.puts("  #{spec_name}: no subjects with questions — skipped blueprint")
  else
    n = length(subject_ids)
    per = max(1, div(role_question_total, n))

    # Replace-on-seed (same semantics as the admin "save subjects" action).
    Repo.query("DELETE FROM public.job_role_subjects WHERE job_role_id=$1", [role_id])

    Enum.each(subject_ids, fn sid ->
      Repo.query("INSERT INTO public.job_role_subjects (job_role_id, subject_id, question_count, inserted_at, updated_at) VALUES ($1,$2,$3,NOW(),NOW()) ON CONFLICT (job_role_id, subject_id) DO UPDATE SET question_count = EXCLUDED.question_count", [role_id, sid, per])
    end)

    IO.puts("  #{spec_name}: role=#{role_id} subjects=#{n} question_count_each=#{per} (~#{per * n} per assessment)")
  end
end)

File.rm_rf(dir)
IO.puts("\n== MBA seed complete ==")
