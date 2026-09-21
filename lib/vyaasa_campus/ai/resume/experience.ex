defmodule VyaasaCampus.AI.Resume.Experience do
  @moduledoc """
  Compute total non-overlapping years of work experience from parsed
  Work_Experience entries. Port of `calculate_experience_years` and
  `format_experience` from the Python pipeline.
  """

  @date_formats [
    "{0M}/{YYYY}",
    "{M}/{YYYY}",
    "{0M}-{YYYY}",
    "{M}-{YYYY}",
    "{Mshort} {YYYY}",
    "{Mfull} {YYYY}",
    "{Mshort}-{YYYY}",
    "{Mfull}-{YYYY}",
    "{YYYY}/{0M}",
    "{YYYY}-{0M}"
  ]

  @doc """
  Calculate total experience in years from Work_Experience list. Merges
  overlapping intervals so concurrent jobs don't double-count.
  """
  def calculate(work_experience) when is_list(work_experience) do
    intervals =
      work_experience
      |> Enum.map(&parse_interval/1)
      |> Enum.reject(&is_nil/1)

    case intervals do
      [] ->
        0.0

      _ ->
        intervals
        |> Enum.sort_by(fn {start, _end} -> start end, {:asc, NaiveDateTime})
        |> merge_overlaps([])
        |> Enum.reduce(0, fn {s, e}, acc -> acc + months_between(s, e) end)
        |> Kernel./(12)
        |> Float.round(2)
    end
  end

  def calculate(_), do: 0.0

  defp parse_interval(job) when is_map(job) do
    start_str = to_string(job["start_date"] || "")
    end_str = to_string(job["end_date"] || "")

    with {:ok, start_dt} <- parse_date(start_str),
         {:ok, end_dt} <- parse_date_or_now(end_str) do
      if NaiveDateTime.compare(end_dt, start_dt) == :gt do
        {start_dt, end_dt}
      else
        nil
      end
    else
      _ -> nil
    end
  end

  defp parse_interval(_), do: nil

  defp parse_date_or_now(""), do: {:ok, NaiveDateTime.utc_now()}

  defp parse_date_or_now(s) do
    case String.downcase(String.trim(s)) do
      val when val in ["present", "current", "now", "ongoing"] ->
        {:ok, NaiveDateTime.utc_now()}

      _ ->
        parse_date(s)
    end
  end

  defp parse_date(s) when is_binary(s) do
    s = String.trim(s)
    Enum.find_value(@date_formats, {:error, :no_format}, fn fmt ->
      case Timex.parse(s, fmt) do
        {:ok, dt} -> {:ok, NaiveDateTime.new!(dt.year, dt.month, 1, 0, 0, 0)}
        _ -> nil
      end
    end)
  end

  defp parse_date(_), do: {:error, :invalid}

  defp merge_overlaps([], acc), do: Enum.reverse(acc)
  defp merge_overlaps([first | rest], []), do: merge_overlaps(rest, [first])

  defp merge_overlaps([{cs, ce} | rest], [{ls, le} | acc_tail]) do
    if NaiveDateTime.compare(cs, le) == :lt do
      latest_end = if NaiveDateTime.compare(le, ce) == :gt, do: le, else: ce
      merge_overlaps(rest, [{ls, latest_end} | acc_tail])
    else
      merge_overlaps(rest, [{cs, ce}, {ls, le} | acc_tail])
    end
  end

  defp months_between(s, e) do
    diff = Timex.diff(e, s, :months)
    if diff < 0, do: 0, else: diff
  end

  @doc "Format years as e.g. '2 years, 3 months'."
  def format_experience(years) when is_number(years) and years > 0 do
    y = trunc(years)
    m = round((years - y) * 12)

    parts =
      [
        if(y > 0, do: "#{y} year#{if y == 1, do: "", else: "s"}"),
        if(m > 0, do: "#{m} month#{if m == 1, do: "", else: "s"}")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "Less than a month"
      _ -> Enum.join(parts, ", ")
    end
  end

  def format_experience(_), do: "No experience"

  @doc "True if total experience is below the fresher threshold (2 years)."
  def fresher?(years) when is_number(years), do: years < 2.0
  def fresher?(_), do: true
end
