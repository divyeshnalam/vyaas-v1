defmodule VyaasaCampus.AI.MiniProjectFileExtractor do
  @moduledoc """
  Extracts plain text from student-submitted project files.
  Supports PDF (via pdftotext), DOCX/PPTX (via pandoc), CSV, plain text, and
  ZIP archives (each supported member is extracted and concatenated).
  Returns {:ok, text} or {:error, reason}.
  """

  require Logger

  @max_bytes 20 * 1024 * 1024
  @max_text_chars 40_000
  @max_zip_members 50

  @supported_extensions ~w(.pdf .docx .pptx .doc .txt .md .csv .py .js .ts .html .json .xml .xlsx .zip)

  def extract(filename, binary) when is_binary(binary) do
    cond do
      byte_size(binary) > @max_bytes ->
        {:error, "File exceeds 20 MB limit"}

      true ->
        ext = filename |> Path.extname() |> String.downcase()
        do_extract(ext, filename, binary)
    end
  end

  def supported?(filename) do
    ext = filename |> Path.extname() |> String.downcase()
    ext in @supported_extensions
  end

  # ── Extractors ────────────────────────────────────────────────────────────

  defp do_extract(".pdf", filename, binary) do
    with_temp_file(binary, ".pdf", fn path ->
      case System.cmd("pdftotext", [path, "-"], stderr_to_stdout: false) do
        {text, 0} -> {:ok, truncate(text)}
        {err, _} ->
          Logger.warning("pdftotext failed for #{filename}: #{String.slice(err, 0, 200)}")
          {:error, "Could not extract PDF text"}
      end
    end)
  end

  defp do_extract(ext, filename, binary) when ext in [".docx", ".doc", ".pptx"] do
    with_temp_file(binary, ext, fn path ->
      case System.cmd("pandoc", [path, "-t", "plain", "--wrap=none"],
                      stderr_to_stdout: false) do
        {text, 0} -> {:ok, truncate(text)}
        {err, _} ->
          Logger.warning("pandoc failed for #{filename}: #{String.slice(err, 0, 200)}")
          {:error, "Could not extract document text"}
      end
    end)
  end

  defp do_extract(".csv", _filename, binary) do
    text =
      binary
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    {:ok, truncate(text)}
  end

  defp do_extract(".xlsx", filename, binary) do
    with_temp_file(binary, ".xlsx", fn path ->
      case System.cmd("pandoc", [path, "-t", "plain"], stderr_to_stdout: false) do
        {text, 0} -> {:ok, truncate(text)}
        {_, _} ->
          Logger.warning("pandoc XLSX failed for #{filename}, trying ssconvert fallback")
          {:error, "Could not extract spreadsheet text"}
      end
    end)
  end

  defp do_extract(ext, _filename, binary)
       when ext in [".txt", ".md", ".py", ".js", ".ts", ".html", ".json", ".xml"] do
    case :unicode.characters_to_binary(binary, :utf8, :utf8) do
      text when is_binary(text) -> {:ok, truncate(text)}
      _ -> {:ok, truncate(binary)}
    end
  end

  defp do_extract(".zip", filename, binary) do
    case :zip.extract(binary, [:memory]) do
      {:ok, members} ->
        text =
          members
          |> Enum.map(fn {name, content} -> {to_string(name), content} end)
          # Skip junk, directories, and nested zips (no recursive unpacking).
          |> Enum.reject(fn {name, _} -> zip_skip?(name) end)
          |> Enum.filter(fn {name, _} ->
            supported?(name) and not String.ends_with?(String.downcase(name), ".zip")
          end)
          |> Enum.take(@max_zip_members)
          |> Enum.map(fn {name, content} ->
            case extract(name, content) do
              {:ok, t} when byte_size(t) > 0 -> "\n\n===== #{name} =====\n#{t}"
              _ -> ""
            end
          end)
          |> Enum.join("")
          |> String.trim()

        if text == "",
          do: {:error, "The ZIP contained no readable documents"},
          else: {:ok, truncate(text)}

      {:error, reason} ->
        Logger.warning("zip extract failed for #{filename}: #{inspect(reason)}")
        {:error, "Could not read the ZIP archive"}
    end
  end

  defp do_extract(ext, filename, _binary) do
    Logger.warning("Unsupported file type #{ext} for #{filename}")
    {:error, "Unsupported file type: #{ext}"}
  end

  # Junk/unsafe zip members: directories, macOS resource forks, dotfiles.
  defp zip_skip?(name) do
    base = Path.basename(name)
    String.ends_with?(name, "/") or String.starts_with?(name, "__MACOSX") or
      String.starts_with?(base, ".")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp with_temp_file(binary, ext, fun) do
    path = System.tmp_dir!() |> Path.join("mp_upload_#{:rand.uniform(999_999)}#{ext}")

    try do
      File.write!(path, binary)
      fun.(path)
    after
      File.rm(path)
    end
  rescue
    e ->
      Logger.error("File extraction error: #{inspect(e)}")
      {:error, "File processing error"}
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @max_text_chars do
      String.slice(text, 0, @max_text_chars) <> "\n\n[...truncated]"
    else
      text
    end
  end
end
