defmodule VyaasaCampus.AI.Resume.Extractor do
  @moduledoc """
  Resume text + hyperlink extraction for PDF, DOCX, TXT.

  Returns `{:ok, %{text, links, page_count}}` or `{:error, reason}`.

  PDF: shells out to `pdftotext` (poppler-utils). URLs are recovered by regex
  over the extracted text — annotation-level hyperlinks are not preserved by
  pdftotext, but the regex catches URLs that appear in the text body, which is
  what 95% of resumes have.

  DOCX: uses Erlang's :zip + :xmerl to walk the OOXML payload directly. No
  Python equivalent dep required.

  TXT: trivial.
  """

  @url_regex ~r/https?:\/\/[^\s<>"'()]+|www\.[^\s<>"'()]+/

  # Bare (scheme-less, no "www.") links for well-known profile/code platforms,
  # e.g. "github.com/user/repo" or "linkedin.com/in/x" written as plain text —
  # these are common on resumes and the http/www regex above misses them. Scoped
  # to a known platform list + a required path segment to avoid false positives.
  @bare_known_regex ~r/\b(?:github|gitlab|bitbucket|linkedin|behance|dribbble|medium|kaggle|leetcode|hackerrank|codepen|stackoverflow|gitlab|twitter)\.[a-z]{2,}\/[^\s<>"'()]+/i

  @doc """
  Extract from an arbitrary file. `filename` is used to detect the format.
  `binary` is the raw file bytes.
  """
  def extract(binary, filename) when is_binary(binary) and is_binary(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".pdf" -> extract_pdf(binary)
      ".docx" -> extract_docx(binary)
      ".txt" -> extract_txt(binary)
      ext -> {:error, "Unsupported format: #{ext}"}
    end
  end

  @doc "Extract from a path on disk (reads file then dispatches)."
  def extract_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, bin} -> extract(bin, path)
      {:error, reason} -> {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  # ----------------------------------------------------------------------
  # PDF — pdftotext shell-out
  # ----------------------------------------------------------------------

  defp extract_pdf(binary) do
    tmp = Path.join(System.tmp_dir!(), "resume_#{System.unique_integer([:positive])}.pdf")

    try do
      File.write!(tmp, binary)

      with {:ok, text} <- pdftotext(tmp),
           {:ok, page_count} <- pdf_pages(tmp) do
        # Merge URLs printed in the body with hyperlink-annotation URLs that
        # pdftotext drops (e.g. the resume shows "LinkedIn" but the URL is
        # embedded as a /URI link action).
        links =
          (find_urls(text) ++ pdf_annotation_links(binary))
          |> Enum.uniq_by(& &1.uri)

        {:ok, %{text: text, links: links, page_count: page_count}}
      end
    after
      File.rm(tmp)
    end
  rescue
    e -> {:error, "PDF extraction failed: #{Exception.message(e)}"}
  end

  defp pdftotext(path) do
    # NOTE: do NOT merge stderr into stdout — pdftotext prints syntax warnings to
    # stderr and we capture stdout as the resume text. Merging would pollute the
    # parsed text (and the LLM prompt) with "Syntax Warning: ..." lines.
    case System.cmd("pdftotext", ["-layout", "-enc", "UTF-8", path, "-"]) do
      {text, 0} -> {:ok, text}
      {_out, code} -> {:error, "pdftotext exit #{code}"}
    end
  end

  defp pdf_pages(path) do
    case System.cmd("pdfinfo", [path], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/Pages:\s+(\d+)/, output) do
          [_, n] -> {:ok, String.to_integer(n)}
          _ -> {:ok, 1}
        end

      _ ->
        {:ok, 1}
    end
  end

  @doc """
  DOCX split into paragraphs, for showing a document to a human.

  `extract/2` flattens the whole file into one whitespace-collapsed string —
  what the scoring prompts want, but a wall of text on screen. This keeps the
  `<w:p>` boundaries so a preview can render a resume line by line. Formatting
  (fonts, columns, tables, images) is not recovered; this is a readable
  approximation, not a rendition of the document.

  Returns `{:ok, [paragraph]}` or `{:error, reason}`.
  """
  def docx_paragraphs(binary) when is_binary(binary) do
    with {:ok, files} <- unzip_in_memory(binary),
         {:ok, doc_xml} <- fetch(files, ~c"word/document.xml") do
      paragraphs =
        doc_xml
        |> String.split("</w:p>")
        |> Enum.map(&docx_text/1)
        |> Enum.reject(&(&1 == ""))

      {:ok, paragraphs}
    end
  rescue
    e -> {:error, "DOCX preview failed: #{Exception.message(e)}"}
  end

  @doc "As `docx_paragraphs/1`, reading the DOCX from disk."
  def docx_paragraphs_from_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, bin} -> docx_paragraphs(bin)
      {:error, reason} -> {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  # ----------------------------------------------------------------------
  # DOCX — unzip + walk word/document.xml + word/_rels/document.xml.rels
  # ----------------------------------------------------------------------

  defp extract_docx(binary) do
    with {:ok, files} <- unzip_in_memory(binary),
         {:ok, doc_xml} <- fetch(files, ~c"word/document.xml") do
      text = docx_text(doc_xml)
      rel_links = case fetch(files, ~c"word/_rels/document.xml.rels") do
        {:ok, rels_xml} -> docx_hyperlinks(rels_xml)
        _ -> []
      end

      regex_links = find_urls(text)
      links = (rel_links ++ regex_links) |> Enum.uniq_by(& &1.uri)

      word_count = text |> String.split() |> length()
      page_count = max(1, round(word_count / 250))

      {:ok, %{text: text, links: links, page_count: page_count}}
    end
  rescue
    e -> {:error, "DOCX extraction failed: #{Exception.message(e)}"}
  end

  defp unzip_in_memory(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, "Invalid DOCX (zip) file: #{inspect(reason)}"}
    end
  end

  defp fetch(files, name) do
    case List.keyfind(files, name, 0) do
      {^name, contents} -> {:ok, contents}
      _ -> {:error, "Missing #{name} in DOCX"}
    end
  end

  # Collect text from all <w:t> nodes. We use a simple regex over the XML —
  # robust enough for word/document.xml which has a flat namespace.
  defp docx_text(xml) when is_binary(xml) do
    Regex.scan(~r/<w:t[^>]*>([^<]*)<\/w:t>/, xml, capture: :all_but_first)
    |> Enum.map(fn [t] -> decode_xml_entities(t) end)
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp docx_hyperlinks(rels_xml) do
    Regex.scan(~r/Type="[^"]*hyperlink"\s+Target="([^"]+)"/i, rels_xml, capture: :all_but_first)
    |> Enum.map(fn [uri] -> %{text: uri, uri: decode_xml_entities(uri)} end)
  end

  defp decode_xml_entities(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  # ----------------------------------------------------------------------
  # TXT
  # ----------------------------------------------------------------------

  defp extract_txt(binary) do
    text = binary |> :unicode.characters_to_binary(:utf8, :utf8) |> to_string()
    links = find_urls(text)
    page_count = max(1, round(length(String.split(text)) / 250))
    {:ok, %{text: text, links: links, page_count: page_count}}
  rescue
    e -> {:error, "TXT extraction failed: #{Exception.message(e)}"}
  end

  # ----------------------------------------------------------------------
  # Shared helpers
  # ----------------------------------------------------------------------

  defp find_urls(text) when is_binary(text) do
    scheme_urls = Regex.scan(@url_regex, text) |> Enum.map(fn [url] -> url end)
    bare_urls = Regex.scan(@bare_known_regex, text) |> Enum.map(fn [url] -> url end)

    (scheme_urls ++ bare_urls)
    |> Enum.map(&%{text: &1, uri: &1})
    # A bare "github.com/x" is a duplicate of "https://github.com/x" — drop it.
    |> Enum.uniq_by(fn %{uri: u} -> String.replace(u, ~r{^https?://(www\.)?}i, "") end)
  end

  # Recover hyperlink-annotation URLs that pdftotext drops. PDF link actions are
  # stored as `/URI (http://...)` (or `/URI <hex>`) either in the raw bytes or
  # inside FlateDecode-compressed object streams (PDF 1.5+). We scan both.
  defp pdf_annotation_links(binary) when is_binary(binary) do
    from_raw = scan_uri_actions(binary)

    from_streams =
      Regex.scan(~r/stream\r?\n(.*?)\r?\nendstream/s, binary, capture: :all_but_first)
      |> Enum.flat_map(fn [chunk] ->
        case inflate(chunk) do
          {:ok, data} -> scan_uri_actions(data)
          :error -> []
        end
      end)

    (from_raw ++ from_streams)
    |> Enum.uniq()
    |> Enum.map(fn uri -> %{text: uri, uri: uri} end)
  end

  defp scan_uri_actions(data) when is_binary(data) do
    literal =
      Regex.scan(~r/\/URI\s*\(([^)]*)\)/, data, capture: :all_but_first)
      |> Enum.map(fn [s] -> unescape_pdf_string(s) end)

    hex =
      Regex.scan(~r/\/URI\s*<([0-9A-Fa-f\s]+)>/, data, capture: :all_but_first)
      |> Enum.map(fn [h] -> decode_pdf_hex(h) end)

    (literal ++ hex)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&valid_uri?/1)
  end

  defp scan_uri_actions(_), do: []

  defp unescape_pdf_string(s) do
    s
    |> String.replace("\\(", "(")
    |> String.replace("\\)", ")")
    |> String.replace("\\\\", "\\")
  end

  defp decode_pdf_hex(h) do
    case h |> String.replace(~r/\s/, "") |> Base.decode16(case: :mixed) do
      {:ok, bin} -> bin
      :error -> ""
    end
  end

  defp valid_uri?(s), do: String.match?(s, ~r/^(https?:\/\/|www\.|mailto:)/i)

  # Inflate a FlateDecode stream chunk; returns :error for non-flate streams
  # (images, raw data) so callers can skip them.
  defp inflate(chunk) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z)
      data = z |> :zlib.inflate(chunk) |> IO.iodata_to_binary()
      :zlib.inflateEnd(z)
      {:ok, data}
    rescue
      _ -> :error
    catch
      _, _ -> :error
    after
      :zlib.close(z)
    end
  end

  @doc "Cleanup whitespace and non-printables — port of Python's clean_text."
  def clean_text(text) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end
end
