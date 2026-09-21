defmodule VyaasaCampusWeb.DateTimeFormatter do
  @moduledoc """
  Single source of truth for user-facing date / time / duration formatting.

  Use these helpers in LiveViews, templates and components instead of inline
  `Calendar.strftime/2` calls so the UI stays consistent.

      format_date(~D[2026-04-20])      #=> "Apr 20, 2026"
      format_datetime(utc_datetime)     #=> "Apr 20, 2026 at 03:42 PM IST"
      format_relative(utc_datetime)     #=> "5 minutes ago" (falls back to date after 7 days)
      format_duration(125)              #=> "02:05"
      format_duration(7325)             #=> "02:02:05"

  API/JSON serialization should keep using the dedicated controller helper
  (`format_datetime_ist/1`) since machine consumers rely on a stable shape.
  """

  @display_tz "Asia/Kolkata"
  @date_format "%b %d, %Y"
  @datetime_format "%b %d, %Y at %I:%M %p IST"

  # ---- Date ------------------------------------------------------------------

  def format_date(nil), do: "-"

  def format_date(%Date{} = d), do: Calendar.strftime(d, @date_format)

  def format_date(%DateTime{} = dt) do
    dt
    |> shift_to_display_tz()
    |> Calendar.strftime(@date_format)
  end

  def format_date(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, @date_format)

  def format_date(_), do: "-"

  # ---- DateTime --------------------------------------------------------------

  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = dt) do
    dt
    |> shift_to_display_tz()
    |> Calendar.strftime(@datetime_format)
  end

  def format_datetime(%NaiveDateTime{} = ndt) do
    # Naive datetimes have no timezone info; assume UTC (matches Ecto defaults)
    # so the displayed clock time still reflects IST.
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> format_datetime(dt)
      _ -> Calendar.strftime(ndt, "%b %d, %Y at %I:%M %p")
    end
  end

  def format_datetime(_), do: "-"

  # ---- Relative time ---------------------------------------------------------

  def format_relative(nil), do: "-"

  def format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 0 -> format_datetime(dt)
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> format_date(dt)
    end
  end

  def format_relative(%NaiveDateTime{} = ndt) do
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> format_relative(dt)
      _ -> format_date(ndt)
    end
  end

  def format_relative(_), do: "-"

  # ---- Duration (timers) -----------------------------------------------------

  def format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, secs]) |> to_string()
    else
      :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> to_string()
    end
  end

  def format_duration(_), do: "00:00"

  # ---- Internal --------------------------------------------------------------

  defp shift_to_display_tz(%DateTime{} = dt) do
    case DateTime.shift_zone(dt, @display_tz) do
      {:ok, shifted} -> shifted
      _ -> dt
    end
  end
end
