defmodule VyaasaCampus.Reports.TypstRenderer do
  @moduledoc """
  Renders Vyaasa report PDFs via Typst — no Chrome or browser required.

  Each report type has a .typ template in priv/typst/. Context data is
  serialized to a temp JSON file, the Typst CLI compiles it to PDF, and
  the binary is returned. Temp files are always cleaned up.
  """

  require Logger

  @templates_dir Application.app_dir(:vyaasa_campus, "priv/typst")
  @logo_path     Application.app_dir(:vyaasa_campus, "priv/typst/logo.png")
  @seal_path     Application.app_dir(:vyaasa_campus, "priv/static/images/ai8_seal.svg")
  @mark_path     Application.app_dir(:vyaasa_campus, "priv/static/images/vyaasa-mark.svg")
  @ceo_sig_path  Application.app_dir(:vyaasa_campus, "priv/static/images/ceosig.png")
  @cofounder_sig_path Application.app_dir(:vyaasa_campus, "priv/static/images/co-foundersig.png")

  @doc """
  Renders a report PDF for the given type and context map.
  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  def render(type, context) when is_atom(type) and is_map(context) do
    template = Path.join(@templates_dir, "#{type}.typ")
    tmp      = System.tmp_dir!()
    id       = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    data_file = Path.join(tmp, "vyaasa_#{id}.json")
    out_file  = Path.join(tmp, "vyaasa_#{id}.pdf")
    started   = System.monotonic_time(:millisecond)

    try do
      json = context |> inject_meta() |> serialize() |> Jason.encode!()
      File.write!(data_file, json)

      Logger.info("TYPST_PDF | compile | type=#{type} template=#{template}")

      args = [
        "compile", template, out_file,
        "--input", "datafile=#{data_file}",
        "--root", "/"
      ]

      case System.cmd(typst_bin(), args, stderr_to_stdout: true) do
        {_, 0} ->
          pdf = File.read!(out_file)
          ms  = System.monotonic_time(:millisecond) - started
          Logger.info("TYPST_PDF | OK | type=#{type} bytes=#{byte_size(pdf)} ms=#{ms}")
          {:ok, pdf}

        {err, code} ->
          ms = System.monotonic_time(:millisecond) - started
          Logger.error("TYPST_PDF | FAILED | type=#{type} exit=#{code} ms=#{ms}\n#{err}")
          {:error, {:typst_compile_failed, String.trim(err)}}
      end
    rescue
      e ->
        Logger.error("TYPST_PDF | EXCEPTION | #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, {:exception, e}}
    after
      File.rm(data_file)
      File.rm(out_file)
      # Report-type-specific temp assets (e.g. a fetched QR code) aren't ours to
      # know the layout of, so any loader that stashes one under `:_qr_path`
      # is responsible for it existing — we just clean it up here.
      case Map.get(context, :_qr_path) do
        path when is_binary(path) and path != "" -> File.rm(path)
        _ -> :ok
      end
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  # Inject logo/seal paths so templates can show the brand marks.
  defp inject_meta(ctx) do
    ctx
    |> Map.put(:_logo_path, if(File.exists?(@logo_path), do: @logo_path, else: ""))
    |> Map.put(:_seal_path, if(File.exists?(@seal_path), do: @seal_path, else: ""))
    |> Map.put(:_mark_path, if(File.exists?(@mark_path), do: @mark_path, else: ""))
    |> Map.put(:_ceo_sig_path, if(File.exists?(@ceo_sig_path), do: @ceo_sig_path, else: ""))
    |> Map.put(:_cofounder_sig_path, if(File.exists?(@cofounder_sig_path), do: @cofounder_sig_path, else: ""))
  end

  # Serialize an Elixir value to a JSON-safe structure.
  # Handles: structs → maps, DateTime → string, Decimal → float, atoms → strings,
  # tuples → lists, nested maps/lists recursively.
  def serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def serialize(%Date{} = d), do: Date.to_iso8601(d)
  def serialize(%Decimal{} = d), do: Decimal.to_float(d)

  def serialize(%_{} = struct) do
    struct |> Map.from_struct() |> serialize()
  end

  def serialize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), serialize(v)} end)
  end

  def serialize(list) when is_list(list) do
    Enum.map(list, &serialize/1)
  end

  def serialize(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> serialize()
  end

  def serialize(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    Atom.to_string(atom)
  end

  def serialize(value), do: value

  # Resolve Typst binary: prefer system-wide install, fall back to priv/bin/typst.
  defp typst_bin do
    System.find_executable("typst") ||
      Application.app_dir(:vyaasa_campus, "priv/bin/typst")
  end
end
