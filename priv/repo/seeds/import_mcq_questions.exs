# Import MCQ questions from JSON files into public.qa table
#
# Usage:
#   mix run priv/repo/seeds/import_mcq_questions.exs "/path/to/questions/folder"
#
# Folder structure expected:
#   /folder/
#     └── Subject Name/
#          └── Topic Group/
#               └── Topic.txt  (JSON array of MCQ questions)
#
# Each question JSON:
#   { "question": "...", "options": ["A","B","C","D"], "correct_answer": "B", "difficulty": "Beginner", "topic": "..." }

alias VyaasaCampus.Repo
require Logger

# --- Configuration ---
# The curricula_id and branch_id to link questions to.
# Update these if importing for a different curriculum/branch.
default_curricula_id = 1
default_branch_id = 1

# Get folder path from CLI args or use default
base_path =
  case System.argv() do
    [path | _] -> path
    _ -> "/home/geekbull-ravi/Downloads/computer science and engineering"
  end

unless File.dir?(base_path) do
  Logger.error("Directory not found: #{base_path}")
  System.halt(1)
end

Logger.info("Importing MCQ questions from: #{base_path}")

# --- Helper: normalize difficulty to match select_questions SQL expectations ---
normalize_difficulty = fn diff ->
  case String.downcase(String.trim(diff || "medium")) do
    "beginner" -> "easy"
    "easy" -> "easy"
    "basic" -> "easy"
    "intermediate" -> "medium"
    "medium" -> "medium"
    "moderate" -> "medium"
    "advanced" -> "hard"
    "hard" -> "hard"
    "difficult" -> "hard"
    "expert" -> "hard"
    other -> other
  end
end

# --- Helper: convert options array to map {"a" => ..., "b" => ..., "c" => ..., "d" => ...} ---
convert_options = fn options when is_list(options) ->
  labels = ~w(a b c d e f g h)
  options
  |> Enum.with_index()
  |> Enum.into(%{}, fn {opt, idx} -> {Enum.at(labels, idx, "x"), opt} end)
end

# --- Helper: find correct answer key from options ---
find_answer_key = fn correct_answer, options_map ->
  case Enum.find(options_map, fn {_k, v} -> v == correct_answer end) do
    {key, _} -> key
    nil -> "a"
  end
end

# --- Step 1: Get or create subjects ---
get_or_create_subject = fn subject_name ->
  query = "SELECT id FROM public.subjects WHERE name = $1 LIMIT 1"
  case Repo.query(query, [subject_name]) do
    {:ok, %{rows: [[id] | _]}} ->
      id
    _ ->
      # Generate a code from the name
      code = subject_name
             |> String.upcase()
             |> String.replace(~r/[^A-Z0-9]/, "")
             |> String.slice(0, 10)
      code = code <> "#{:rand.uniform(999)}"

      insert_q = "INSERT INTO public.subjects (name, code, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id"
      case Repo.query(insert_q, [subject_name, code]) do
        {:ok, %{rows: [[id] | _]}} ->
          Logger.info("  Created subject: #{subject_name} (id=#{id})")

          # Link to curricula_subjects
          link_q = "INSERT INTO public.curricula_subjects (curricula_id, subject_id, branch_id, inserted_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) ON CONFLICT DO NOTHING"
          Repo.query(link_q, [default_curricula_id, id, default_branch_id])

          id
        {:error, reason} ->
          Logger.error("  Failed to create subject #{subject_name}: #{inspect(reason)}")
          nil
      end
  end
end

# --- Step 2: Get or create topics ---
get_or_create_topic = fn topic_name, subject_id ->
  query = "SELECT id FROM public.topics WHERE name = $1 AND subject_id = $2 LIMIT 1"
  case Repo.query(query, [topic_name, subject_id]) do
    {:ok, %{rows: [[id] | _]}} ->
      id
    _ ->
      insert_q = "INSERT INTO public.topics (name, subject_id, type, weightage, inserted_at, updated_at) VALUES ($1, $2, 'topic', 1.0, NOW(), NOW()) RETURNING id"
      case Repo.query(insert_q, [topic_name, subject_id]) do
        {:ok, %{rows: [[id] | _]}} -> id
        {:error, reason} ->
          Logger.error("  Failed to create topic #{topic_name}: #{inspect(reason)}")
          nil
      end
  end
