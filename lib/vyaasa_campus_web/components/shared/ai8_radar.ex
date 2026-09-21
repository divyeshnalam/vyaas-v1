defmodule VyaasaCampusWeb.Components.Shared.AI8Radar do
  @moduledoc """
  The AI8 8-axis radar ("web") chart.

  Shared by the student's AI8 Overview and the tenant-admin student detail
  drawer so both render the identical chart — same geometry, same palette, same
  labels. Extracted from `Student.AI8OverviewLive` when the admin drawer needed
  it; don't re-implement the geometry elsewhere.

  Expects `dims` as a list of `%{key: string, label: string, score: 0..100}` in
  canonical `VyaasaCampus.AI8.Dimensions` order (8 entries).
  """

  use Phoenix.Component

  alias VyaasaCampus.AI8.Dimensions

  # Geometry of the 320x300 viewBox. Tuned in d4c7af1 so labels clear the outer
  # ring — change with care.
  @cx 160
  @cy 150
  @r 110

  attr :dims, :list, required: true, doc: "8 dimensions as %{key, label, score}"
  attr :class, :string, default: "w-full max-w-105 mx-auto"
  attr :label_size, :string, default: "9px"

  def ai8_radar(assigns) do
    assigns =
      assigns
      |> assign(:cx, @cx)
      |> assign(:cy, @cy)
      |> assign(:rings, Enum.map([0.25, 0.5, 0.75, 1.0], &ring_points/1))
      |> assign(:axes, Enum.map(0..7, fn i -> point(i, 1.0) end))
      |> assign(
        :data,
        Enum.map_join(Enum.with_index(assigns.dims), " ", fn {d, i} ->
          point_str(i, (d.score || 0) / 100)
        end)
      )
      |> assign(
        :labels,
        Enum.map(Enum.with_index(assigns.dims), fn {d, i} ->
          label_info(i, Dimensions.short_label(d.key))
        end)
      )

    ~H"""
    <svg viewBox="0 0 320 300" class={@class} style="overflow: visible">
      <polygon :for={ring <- @rings} points={ring} fill="none" stroke="#F0E6DA" stroke-width="1" />
      <line :for={{x, y} <- @axes} x1={@cx} y1={@cy} x2={x} y2={y} stroke="#F0E6DA" stroke-width="1" />
      <polygon points={@data} fill="#EE6D18" fill-opacity="0.25" stroke="#EE6D18" stroke-width="2" />
      <text
        :for={{x, y, anchor, lbl} <- @labels}
        x={x}
        y={y}
        text-anchor={anchor}
        dominant-baseline="central"
        class="fill-gray-500"
        style={"font-size:#{@label_size}"}
      >{lbl}</text>
    </svg>
    """
  end

  @doc """
  Build the `dims` list for a student from an `AI8.ai8_index/2` (or
  `ai8_indexes/2`) profile. Unassessed dimensions render as 0.
  """
  def dims_from_profile(nil), do: dims_from_profile(%{dimensions: %{}})

  def dims_from_profile(profile) do
    dimensions = Map.get(profile, :dimensions) || %{}

    Enum.map(Dimensions.all(), fn {key, label} ->
      sk = Atom.to_string(key)
      %{key: sk, label: label, score: round(Map.get(dimensions, sk, 0) || 0)}
    end)
  end

  defp angle(i), do: (-90 + i * 45) * :math.pi() / 180

  defp point(i, frac) do
    a = angle(i)
    {Float.round(@cx + @r * frac * :math.cos(a), 1), Float.round(@cy + @r * frac * :math.sin(a), 1)}
  end

  defp point_str(i, frac) do
    {x, y} = point(i, frac)
    "#{x},#{y}"
  end

  defp ring_points(frac), do: Enum.map_join(0..7, " ", &point_str(&1, frac))

  # Pushes each label clear of the outer ring and anchors it away from the
  # grid (start/end for side labels, middle for top/bottom) so text never
  # doubles back over the axis lines.
  defp label_info(i, lbl) do
    a = angle(i)
    cos_a = :math.cos(a)
    sin_a = :math.sin(a)
    x = Float.round(@cx + (@r + 22) * cos_a, 1)
    y = Float.round(@cy + (@r + 22) * sin_a, 1)

    anchor =
      cond do
        cos_a > 0.3 -> "start"
        cos_a < -0.3 -> "end"
        true -> "middle"
      end

    {x, y, anchor, lbl}
  end
end
