defmodule VyaasaCampusWeb.Student.Jam.Components do
  @moduledoc """
  Reusable UI components for the JAM (Just A Minute) session flow.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI
  alias VyaasaCampusWeb.DateTimeFormatter

  @doc """
  Renders the 5-step horizontal stepper for the JAM session flow.

  ## Attrs
    - `current_step` - The current active step atom (:instructions, :topic, :preparation, :speak, :feedback)
  """
  attr :current_step, :atom, required: true

  def stepper(assigns) do
    steps = [
      %{key: :instructions, label: "INSTRUCTIONS"},
      %{key: :topic, label: "TOPIC"},
      %{key: :preparation, label: "PREPARATION"},
      %{key: :speak, label: "SPEAKING"},
      %{key: :feedback, label: "VYAASA FEEDBACK"}
    ]

    step_order = [:instructions, :topic, :preparation, :speak, :feedback]
    current_index = Enum.find_index(step_order, &(&1 == assigns.current_step))

    # Map internal steps to stepper indices
    current_index = case assigns.current_step do
      :instructions -> 0
      :topic -> 1
      :topic_explanation -> 1
      :preparation -> 2
      :speak -> 3
      :feedback -> 4
      _ -> 0
    end

    assigns = assign(assigns, steps: steps, current_index: current_index)

    ~H"""
    <div class="flex items-center justify-between w-full max-w-4xl mx-auto mb-10 px-4">
      <%= for {step, index} <- Enum.with_index(@steps) do %>
        <div class="flex flex-col items-center flex-1 relative">
          <!-- Connector Line -->
          <%= if index > 0 do %>
            <div class={[
              "absolute right-1/2 w-full h-[2px] top-4 -translate-y-1/2 -z-10",
              if(index <= @current_index, do: "bg-green-500", else: "bg-gray-100")
            ]} style="right: 50%; width: 100%;"></div>
          <% end %>

          <!-- Step Circle -->
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold transition-all duration-300 z-10",
            cond do
              index < @current_index -> "bg-green-500 text-white"
              index == @current_index -> "bg-orange-500 text-white ring-4 ring-orange-100"
              true -> "bg-gray-100 text-gray-400"
            end
          ]}>
            <%= if index < @current_index do %>
              <.icon name="hero-check" class="w-5 h-5" />
            <% else %>
              {index + 1}
            <% end %>
          </div>

          <!-- Step Label -->
          <span class={[
            "text-[10px] font-bold tracking-wider mt-2 whitespace-nowrap",
            if(index <= @current_index, do: "text-gray-900", else: "text-gray-400")
          ]}>
            {step.label}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a horizontal score bar (e.g., Clarity 4/5).
  """
  attr :label, :string, required: true
  attr :score, :integer, required: true
  attr :max, :integer, default: 10

  def score_bar(assigns) do
    percentage = assigns.score / assigns.max * 100
    assigns = assign(assigns, percentage: percentage)

    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-sm text-gray-700 w-24">{@label}</span>
      <div class="flex-1 bg-gray-200 rounded-full h-2.5">
        <div
          class="bg-orange-500 h-2.5 rounded-full transition-all duration-500"
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
      <span class="text-sm font-semibold text-gray-700 w-8 text-right">{@score}/{@max}</span>
    </div>
    """
  end

  @doc """
  Renders the circular countdown timer used in the Speak screen.
  """
  attr :seconds, :integer, required: true
  attr :total, :integer, default: 60
  attr :size, :string, default: "md"

  def circular_timer(assigns) do
    progress = assigns.seconds / assigns.total
    # SVG circle: circumference = 2 * pi * r (r=18 for a 44px viewbox)
    circumference = 2 * :math.pi() * 18
    offset = circumference * (1 - progress)

    {container_class, text_class} =
      case assigns.size do
        "sm" -> {"w-12 h-12", "text-xs"}
        "lg" -> {"w-20 h-20", "text-lg"}
        _ -> {"w-14 h-14", "text-sm"}
      end

    assigns =
      assign(assigns,
        circumference: circumference,
        offset: offset,
        container_class: container_class,
        text_class: text_class
      )

    ~H"""
    <div class={"relative #{@container_class}"}>
      <svg class="w-full h-full transform -rotate-90" viewBox="0 0 40 40">
        <!-- Background circle -->
        <circle cx="20" cy="20" r="18" fill="none" stroke="#e5e7eb" stroke-width="2.5" />
        <!-- Progress circle -->
        <circle
          cx="20"
          cy="20"
          r="18"
          fill="none"
          stroke={if @seconds > 10, do: "#22c55e", else: "#ef4444"}
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-dasharray={@circumference}
          stroke-dashoffset={@offset}
          class="transition-all duration-1000"
          data-countdown-circle
        />
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class={"font-bold #{@text_class}"} data-countdown-circle-text>
          {DateTimeFormatter.format_duration(@seconds)}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the audio waveform visualization.
  When active with a real audio level, generates bars based on the level.
  """
  attr :active, :boolean, default: false
  attr :level, :integer, default: 0

  def waveform(assigns) do
    bars =
      if assigns.active and assigns.level > 0 do
        # Generate bars based on real audio level (0-100)
        base = assigns.level
        for i <- 0..24 do
          # Create variation around the base level
          variation = :erlang.phash2({i, base}, 30) - 15
          min(95, max(8, base + variation))
        end
      else
        if assigns.active do
          [35, 55, 40, 65, 45, 70, 50, 60, 38, 68, 42, 58, 48, 62, 36, 55, 44, 66, 40, 52, 46, 64, 38, 56, 50]
        else
          List.duplicate(8, 25)
        end
      end

    assigns = assign(assigns, bars: bars)

    ~H"""
    <div class="flex items-center justify-center gap-1 h-16 my-4">
      <%= for {height, i} <- Enum.with_index(@bars) do %>
        <div
          class={[
            "w-1.5 rounded-full transition-all duration-150",
            if(@active, do: "bg-orange-500", else: "bg-gray-300")
          ]}
          style={"height: #{height}%; animation-delay: #{i * 50}ms;"}
        >
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the overall score circle (e.g., 60/100).
  """
  attr :score, :integer, required: true
  attr :max, :integer, default: 100

  def score_circle(assigns) do
    progress = assigns.score / assigns.max
    circumference = 2 * :math.pi() * 40
    offset = circumference * (1 - progress)

    color =
      cond do
        assigns.score >= 80 -> "#22c55e"
        assigns.score >= 60 -> "#f97316"
        assigns.score >= 40 -> "#eab308"
        true -> "#ef4444"
      end

    assigns = assign(assigns, circumference: circumference, offset: offset, color: color)

    ~H"""
    <div class="relative w-24 h-24 mx-auto">
      <svg class="w-full h-full transform -rotate-90" viewBox="0 0 88 88">
        <circle cx="44" cy="44" r="40" fill="none" stroke="#e5e7eb" stroke-width="6" />
        <circle
          cx="44"
          cy="44"
          r="40"
          fill="none"
          stroke={@color}
          stroke-width="6"
          stroke-linecap="round"
          stroke-dasharray={@circumference}
          stroke-dashoffset={@offset}
          class="transition-all duration-1000"
        />
      </svg>
      <div class="absolute inset-0 flex flex-col items-center justify-center">
        <span class="text-2xl font-bold text-gray-900">{@score}</span>
        <span class="text-xs text-gray-500">/{@max}</span>
      </div>
    </div>
    """
  end

end