end

# --- Helper: parse JSON that may contain multiple concatenated arrays ---
parse_json_questions = fn content ->
  case Jason.decode(content) do
    {:ok, questions} when is_list(questions) ->
      questions

    {:error, _} ->
      # Try splitting on ]\n[ pattern (multiple arrays concatenated)
      # Replace ][ or ]\n[ with a comma to merge arrays
      merged = Regex.replace(~r/\]\s*\[/, content, ",")
      case Jason.decode(merged) do
        {:ok, questions} when is_list(questions) -> questions
        _ -> []
      end
  end
end

# --- Helper: recursively find all .txt files ---
find_txt_files = fn dir ->
  Path.wildcard(Path.join(dir, "**/*.txt"))
  |> Enum.sort()
end

# --- Step 3: Walk the directory and import ---
subject_dirs = File.ls!(base_path)
  |> Enum.filter(fn name -> File.dir?(Path.join(base_path, name)) end)
  |> Enum.sort()

total_imported = Enum.reduce(subject_dirs, 0, fn subject_dir, total_acc ->
  subject_name = subject_dir
    |> String.replace(" Curriculum Overview", "")
    |> String.trim()

  subject_path = Path.join(base_path, subject_dir)
  Logger.info("\nProcessing subject: #{subject_name}")

  subject_id = get_or_create_subject.(subject_name)

  if is_nil(subject_id) do
    Logger.error("Skipping subject #{subject_name} - could not get/create")
    total_acc
  else
    # Recursively find all .txt files under this subject
    txt_files = find_txt_files.(subject_path)

    subject_count = Enum.reduce(txt_files, 0, fn file_path, file_acc ->
      # Use the filename (without .txt) as the topic name
      topic_name = Path.basename(file_path, ".txt") |> String.trim()

      # Try to parse JSON - handle files with multiple concatenated JSON arrays
      case File.read(file_path) do
        {:ok, content} ->
          # Normalize line endings and try to extract all JSON arrays
          content = String.replace(content, "\r\n", "\n")
          parsed = parse_json_questions.(content)
          case parsed do
            questions when is_list(questions) and length(questions) > 0 ->
              topic_id = get_or_create_topic.(topic_name, subject_id)

              if is_nil(topic_id) do
                file_acc
              else
                inserted = Enum.reduce(questions, 0, fn q, q_acc ->
                  question_text = q["question"]
                  raw_options = q["options"] || []
                  correct_answer = q["correct_answer"] || ""
                  difficulty = normalize_difficulty.(q["difficulty"])

                  options_map = convert_options.(raw_options)
                  answer_key = find_answer_key.(correct_answer, options_map)

                  # Check for duplicate
                  dup_q = "SELECT id FROM public.qa WHERE question = $1 AND topic_id = $2 LIMIT 1"
                  case Repo.query(dup_q, [question_text, topic_id]) do
                    {:ok, %{rows: [_ | _]}} ->
                      q_acc  # skip duplicate

                    _ ->
                      insert_q = """
                      INSERT INTO public.qa (question, answer, options, difficulty_level, type, weightage, topic_id, inserted_at, updated_at)
                      VALUES ($1, $2, $3, $4, 'multiple_choice', 1.0, $5, NOW(), NOW())
                      """
                      case Repo.query(insert_q, [question_text, answer_key, options_map, difficulty, topic_id]) do
                        {:ok, _} -> q_acc + 1
                        {:error, reason} ->
                          Logger.error("    Failed to insert question: #{inspect(reason)}")
                          q_acc
                      end
                  end
                end)

                if inserted > 0 do
                  Logger.info("  #{topic_name}: +#{inserted} questions")
                end

                file_acc + inserted
              end

            _ ->
              file_acc  # not valid JSON
          end

        _ ->
          file_acc
      end
    end)

    Logger.info("  Subject total: #{subject_count} new questions")
    total_acc + subject_count
  end
end)

# Final summary
{:ok, %{rows: [[qa_count]]}} = Repo.query("SELECT COUNT(*)::integer FROM public.qa")
Logger.info("\n========================================")
Logger.info("Import complete!")
Logger.info("New questions imported: #{total_imported}")
Logger.info("Total questions in database: #{qa_count}")
Logger.info("========================================")
