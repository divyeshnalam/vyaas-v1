defmodule VyaasaCampusWeb.ReportHTML do
  @moduledoc """
  Renders HEEx templates for server-side PDF reports.

  Templates live next to this module in `report_html/*.html.heex` and are
  self-contained HTML documents (with `<head>`, inline CSS, body). They are
  rendered by `Vyaasa.Reports` and piped into ChromicPDF.
  """

  use VyaasaCampusWeb, :html

  embed_templates "report_html/*"

  @doc """
  Renders a report HEEx template for the given type and returns a fully-formed
  HTML document as a UTF-8 binary.
  """
  def render_document(type, assigns) when is_map(assigns) do
    assigns =
      assigns
      |> Map.put(:logo_src, logo_data_uri())
      |> Map.put(:watermark_src, logo_data_uri())
      |> Map.put(:generated_at_display, format_datetime(assigns.generated_at))

    type
    |> render_template(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp render_template(:mcq, assigns), do: mcq(assigns)
  defp render_template(:jam, assigns), do: jam(assigns)
  defp render_template(:psychometric, assigns), do: psychometric(assigns)
  defp render_template(:behavioral, assigns), do: behavioral(assigns)
  defp render_template(:interview, assigns), do: interview(assigns)
  defp render_template(:case_study, assigns), do: case_study(assigns)
  defp render_template(:ai8, assigns), do: ai8(assigns)
  defp render_template(:resume, assigns), do: resume(assigns)
  defp render_template(:leaderboard, assigns), do: leaderboard(assigns)
  defp render_template(:specialization, assigns), do: specialization(assigns)

  # ============================================================================
  # SHARED COMPONENTS
  # ============================================================================

  @doc """
  Common print CSS shared by every report template. Kept in a single place so
  visual tweaks propagate everywhere.
  """
  def common_styles do
    """
    @page { size: A4; margin: 12mm; }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      font-size: 11pt;
      color: #111827;
      background: #ffffff;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    .report { position: relative; }
    .watermark {
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%) ;
      opacity: 0.08;
      z-index: 0;
      pointer-events: none;
      width: 520px;
    }
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 2px solid #f97316;
      padding-bottom: 10px;
      margin-bottom: 16px;
    }
    .brand { display: flex; align-items: center; gap: 10px; }
    .brand img { height: 32px; width: auto; }
    .brand .name { font-size: 14pt; font-weight: 700; color: #111827; }
    .brand .tag  { font-size: 9pt; color: #6b7280; }
    .meta { text-align: right; font-size: 9pt; color: #4b5563; line-height: 1.5; }
    .meta .who { font-weight: 600; color: #111827; }
    .title-block {
      margin: 6px 0 14px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .title-block h1 { margin: 0; font-size: 18pt; color: #111827; }
    .title-block p  { margin: 2px 0 0; font-size: 10pt; color: #6b7280; }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 9999px;
      font-size: 9pt;
      font-weight: 600;
      white-space: nowrap;
    }
    .card {
      border: 1px solid #e5e7eb;
      border-radius: 10px;
      padding: 14px 16px;
      margin-bottom: 12px;
      background: #ffffff;
      page-break-inside: avoid;
    }
    .card h3 {
      margin: 0 0 10px;
      font-size: 11pt;
      font-weight: 600;
      color: #111827;
      letter-spacing: 0.2px;
    }
    .prose { font-size: 10pt; line-height: 1.55; color: #374151; }
    .prose p { margin: 0 0 8px; }
    .grid-2 {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .pill-list { margin: 0; padding-left: 18px; }
    .pill-list li { font-size: 10pt; line-height: 1.5; color: #374151; margin-bottom: 3px; }
    .kv { width: 100%; font-size: 10pt; border-collapse: collapse; }
    .kv td { padding: 4px 0; vertical-align: top; }
    .kv td.key { color: #4b5563; }
    .kv td.val { text-align: right; font-weight: 600; color: #111827; }
    .bar-row { margin-bottom: 10px; }
    .bar-row:last-child { margin-bottom: 0; }
    .bar-row .meta-line {
      display: flex;
      justify-content: space-between;
      font-size: 9pt;
      color: #374151;
      margin-bottom: 4px;
    }
    .bar-row .meta-line .label { font-weight: 600; }
    .bar {
      width: 100%;
      background: #e5e7eb;
      border-radius: 9999px;
      height: 7px;
      overflow: hidden;
    }
    .bar > span { display: block; height: 100%; border-radius: 9999px; }
    .footer {
      margin-top: 14px;
      padding-top: 8px;
      border-top: 1px solid #e5e7eb;
      font-size: 8pt;
      color: #9ca3af;
      text-align: center;
    }
    .score-hero {
      display: flex;
      align-items: center;
      gap: 24px;
    }
    .gauge { position: relative; width: 130px; height: 130px; flex-shrink: 0; }
    .gauge svg { transform: rotate(-90deg); }
    .gauge .center {
      position: absolute; inset: 0;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center; text-align: center;
    }
    .gauge .center .score { font-size: 16pt; font-weight: 700; color: #111827; }
    .gauge .center .label { font-size: 8pt; color: #6b7280; margin-top: 2px; }
    .score-summary { flex: 1; }
    .score-summary .pct { font-size: 30pt; font-weight: 700; line-height: 1; }
    .score-summary .verdict { font-size: 13pt; font-weight: 600; margin-top: 4px; }
    .score-summary .sub { font-size: 9pt; color: #6b7280; margin-top: 8px; }
    .chip {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 6px;
      font-size: 8.5pt;
      font-weight: 600;
      background: #f3f4f6;
      color: #374151;
      margin-right: 4px;
      margin-bottom: 4px;
    }
    h4.section { margin: 12px 0 6px; font-size: 10pt; color: #374151; }
    ul.tight { margin: 0; padding-left: 18px; }
    ul.tight li { font-size: 10pt; line-height: 1.55; color: #374151; margin-bottom: 3px; }
    """
  end

  attr :logo_src, :string, required: true
  attr :student, :map, default: nil
  attr :generated_at_display, :string, required: true

  @doc """
  Shared header block (brand + student meta).
  """
  def report_header(assigns) do
    ~H"""
    <header class="header">
      <div class="brand">
        <img :if={@logo_src != ""} src={@logo_src} alt="Vyaasa" />
        <div>
          <div class="name">Vyaasa</div>
          <div class="tag">Assessment Report</div>
        </div>
      </div>
      <div class="meta">
        <div :if={@student} class="who">
          {@student.first_name} {@student.last_name}
        </div>
        <div :if={@student && @student.email}>{@student.email}</div>
        <div>Generated {format_datetime(@generated_at_display)} </div>
      </div>
    </header>
    """
  end

  attr :watermark_src, :string, required: true

  def report_watermark(assigns) do
    ~H"""
    <img :if={@watermark_src != ""} class="watermark" src={@watermark_src} alt="" />
    """
  end

  attr :generated_at_display, :string, required: true

  def report_footer(assigns) do
    ~H"""
    <div class="footer">
      Vyaasa · Assessment Report · {format_datetime(@generated_at_display)}
    </div>
    """
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  @doc false
  def logo_data_uri do
    case File.read(Path.join(:code.priv_dir(:vyaasa_campus), "static/images/logo.png")) do
      {:ok, bytes} -> "data:image/png;base64," <> Base.encode64(bytes)
      {:error, _} -> ""
    end
  end

  @doc false
  def format_datetime(%DateTime{} = dt) do
    {:ok, shifted} = DateTime.shift_zone(dt, "Asia/Kolkata")
    Calendar.strftime(shifted, "%B %-d, %Y %-I:%M:%S %p IST")
  rescue
    _ -> Calendar.strftime(dt, "%B %-d, %Y %-I:%M:%S %p IST")
  end

  def format_datetime(_), do: ""

  @doc false
  def minutes(seconds) when is_integer(seconds) and seconds >= 0, do: div(seconds, 60)
  def minutes(_), do: 0

  @doc false
  def color_hex(:green), do: "#16a34a"
  def color_hex(:amber), do: "#d97706"
  def color_hex(:orange), do: "#ea580c"
  def color_hex(:red), do: "#dc2626"
  def color_hex(_), do: "#4b5563"

  @doc false
  def tint_hex(:green), do: "#dcfce7"
  def tint_hex(:amber), do: "#fef3c7"
  def tint_hex(:orange), do: "#ffedd5"
  def tint_hex(:red), do: "#fee2e2"
  def tint_hex(_), do: "#f3f4f6"

  @doc false
  def accuracy_bar_color(pct) when pct >= 75, do: "#16a34a"
  def accuracy_bar_color(pct) when pct >= 50, do: "#d97706"
  def accuracy_bar_color(_), do: "#dc2626"

  @doc false
  def clamp_pct(v) when is_number(v), do: max(0.0, min(100.0, v * 1.0))
  def clamp_pct(_), do: 0.0

  @doc """
  Rounds a value to the nearest integer, tolerating nil/strings/Decimals so a
  bad score never crashes a report render (and silently kills its email).
  """
  def safe_round(v) when is_number(v), do: round(v)
  def safe_round(%Decimal{} = d), do: d |> Decimal.to_float() |> round()

  def safe_round(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> round(f)
      :error -> 0
    end
  end

  def safe_round(_), do: 0

  @doc false
  def score_out_of(v, max) when is_number(v) and is_number(max) and max > 0,
    do: Float.round(v / max * 100, 1)

  def score_out_of(_, _), do: 0.0

  @doc """
  Performance color based on a numeric value (same scale as Reports context).
  """
  def perf_color(p) when is_number(p) and p >= 75, do: :green
  def perf_color(p) when is_number(p) and p >= 60, do: :amber
  def perf_color(p) when is_number(p) and p >= 40, do: :orange
  def perf_color(_), do: :red

  @doc false
  def humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def humanize_key(key) when is_atom(key), do: humanize_key(to_string(key))
  def humanize_key(_), do: ""

  # --- leaderboard / specialization helpers -----------------------------------

  @doc false
  def rank_row_class(1), do: "top-1"
  def rank_row_class(2), do: "top-2"
  def rank_row_class(3), do: "top-3"
  def rank_row_class(_), do: ""

  @doc false
  def rank_pill_class(1), do: "rank-1"
  def rank_pill_class(2), do: "rank-2"
  def rank_pill_class(3), do: "rank-3"
  def rank_pill_class(_), do: "rank-default"

  @doc false
  def format_score(nil), do: "-"
  def format_score(%Decimal{} = d), do: d |> Decimal.to_float() |> round() |> Integer.to_string()
  def format_score(n) when is_integer(n), do: Integer.to_string(n)
  def format_score(n) when is_float(n), do: n |> round() |> Integer.to_string()
  def format_score(n), do: to_string(n)
end
