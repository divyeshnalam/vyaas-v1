defmodule VyaasaCampusWeb.Admin.QuestionBankLive do
  @moduledoc """
  Super admin LiveView for managing the question bank.
  Shows question counts per subject/topic and allows ZIP upload to seed questions.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Repo

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @max_upload_size 100_000_000  # 100 MB

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    user_info =
      case current_user do
        nil ->
          %{name: "Super Admin", email: nil, role: "Platform Admin"}

        u ->
          %{
            name: String.trim("#{u.first_name} #{u.last_name}"),
            email: u.email,
            role: "Platform Admin"
          }
      end

    socket =
      socket
      |> assign(:page_title, "Question Bank")
      |> assign(:user_info, user_info)
      |> assign(:subject_stats, load_subject_stats())
      |> assign(:total_questions, load_total_questions())
      |> assign(:total_subjects, load_total_subjects())
      |> assign(:total_topics, load_total_topics())
      |> assign(:selected_subject, nil)
      |> assign(:topic_stats, [])
      |> assign(:branch_stats, load_branch_stats())
      |> assign(:selected_branch, nil)
      |> assign(:branch_subjects, [])
      |> assign(:uploading?, false)
      |> assign(:upload_result, nil)
      |> assign(:degree_options, load_degree_options())
      |> assign(:selected_degree, nil)
      |> assign(:spec_options, [])
      |> assign(:selected_spec, nil)
      |> allow_upload(:question_zip,
        accept: ~w(.zip .rar),
        max_entries: 1,
        max_file_size: @max_upload_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("select_branch", %{"id" => branch_id}, socket) do
    {id, _} = Integer.parse(branch_id)
    branch = Enum.find(socket.assigns.branch_stats, fn b -> b.id == id end)

    {:noreply,
     socket
     |> assign(:selected_branch, branch)
     |> assign(:branch_subjects, load_branch_subjects(id))
     |> assign(:selected_subject, nil)
     |> assign(:topic_stats, [])}
  end

  @impl true
  def handle_event("close_branch", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_branch, nil)
     |> assign(:branch_subjects, [])
     |> assign(:selected_subject, nil)
     |> assign(:topic_stats, [])}
  end

  @impl true
  def handle_event("select_subject", %{"id" => subject_id}, socket) do
    {id, _} = Integer.parse(subject_id)

    if socket.assigns.selected_subject && socket.assigns.selected_subject.id == id do
      # Clicking the expanded subject collapses it.
      {:noreply, socket |> assign(:selected_subject, nil) |> assign(:topic_stats, [])}
    else
      subject = Enum.find(socket.assigns.branch_subjects, fn s -> s.id == id end)

      {:noreply,
       socket
       |> assign(:selected_subject, subject)
       |> assign(:topic_stats, load_topic_stats(id))}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_degree", %{"degree_id" => degree_id}, socket) do
    specs = load_specialization_options(degree_id)

    {:noreply,
     socket
     |> assign(:selected_degree, degree_id)
     |> assign(:spec_options, specs)
     |> assign(:selected_spec, nil)}
  end

  @impl true
  def handle_event("select_spec", %{"spec_id" => spec_id}, socket) do
    {:noreply, assign(socket, :selected_spec, spec_id)}
  end

  @impl true
  def handle_event("upload_questions", _params, socket) do
    socket = assign(socket, :uploading?, true)

    spec_id = socket.assigns.selected_spec
    degree_id = socket.assigns.selected_degree

    uploaded_files =
      consume_uploaded_entries(socket, :question_zip, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name) |> String.downcase()
        dest = Path.join(System.tmp_dir!(), "question_upload_#{:rand.uniform(999999)}#{ext}")
        File.cp!(path, dest)
        {:ok, {dest, ext}}
      end)

    case uploaded_files do
      [{file_path, ext}] ->
        result = process_archive_upload(file_path, ext, spec_id, degree_id)
        File.rm(file_path)

        {:noreply,
         socket
         |> assign(:uploading?, false)
         |> assign(:upload_result, result)
         |> assign(:subject_stats, load_subject_stats())
         |> assign(:branch_stats, load_branch_stats())
         |> assign(:branch_subjects, refresh_branch_subjects(socket))
         |> assign(:total_questions, load_total_questions())
         |> assign(:total_subjects, load_total_subjects())
         |> assign(:total_topics, load_total_topics())
         |> put_flash(:info, "Imported #{result.imported} questions (#{result.skipped} duplicates skipped)")}

      _ ->
        {:noreply,
         socket
         |> assign(:uploading?, false)
         |> put_flash(:error, "No file uploaded")}
    end
  end

  @impl true
  def handle_event("dismiss_result", _params, socket) do
    {:noreply, assign(socket, :upload_result, nil)}
  end

  @impl true
  def handle_event("delete_subject", %{"id" => subject_id}, socket) do
    {id, _} = Integer.parse(subject_id)

    case delete_subject_cascade(id) do
      :ok ->
        selected =
          if socket.assigns.selected_subject && socket.assigns.selected_subject.id == id,
            do: nil,
            else: socket.assigns.selected_subject

        {:noreply,
         socket
         |> assign(:selected_subject, selected)
         |> assign(:topic_stats, if(is_nil(selected), do: [], else: socket.assigns.topic_stats))
         |> assign(:subject_stats, load_subject_stats())
         |> assign(:branch_stats, load_branch_stats())
         |> assign(:branch_subjects, refresh_branch_subjects(socket))
         |> assign(:total_questions, load_total_questions())
         |> assign(:total_subjects, load_total_subjects())
         |> assign(:total_topics, load_total_topics())
         |> put_flash(:info, "Subject deleted successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete subject: #{reason}")}
    end
  end

  # ============================================================================
  # ARCHIVE PROCESSING
  # ============================================================================

  defp process_archive_upload(file_path, ext, spec_id, degree_id) do
    require Logger

    spec_candidates = build_spec_candidates(degree_id)

    case ext do
      ".zip" -> process_zip_file(file_path, spec_id, spec_candidates)
      ".rar" -> process_rar_file(file_path, spec_id, spec_candidates)
      _ ->
        Logger.error("Unsupported file type: #{ext}")
        %{imported: 0, skipped: 0, errors: 1, subjects: MapSet.new()}
    end
  end

  defp process_zip_file(zip_path, spec_id, spec_candidates) do
    require Logger

    case :zip.unzip(String.to_charlist(zip_path), [:memory]) do
      {:ok, file_list} ->
        results =
          file_list
          |> Enum.filter(fn {name, _} ->
            fname = to_string(name)
            String.ends_with?(fname, ".txt") and not String.starts_with?(Path.basename(fname), ".")
          end)
          |> Enum.reduce(%{imported: 0, skipped: 0, errors: 0, subjects: MapSet.new()}, fn {name_chars, content}, acc ->
            fname = to_string(name_chars)
            process_archive_entry(fname, content, spec_id, spec_candidates, acc)
          end)

        Logger.info("ZIP import done: #{results.imported} imported, #{results.skipped} skipped, #{results.errors} errors")
        results

      {:error, reason} ->
        Logger.error("Failed to unzip: #{inspect(reason)}")
        %{imported: 0, skipped: 0, errors: 1, subjects: MapSet.new()}
    end
  end

  defp process_rar_file(rar_path, spec_id, spec_candidates) do
    require Logger

    extract_dir = Path.join(System.tmp_dir!(), "rar_extract_#{:rand.uniform(999999)}")
    File.mkdir_p!(extract_dir)

    try do
      case System.cmd("unrar", ["x", "-o+", rar_path, extract_dir <> "/"], stderr_to_stdout: true) do
        {_output, 0} ->
          txt_files =
            Path.wildcard(Path.join(extract_dir, "**/*.txt"))
            |> Enum.reject(fn f -> String.starts_with?(Path.basename(f), ".") end)

          results =
            Enum.reduce(txt_files, %{imported: 0, skipped: 0, errors: 0, subjects: MapSet.new()}, fn file, acc ->
              relative_path = Path.relative_to(file, extract_dir)
              content = File.read!(file)
              process_archive_entry(relative_path, content, spec_id, spec_candidates, acc)
            end)

          Logger.info("RAR import done: #{results.imported} imported, #{results.skipped} skipped")
          results

        {output, code} ->
          Logger.error("unrar failed (exit #{code}): #{String.slice(output, 0, 500)}")
          %{imported: 0, skipped: 0, errors: 1, subjects: MapSet.new()}
      end
    rescue
      e in ErlangError ->
        # :enoent here means the `unrar` binary itself is missing from PATH.
        Logger.error("RAR handling failed: #{inspect(e)}. If this is :enoent, install 'unrar' (apt install unrar).")
        %{imported: 0, skipped: 0, errors: 1, subjects: MapSet.new()}

      e ->
        Logger.error("RAR processing failed: #{Exception.message(e)}")
        %{imported: 0, skipped: 0, errors: 1, subjects: MapSet.new()}
    after
      File.rm_rf(extract_dir)
    end
  end

  # Path parsing. The first folder is the archive root and is ignored.
  #
  # Branch auto-split: when a degree is selected and the folder just below the
  # root matches one of that degree's specialisations (by normalised name or its
  # initials — e.g. "HR" → "Human Resources"), the file is routed to THAT
  # specialisation, with subject = the next folder down and chapter = the folder
  # after it. This lets a single multi-branch archive (MBA/FINANCE/…, MBA/HR/…,
  # MBA/MARKETING/…) split into the right specialisations in one upload.
  #
  # Fallback (no branch match): everything goes to the specialisation picked in
  # the UI, with subject = first folder after root and chapter = file name.
  defp process_archive_entry(file_path, content, fallback_spec_id, spec_candidates, acc) do
    parts =
      file_path
      |> String.replace("\\", "/")
      |> String.split("/")
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "__MACOSX") or String.starts_with?(&1, ".")))

    # Need at least: [root, file.txt]
    if length(parts) < 2 do
      acc
    else
      # Strip root folder (RAR/ZIP name)
      [_root | rest] = parts

      {spec_id, subject_name, chapter_name} =
        case resolve_branch_to_spec(List.first(rest), spec_candidates) do
          nil ->
            {sub, chap} = extract_subject_and_chapter(rest)
            {fallback_spec_id, sub, chap}

          branch_spec_id ->
            {sub, chap} = branch_subject_and_chapter(tl(rest))
            {branch_spec_id, sub, chap}
        end

      content_str = content |> to_string() |> String.replace("\r\n", "\n")
      questions = parse_json_questions(content_str)

      if questions == [] or is_nil(spec_id) do
        acc
      else
        subject_id = get_or_create_subject(subject_name, spec_id)

        if is_nil(subject_id) do
          %{acc | errors: acc.errors + 1}
        else
          chapter_id = if chapter_name, do: get_or_create_chapter(chapter_name, subject_id), else: nil

          # Group questions by their JSON "topic" field, fallback to chapter or subject name
          {imported, skipped} = insert_questions_with_topics(questions, subject_id, chapter_id, chapter_name || subject_name)

          %{acc |
            imported: acc.imported + imported,
            skipped: acc.skipped + skipped,
            subjects: MapSet.put(acc.subjects, subject_name)
          }
        end
      end
    end
  end

  # Parts BELOW a matched branch folder → {subject, chapter}:
  #   [subject, chapter, …, file] → subject, chapter
  #   [subject, file]             → subject, no chapter
  defp branch_subject_and_chapter([]), do: {"General", nil}
  defp branch_subject_and_chapter([only]), do: {clean_name(only), nil}
  defp branch_subject_and_chapter([subject_folder, _file]), do: {clean_name(subject_folder), nil}

  defp branch_subject_and_chapter([subject_folder, chapter_folder | _rest]),
    do: {clean_name(subject_folder), clean_name(chapter_folder)}

  # Build specialisation match candidates for the selected degree. Each spec is
  # keyed by its normalised name AND its initials, so a "HR" folder resolves to
  # the "Human Resources" specialisation.
  defp build_spec_candidates(nil), do: []

  defp build_spec_candidates(degree_id) do
    degree_id
    |> load_specialization_options()
    |> Enum.map(fn %{id: id, name: name} ->
      keys = MapSet.new([normalize_match_key(name), spec_initials(name)]) |> MapSet.delete("")
      %{id: id, keys: keys}
    end)
  end

  defp resolve_branch_to_spec(_branch, []), do: nil
  defp resolve_branch_to_spec(nil, _candidates), do: nil

  defp resolve_branch_to_spec(branch, candidates) do
    case normalize_match_key(branch) do
      "" -> nil
      key -> Enum.find_value(candidates, fn %{id: id, keys: keys} -> if MapSet.member?(keys, key), do: id end)
    end
  end

  defp normalize_match_key(name) do
    name |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
  end

  defp spec_initials(name) do
    name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.downcase()
  end

  # Extract subject and chapter from path parts (after root is stripped)
  defp extract_subject_and_chapter([file_name]) do
    # Depth 2: just root/file.txt → subject = file name, no chapter
    {clean_name(file_name), nil}
  end

  defp extract_subject_and_chapter([subject_folder, file_name]) do
    # Depth 3: root/subject/file.txt → subject = folder, chapter = file name
    {clean_name(subject_folder), clean_name(file_name)}
  end

  defp extract_subject_and_chapter([subject_folder | rest]) do
    # Depth 4+: root/subject/.../file.txt → subject = first folder after root, chapter = file name
    file_name = List.last(rest)
    {clean_name(subject_folder), clean_name(file_name)}
  end

  defp clean_name(name) do
    name
    |> String.replace(~r/\.txt$/i, "")
    |> String.replace(" Curriculum Overview", "")
    |> String.replace(" Assessment Questions", "")
    |> String.replace(~r/\s*\(Quest\)$/i, "")
    |> String.trim()
  end

  defp parse_json_questions(content) do
    case Jason.decode(content) do
      {:ok, questions} when is_list(questions) ->
        questions

      {:error, _} ->
        # Handle multiple concatenated JSON arrays
        merged = Regex.replace(~r/\]\s*\[/, content, ",")
        case Jason.decode(merged) do
          {:ok, questions} when is_list(questions) -> questions
          _ -> []
        end
    end
  end

  # Insert a file's questions grouped by their resolved topic. Per topic we do
  # ONE select for existing question texts (dedup) + ONE batched multi-row
  # INSERT, instead of two queries per question. This turns a ~200-question file
  # from ~400 round-trips into ~2, so large archives import in seconds rather
  # than timing out the LiveView.
  defp insert_questions_with_topics(questions, subject_id, chapter_id, fallback_topic_name) do
    questions
    |> Enum.group_by(fn q ->
      case String.trim(to_string(q["topic"] || fallback_topic_name)) do
        "" -> fallback_topic_name
        name -> name
      end
    end)
    |> Enum.reduce({0, 0}, fn {topic_name, topic_questions}, {imp, skip} ->
      topic_id = get_or_create_topic(topic_name, subject_id, chapter_id)

      if is_nil(topic_id) do
        {imp, skip}
      else
        existing =
          case Repo.query("SELECT question FROM public.qa WHERE topic_id = $1", [topic_id]) do
            {:ok, %{rows: rows}} -> MapSet.new(rows, fn [q] -> q end)
            _ -> MapSet.new()
          end

        {rows, _seen, dup} =
          Enum.reduce(topic_questions, {[], existing, 0}, fn q, {acc, seen, d} ->
            question_text = q["question"]

            cond do
              is_nil(question_text) or question_text == "" ->
                {acc, seen, d}

              MapSet.member?(seen, question_text) ->
                {acc, seen, d + 1}

              true ->
                {[question_row(q, question_text, topic_id) | acc], MapSet.put(seen, question_text), d}
            end
          end)

        {imp + batch_insert_qa(Enum.reverse(rows)), skip + dup}
      end
    end)
  end

  @option_labels ~w(a b c d e f g h)

  defp question_row(q, question_text, topic_id) do
    options_map =
      (q["options"] || [])
      |> Enum.with_index()
      |> Enum.into(%{}, fn {opt, idx} -> {Enum.at(@option_labels, idx, "x"), opt} end)

    answer_key =
      case Enum.find(options_map, fn {_k, v} -> v == (q["correct_answer"] || "") end) do
        {key, _} -> key
        nil -> "a"
      end

    {question_text, answer_key, options_map, normalize_difficulty(q["difficulty"]), topic_id}
  end

  defp normalize_difficulty(raw) do
    case String.downcase(String.trim(raw || "medium")) do
      d when d in ["beginner", "easy", "basic"] -> "easy"
      d when d in ["intermediate", "medium", "moderate"] -> "medium"
      d when d in ["advanced", "hard", "difficult", "expert"] -> "hard"
      _ -> "medium"
    end
  end

  # Multi-row parameterized INSERT, chunked to stay well under Postgres' param cap.
  defp batch_insert_qa([]), do: 0

  defp batch_insert_qa(rows) do
    rows
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {placeholders, params, _n} =
        Enum.reduce(chunk, {[], [], 0}, fn {q, a, opts, diff, tid}, {phs, ps, n} ->
          {["($#{n + 1},$#{n + 2},$#{n + 3},$#{n + 4},'multiple_choice',1.0,$#{n + 5},NOW(),NOW())" | phs],
           [tid, diff, opts, a, q | ps], n + 5}
        end)

      sql =
        "INSERT INTO public.qa (question, answer, options, difficulty_level, type, weightage, topic_id, inserted_at, updated_at) VALUES " <>
          Enum.join(Enum.reverse(placeholders), ",")

      case Repo.query(sql, Enum.reverse(params)) do
        {:ok, %{num_rows: nr}} -> acc + nr
        {:error, _} -> acc
      end
    end)
  end

  # ============================================================================
  # DB HELPERS
  # ============================================================================

  defp delete_subject_cascade(subject_id) do
    require Logger

    try do
      # Delete in order: qa → topics → chapters → curricula_subjects → subject
      # The DB has ON DELETE CASCADE for topics→qa and subjects→topics,
      # but curricula_subjects needs explicit cleanup
      Repo.query("DELETE FROM public.curricula_subjects WHERE subject_id = $1", [subject_id])
      Repo.query("DELETE FROM public.subjects WHERE id = $1", [subject_id])
      Logger.info("Deleted subject #{subject_id} and all related data")
      :ok
    rescue
      e ->
        Logger.error("Failed to delete subject #{subject_id}: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp get_or_create_subject(subject_name, spec_id) do
    {:ok, spec_uuid} = Ecto.UUID.dump(spec_id)

    # Look for existing subject with this name under this specialization
    query = "SELECT id FROM public.subjects WHERE name = $1 AND specialization_id = $2 LIMIT 1"
    case Repo.query(query, [subject_name, spec_uuid]) do
      {:ok, %{rows: [[id] | _]}} ->
        id

      _ ->
        # Also check if subject exists without specialization (legacy) and claim it
        legacy_q = "SELECT id FROM public.subjects WHERE name = $1 AND specialization_id IS NULL LIMIT 1"
        case Repo.query(legacy_q, [subject_name]) do
          {:ok, %{rows: [[id] | _]}} ->
            # Claim this subject for the specialization
            Repo.query("UPDATE public.subjects SET specialization_id = $1 WHERE id = $2", [spec_uuid, id])
            id

          _ ->
            code =
              subject_name
              |> String.upcase()
              |> String.replace(~r/[^A-Z0-9]/, "")
              |> String.slice(0, 10)
              |> Kernel.<>("#{:rand.uniform(999)}")

            insert_q = """
            INSERT INTO public.subjects (name, code, specialization_id, inserted_at, updated_at)
            VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id
            """
            case Repo.query(insert_q, [subject_name, code, spec_uuid]) do
              {:ok, %{rows: [[id] | _]}} ->
                # Also link to curricula_subjects for backward compat with assessment generation
                link_to_curricula(id, spec_id)
                id

              {:error, _} -> nil
            end
        end
    end
  end

  # Link a subject into `curricula_subjects` — scoped to ITS OWN specialization
  # only. Get-or-creates the curricula row for that specialization (mirroring
  # what seed_mba_question_bank.exs already does correctly) rather than falling
  # back to "every curricula", which used to link e.g. an MBA/Finance upload
  # into every existing branch, including Computer Science — polluting that
  # branch's subject pool for exam question selection
  # (Contexts.Assessments.select_questions_excluding_subject/6 reads exactly
  # this table).
  defp link_to_curricula(subject_id, spec_id) do
    {:ok, spec_uuid} = Ecto.UUID.dump(spec_id)

    case get_or_create_curricula_for_spec(spec_uuid) do
      {curricula_id, branch_id} ->
        link_q = "INSERT INTO public.curricula_subjects (curricula_id, subject_id, branch_id, inserted_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) ON CONFLICT DO NOTHING"
        Repo.query(link_q, [curricula_id, subject_id, branch_id])

      nil ->
        :ok
    end
  end

  defp get_or_create_curricula_for_spec(spec_uuid) do
    case Repo.query("SELECT id, branch_id FROM public.curricula WHERE specialization_id = $1 LIMIT 1", [spec_uuid]) do
      {:ok, %{rows: [[curricula_id, branch_id] | _]}} ->
        {curricula_id, branch_id}

      _ ->
        with {:ok, %{rows: [[spec_name, degree_name] | _]}} <-
               Repo.query(
                 "SELECT s.name, d.name FROM public.specializations s JOIN public.degrees d ON d.id = s.degree_id WHERE s.id = $1",
                 [spec_uuid]
               ),
             qualification_id when not is_nil(qualification_id) <- get_or_create_qualification(degree_name),
             branch_id when not is_nil(branch_id) <- get_or_create_branch(spec_name, qualification_id),
             {:ok, %{rows: [[curricula_id] | _]}} <-
               Repo.query(
                 "INSERT INTO public.curricula (name, code, branch_id, specialization_id, inserted_at, updated_at) VALUES ($1, $2, $3, $4, NOW(), NOW()) RETURNING id",
                 [spec_name, qb_code(spec_name, "CU"), branch_id, spec_uuid]
               ) do
          {curricula_id, branch_id}
        else
          _ -> nil
        end
    end
  end

  # Get-or-create the qualification (degree-level, e.g. "B.Tech"/"MBA") that
  # groups a specialization's branch. load_branch_stats/0 (the admin
  # "Branches" tab) INNER JOINs qualifications, so a branch with no
  # qualification_id is silently invisible there even though its data is real.
  defp get_or_create_qualification(degree_name) do
    case Repo.query("SELECT id FROM public.qualifications WHERE name = $1 LIMIT 1", [degree_name]) do
      {:ok, %{rows: [[id] | _]}} ->
        id

      _ ->
        case Repo.query(
               "INSERT INTO public.qualifications (name, inserted_at, updated_at) VALUES ($1, NOW(), NOW()) RETURNING id",
               [degree_name]
             ) do
          {:ok, %{rows: [[id] | _]}} -> id
          _ -> nil
        end
    end
  end

  # A branch is one SPECIALIZATION's row in the Branches tab — matching how
  # "Computer Science" and "Information Technology" already appear as separate
  # branches under the "B.Tech" qualification, rather than one combined
  # "B.Tech" branch. Scoped by (name, qualification_id) together, NOT name
  # alone: several degrees can share a specialization name (e.g. MBA and
  # B.Tech both have an "Information Technology" specialization) — matching on
  # name alone would silently merge two unrelated specializations' question
  # pools into the same branch.
  defp get_or_create_branch(spec_name, qualification_id) do
    case Repo.query(
           "SELECT id FROM public.branches WHERE name = $1 AND qualification_id = $2 LIMIT 1",
           [spec_name, qualification_id]
         ) do
      {:ok, %{rows: [[id] | _]}} ->
        id

      _ ->
        case Repo.query(
               "INSERT INTO public.branches (name, code, qualification_id, inserted_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id",
               [spec_name, qb_code(spec_name, "B"), qualification_id]
             ) do
          {:ok, %{rows: [[id] | _]}} -> id
          _ -> nil
        end
    end
  end

  defp qb_code(name, prefix) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 10)
    |> Kernel.<>("#{prefix}#{:rand.uniform(999)}")
  end

  defp get_or_create_chapter(chapter_name, subject_id) do
    query = "SELECT id FROM public.chapters WHERE name = $1 AND subject_id = $2 LIMIT 1"
    case Repo.query(query, [chapter_name, subject_id]) do
      {:ok, %{rows: [[id] | _]}} -> id
      _ ->
        code =
          chapter_name
          |> String.upcase()
          |> String.replace(~r/[^A-Z0-9]/, "")
          |> String.slice(0, 10)
          |> Kernel.<>("#{:rand.uniform(99)}")

        insert_q = """
        INSERT INTO public.chapters (name, code, subject_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id
        """
        case Repo.query(insert_q, [chapter_name, code, subject_id]) do
          {:ok, %{rows: [[id] | _]}} -> id
          {:error, _} -> nil
        end
    end
  end

  defp get_or_create_topic(topic_name, subject_id, chapter_id) do
    # Look for topic by name under this subject
    query = "SELECT id FROM public.topics WHERE name = $1 AND subject_id = $2 LIMIT 1"
    case Repo.query(query, [topic_name, subject_id]) do
      {:ok, %{rows: [[id] | _]}} ->
        # Update chapter_id if not set
        if chapter_id do
          Repo.query("UPDATE public.topics SET chapter_id = $1 WHERE id = $2 AND chapter_id IS NULL", [chapter_id, id])
        end
        id
      _ ->
        insert_q = """
        INSERT INTO public.topics (name, subject_id, chapter_id, type, weightage, inserted_at, updated_at)
        VALUES ($1, $2, $3, 'topic', 1.0, NOW(), NOW()) RETURNING id
        """
        case Repo.query(insert_q, [topic_name, subject_id, chapter_id]) do
          {:ok, %{rows: [[id] | _]}} -> id
          {:error, _} -> nil
        end
    end
  end

  # ============================================================================
  # STATS QUERIES
  # ============================================================================

  defp load_subject_stats do
    query = """
    SELECT s.id, s.name, COUNT(q.id)::integer as count,
           COUNT(DISTINCT t.id)::integer as topic_count
    FROM public.subjects s
    LEFT JOIN public.topics t ON t.subject_id = s.id
    LEFT JOIN public.qa q ON q.topic_id = t.id
    GROUP BY s.id, s.name
    ORDER BY COUNT(q.id) DESC
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, count, topic_count] ->
          %{id: id, name: name, count: count, topic_count: topic_count}
        end)

      _ -> []
    end
  end

  defp load_topic_stats(subject_id) do
    query = """
    SELECT t.id, t.name, COUNT(q.id)::integer as count,
           COUNT(CASE WHEN q.difficulty_level = 'easy' THEN 1 END)::integer as easy,
           COUNT(CASE WHEN q.difficulty_level = 'medium' THEN 1 END)::integer as medium,
           COUNT(CASE WHEN q.difficulty_level = 'hard' THEN 1 END)::integer as hard
    FROM public.topics t
    LEFT JOIN public.qa q ON q.topic_id = t.id
    WHERE t.subject_id = $1
    GROUP BY t.id, t.name
    ORDER BY COUNT(q.id) DESC
    """

    case Repo.query(query, [subject_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, count, easy, medium, hard] ->
          %{id: id, name: name, count: count, easy: easy, medium: medium, hard: hard}
        end)

      _ -> []
    end
  end

  # Branches that have subjects mapped, with rolled-up subject/topic/question
  # counts. Subjects hang off a branch via curricula_subjects.branch_id, and the
  # branch's degree is its qualification.
  defp load_branch_stats do
    query = """
    SELECT b.id, b.name, q.name AS degree_name,
           COUNT(DISTINCT cs.subject_id)::integer AS subject_count,
           COUNT(DISTINCT t.id)::integer AS topic_count,
           COUNT(qa.id)::integer AS question_count
    FROM public.branches b
    JOIN public.qualifications q ON q.id = b.qualification_id
    JOIN public.curricula_subjects cs ON cs.branch_id = b.id
    LEFT JOIN public.topics t ON t.subject_id = cs.subject_id
    LEFT JOIN public.qa qa ON qa.topic_id = t.id
    GROUP BY b.id, b.name, q.name
    HAVING COUNT(DISTINCT cs.subject_id) > 0
    ORDER BY COUNT(qa.id) DESC, b.name
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, degree, sc, tc, qc] ->
          %{id: id, name: name, degree_name: degree, subject_count: sc, topic_count: tc, question_count: qc}
        end)

      _ -> []
    end
  end

  # Subjects under one branch, with topic/question counts (for the drawer).
  defp load_branch_subjects(branch_id) do
    query = """
    SELECT s.id, s.name,
           COUNT(DISTINCT t.id)::integer AS topic_count,
           COUNT(qa.id)::integer AS question_count
    FROM public.curricula_subjects cs
    JOIN public.subjects s ON s.id = cs.subject_id
    LEFT JOIN public.topics t ON t.subject_id = s.id
    LEFT JOIN public.qa qa ON qa.topic_id = t.id
    WHERE cs.branch_id = $1
    GROUP BY s.id, s.name
    ORDER BY COUNT(qa.id) DESC, s.name
    """

    case Repo.query(query, [branch_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, tc, qc] ->
          %{id: id, name: name, topic_count: tc, count: qc}
        end)

      _ -> []
    end
  end

  # Re-fetch the open drawer's subject list (used after upload/delete).
  defp refresh_branch_subjects(socket) do
    case socket.assigns.selected_branch do
      %{id: id} -> load_branch_subjects(id)
      _ -> []
    end
  end

  defp load_total_questions do
    case Repo.query("SELECT COUNT(*)::integer FROM public.qa") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp load_total_subjects do
    case Repo.query("SELECT COUNT(DISTINCT s.id)::integer FROM public.subjects s JOIN public.topics t ON t.subject_id = s.id JOIN public.qa q ON q.topic_id = t.id") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp load_total_topics do
    case Repo.query("SELECT COUNT(DISTINCT t.id)::integer FROM public.topics t JOIN public.qa q ON q.topic_id = t.id") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp load_degree_options do
    case Repo.query("SELECT id::text, name FROM public.degrees WHERE is_active = true ORDER BY name") do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name] -> %{id: id, name: name} end)
      _ -> []
    end
  end

  defp load_specialization_options(degree_id) do
    {:ok, degree_uuid} = Ecto.UUID.dump(degree_id)

    case Repo.query("SELECT id::text, name, code FROM public.specializations WHERE degree_id = $1 AND is_active = true ORDER BY name", [degree_uuid]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, code] -> %{id: id, name: name, code: code} end)
      _ -> []
    end
  end


  # ============================================================================
  # RENDER
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout user_info={@user_info} current_section="question_bank">
        <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-350 mx-auto w-full">
            <!-- Stats Overview -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
              <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
                <div class="flex items-center">
                  <div class="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                    <.icon name="hero-question-mark-circle" class="h-5 w-5 text-blue-600" />
                  </div>
                  <div class="ml-3">
                    <p class="text-xs text-gray-500">Total Questions</p>
                    <p class="text-xl font-bold text-gray-900">{@total_questions}</p>
                  </div>
                </div>
              </div>
              <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
                <div class="flex items-center">
                  <div class="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                    <.icon name="hero-book-open" class="h-5 w-5 text-green-600" />
                  </div>
                  <div class="ml-3">
                    <p class="text-xs text-gray-500">Subjects</p>
                    <p class="text-xl font-bold text-gray-900">{@total_subjects}</p>
                  </div>
                </div>
              </div>
              <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
                <div class="flex items-center">
                  <div class="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                    <.icon name="hero-tag" class="h-5 w-5 text-purple-600" />
                  </div>
                  <div class="ml-3">
                    <p class="text-xs text-gray-500">Topics</p>
                    <p class="text-xl font-bold text-gray-900">{@total_topics}</p>
                  </div>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <!-- Upload Section -->
              <div class="lg:col-span-1">
                <div class="bg-white rounded-xl shadow-sm border border-gray-200">
                  <div class="px-5 py-4 border-b border-gray-200">
                    <h2 class="text-base font-semibold text-gray-900">Upload Questions</h2>
                    <p class="text-xs text-gray-500 mt-1">Upload a ZIP or RAR file containing MCQ JSON files</p>
                  </div>

                  <div class="p-5 space-y-4">
                    <!-- Degree selector -->
                    <form phx-change="select_degree">
                      <label class="block text-sm font-medium text-gray-700 mb-1">Degree</label>
                      <select
                        name="degree_id"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-black text-sm focus:ring-2 focus:ring-orange-500 focus:border-orange-500"
                      >
                        <option value="">Select degree...</option>
                        <%= for deg <- @degree_options do %>
                          <option value={deg.id} selected={@selected_degree == deg.id}>{deg.name}</option>
                        <% end %>
                      </select>
                    </form>

                    <!-- Specialization selector -->
                    <form phx-change="select_spec">
                      <label class="block text-sm font-medium text-gray-700 mb-1">Specialization</label>
                      <select
                        name="spec_id"
                        disabled={@spec_options == []}
                        class={[
                          "w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-orange-500 focus:border-orange-500",
                          if(@spec_options == [], do: "bg-gray-100 text-gray-400 cursor-not-allowed", else: "text-black")
                        ]}
                      >
                        <option value="">{if @spec_options == [], do: "Select degree first", else: "Select specialization..."}</option>
                        <%= for spec <- @spec_options do %>
                          <option value={spec.id} selected={@selected_spec == spec.id}>{spec.name}</option>
                        <% end %>
                      </select>
                    </form>

                    <form id="upload-form" phx-submit="upload_questions" phx-change="validate_upload">
                      <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-orange-400 transition-colors">
                        <.live_file_input upload={@uploads.question_zip} class="hidden" />
                        <label for={@uploads.question_zip.ref} class="cursor-pointer">
                          <.icon name="hero-arrow-up-tray" class="h-8 w-8 text-gray-400 mx-auto mb-2" />
                          <p class="text-sm text-gray-600">Click to select ZIP or RAR file</p>
                          <p class="text-xs text-gray-400 mt-1">Max 100MB</p>
                        </label>
                      </div>

                      <!-- Upload entries -->
                      <%= for entry <- @uploads.question_zip.entries do %>
                        <div class="mt-3 flex items-center justify-between bg-gray-50 rounded-lg p-3">
                          <div class="flex items-center">
                            <.icon name="hero-document" class="h-5 w-5 text-gray-500 mr-2" />
                            <div>
                              <p class="text-sm font-medium text-gray-900">{entry.client_name}</p>
                              <p class="text-xs text-gray-500">{Float.round(entry.client_size / 1_000_000, 1)} MB</p>
                            </div>
                          </div>
                          <div class="w-20">
                            <div class="bg-gray-200 rounded-full h-1.5">
                              <div class="bg-orange-500 h-1.5 rounded-full" style={"width: #{entry.progress}%"}></div>
                            </div>
                          </div>
                        </div>

                        <%= for err <- upload_errors(@uploads.question_zip, entry) do %>
                          <p class="mt-1 text-xs text-red-600">{error_to_string(err)}</p>
                        <% end %>
                      <% end %>

                      <button
                        type="submit"
                        disabled={@uploading? or @uploads.question_zip.entries == [] or is_nil(@selected_spec)}
                        class={[
                          "w-full mt-4 px-4 py-2.5 text-sm font-medium text-white rounded-lg transition-colors",
                          "disabled:opacity-50 disabled:cursor-not-allowed",
                          if(@uploading?, do: "bg-orange-400", else: "bg-orange-500 hover:bg-orange-600")
                        ]}
                      >
                        <%= if @uploading? do %>
                          <.icon name="hero-arrow-path" class="animate-spin h-4 w-4 inline mr-1" />
                          Processing...
                        <% else %>
                          Upload & Import
                        <% end %>
                      </button>
                    </form>

                    <!-- Upload Result -->
                    <%= if @upload_result do %>
                      <div class="mt-4 p-3 bg-green-50 border border-green-200 rounded-lg">
                        <div class="flex items-start justify-between">
                          <div>
                            <p class="text-sm font-medium text-green-800">Import Complete</p>
                            <p class="text-xs text-green-700 mt-1">
                              +{@upload_result.imported} new, {@upload_result.skipped} duplicates skipped
                            </p>
                            <%= if MapSet.size(@upload_result.subjects) > 0 do %>
                              <p class="text-xs text-green-600 mt-1">
                                Subjects: {Enum.join(@upload_result.subjects, ", ")}
                              </p>
                            <% end %>
                          </div>
                          <button phx-click="dismiss_result" class="text-green-500 hover:text-green-700">
                            <.icon name="hero-x-mark" class="h-4 w-4" />
                          </button>
                        </div>
                      </div>
                    <% end %>

                    <!-- Expected Format -->
                    <div class="mt-4 p-3 bg-slate-50 rounded-lg">
                      <p class="text-xs font-medium text-slate-600 mb-1">Expected structure:</p>
                      <pre class="text-[10px] text-slate-500 leading-relaxed">Root Folder/
  Subject Name/
    Chapter Name/
      Chapter.txt  (JSON array)</pre>
                      <p class="text-xs text-slate-500 mt-2">Each .txt = JSON array with question, options, correct_answer, difficulty, topic fields. Topic is read from JSON.</p>
                      <p class="text-xs text-slate-500 mt-2">Multi-branch archives auto-split: if the first folder matches a specialization of the selected degree (e.g. <span class="font-mono">FINANCE</span>, <span class="font-mono">HR</span>), those files are routed to that specialization automatically — the next folder becomes the subject. Unmatched files use the specialization selected above.</p>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Branches with question data -->
              <div class="lg:col-span-2 space-y-6">
                <div class="bg-white rounded-xl shadow-sm border border-gray-200">
                  <div class="px-5 py-4 border-b border-gray-200 flex items-center justify-between gap-3">
                    <div>
                      <h2 class="text-base font-semibold text-gray-900">Branches with data</h2>
                      <p class="text-xs text-gray-500 mt-0.5">Branches that have subjects mapped. Click a row to see its subjects.</p>
                    </div>
                    <span class="text-xs text-gray-400 whitespace-nowrap">{length(@branch_stats)} branches</span>
                  </div>

                  <div :if={@branch_stats == []} class="px-5 py-12 text-center">
                    <.icon name="hero-inbox" class="h-10 w-10 text-gray-300 mx-auto mb-2" />
                    <p class="text-sm text-gray-500">No branch has subject data yet. Upload questions to populate one.</p>
                  </div>

                  <div :if={@branch_stats != []} class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-gray-200">
                      <thead class="bg-gray-50">
                        <tr>
                          <th class="px-5 py-2.5 text-left text-xs font-medium text-gray-500 uppercase">Branch</th>
                          <th class="px-5 py-2.5 text-left text-xs font-medium text-gray-500 uppercase">Degree</th>
                          <th class="px-5 py-2.5 text-right text-xs font-medium text-gray-500 uppercase">Subjects</th>
                          <th class="px-5 py-2.5 text-right text-xs font-medium text-gray-500 uppercase">Topics</th>
                          <th class="px-5 py-2.5 text-right text-xs font-medium text-gray-500 uppercase">Questions</th>
                          <th class="px-5 py-2.5 text-right text-xs font-medium text-gray-500 uppercase"></th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-gray-100">
                        <tr :for={branch <- @branch_stats}
                          class={[
                            "hover:bg-orange-50/60 cursor-pointer transition-colors",
                            @selected_branch && @selected_branch.id == branch.id && "bg-orange-50"
                          ]}
                          phx-click="select_branch"
                          phx-value-id={branch.id}
                        >
                          <td class="px-5 py-3 text-sm font-medium text-gray-900">{branch.name}</td>
                          <td class="px-5 py-3 text-sm text-gray-500">{branch.degree_name}</td>
                          <td class="px-5 py-3 text-sm text-gray-600 text-right">{branch.subject_count}</td>
                          <td class="px-5 py-3 text-sm text-gray-600 text-right">{branch.topic_count}</td>
                          <td class="px-5 py-3 text-right">
                            <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium " <> question_count_class(branch.question_count)}>
                              {branch.question_count}
                            </span>
                          </td>
                          <td class="px-5 py-3 text-right">
                            <.icon name="hero-chevron-right" class="h-4 w-4 text-gray-400 inline" />
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>
            </div>

            <!-- Subjects drawer for the selected branch -->
            <div :if={@selected_branch} class="fixed inset-0 z-50 overflow-hidden" phx-window-keydown="close_branch" phx-key="Escape">
              <div class="absolute inset-0 bg-gray-900/40" phx-click="close_branch"></div>
              <div class="absolute right-0 top-0 h-full w-full max-w-md bg-white shadow-2xl flex flex-col">
                <div class="px-5 py-4 border-b border-gray-200 flex items-start justify-between gap-3">
                  <div class="flex items-start gap-3 min-w-0">
                    <span class="shrink-0 h-9 w-9 rounded-xl bg-orange-50 text-orange-500 flex items-center justify-center">
                      <.icon name="hero-academic-cap-solid" class="h-4 w-4" />
                    </span>
                    <div class="min-w-0">
                      <h3 class="text-base font-bold text-gray-900 truncate">{@selected_branch.name}</h3>
                      <p class="text-[11px] text-gray-400">
                        {@selected_branch.degree_name} · {@selected_branch.subject_count} subjects · {@selected_branch.question_count} questions
                      </p>
                    </div>
                  </div>
                  <button phx-click="close_branch" class="text-gray-400 hover:text-gray-600 shrink-0" aria-label="Close">
                    <.icon name="hero-x-mark" class="h-6 w-6" />
                  </button>
                </div>

                <div class="flex-1 overflow-y-auto p-4 space-y-2">
                  <p :if={@branch_subjects == []} class="text-sm text-gray-400 text-center py-8">No subjects in this branch.</p>

                  <div :for={subject <- @branch_subjects} class="border border-gray-100 rounded-xl overflow-hidden">
                    <button phx-click="select_subject" phx-value-id={subject.id} class="w-full flex items-center justify-between gap-3 px-4 py-3 hover:bg-gray-50 text-left">
                      <div class="min-w-0">
                        <p class="text-sm font-semibold text-gray-900 truncate">{subject.name}</p>
                        <p class="text-[11px] text-gray-400">{subject.topic_count} topics · {subject.count} questions</p>
                      </div>
                      <div class="flex items-center gap-2 shrink-0">
                        <span class={"px-2 py-0.5 rounded-full text-xs font-medium " <> question_count_class(subject.count)}>{subject.count}</span>
                        <.icon name={if @selected_subject && @selected_subject.id == subject.id, do: "hero-chevron-down", else: "hero-chevron-right"} class="h-4 w-4 text-gray-400" />
                      </div>
                    </button>

                    <!-- Topics + delete when this subject is expanded -->
                    <div :if={@selected_subject && @selected_subject.id == subject.id} class="border-t border-gray-100 bg-gray-50/60 px-4 py-2">
                      <!-- Header -->
                      <div class="grid grid-cols-[1fr_40px_40px_40px_48px] items-center text-[10px] font-medium uppercase tracking-wide px-1 pb-1">
                        <span class="text-gray-400">Topic</span>
                        <span class="text-center text-green-600">Easy</span>
                        <span class="text-center text-yellow-600">Med</span>
                        <span class="text-center text-red-600">Hard</span>
                        <span class="text-center text-gray-500">Total</span>
                      </div>

                      <!-- Empty state -->
                      <p :if={@topic_stats == []} class="text-xs text-gray-400 py-2 text-center">
                        No topics.
                      </p>

                      <!-- Topic rows -->
                      <div
                        :for={topic <- @topic_stats}
                        class="grid grid-cols-[1fr_40px_40px_40px_48px] items-center py-1.5 px-1 text-xs border-t border-gray-100"
                      >
                        <span class="truncate text-gray-700">{topic.name}</span>
                        <span class="text-center text-green-600 tabular-nums">{topic.easy}</span>
                        <span class="text-center text-yellow-600 tabular-nums">{topic.medium}</span>
                        <span class="text-center text-red-600 tabular-nums">{topic.hard}</span>
                        <span class="text-center font-semibold text-gray-700 tabular-nums">{topic.count}</span>
                      </div>

                      <!-- Delete button -->
                      <div class="pt-2 mt-1 border-t border-gray-100 flex justify-end">
                        <button
                          phx-click="delete_subject"
                          phx-value-id={subject.id}
                          phx-value-name={subject.name}
                          data-confirm={"Delete \\"#{subject.name}\\" and all its #{subject.count} questions? This cannot be undone."}
                          class="text-xs text-red-500 hover:text-red-700 inline-flex items-center gap-1"
                        >
                          <.icon name="hero-trash" class="h-3.5 w-3.5" />
                          Delete subject
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
        </div>
      </.admin_layout>
    </Layouts.app>
    """
  end

  defp question_count_class(count) when count >= 1000, do: "bg-green-100 text-green-800"
  defp question_count_class(count) when count >= 100, do: "bg-blue-100 text-blue-800"
  defp question_count_class(count) when count > 0, do: "bg-yellow-100 text-yellow-800"
  defp question_count_class(_), do: "bg-gray-100 text-gray-500"

  defp error_to_string(:too_large), do: "File is too large (max 100MB)"
  defp error_to_string(:not_accepted), do: "Only .zip and .rar files are accepted"
  defp error_to_string(:too_many_files), do: "Only one file at a time"
  defp error_to_string(err), do: inspect(err)
end
