defmodule VyaasaCampusWeb.Student.SharedProfileLive do
  @moduledoc """
  Public-facing LiveView for shared student profiles.
  Accessible via a short public slug — no authentication required.
  Shows profile summary, assessment scores, and skills.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.{SharedProfileLinks, StudentAts, StudentRankings, Students, Tenants}
  import VyaasaCampusWeb.Components.UI

  require Logger

  @impl true
  def mount(%{"token" => slug}, _session, socket) do
    case SharedProfileLinks.resolve_slug(slug) do
      {:ok, %{student_id: student_id, tenant_schema: tenant_schema}} ->
        load_shared_profile(socket, student_id, tenant_schema)

      :error ->
        {:ok,
         socket
         |> assign(:valid, false)
         |> assign(:current_scope, nil)
         |> assign(:page_title, "Invalid Link")}
    end
  end

  defp load_shared_profile(socket, student_id, tenant_schema) do
    try do
      student = Students.get_student(student_id, tenant_schema)

      if student do
        ats_data = StudentAts.get_by_student_id(student_id, tenant_schema)
        rankings = StudentRankings.get_student_scores_and_ranks(student_id, tenant_schema)
        ai8_data = StudentRankings.calculate_ai8_score(student_id, tenant_schema)

        tenant = Tenants.list_tenants() |> Enum.find(&(&1.schema_name == tenant_schema))

        name = "#{student.first_name} #{student.last_name}"
        initials = name |> String.split(" ") |> Enum.take(2) |> Enum.map(&String.first/1) |> Enum.join("") |> String.upcase()

        # Extract ATS info
        preferred_role = if ats_data, do: ats_data.preferred_role, else: nil
        personal_info = if ats_data, do: ats_data.personal_information || %{}, else: %{}
        summary = if ats_data, do: ats_data.professional_summary || %{}, else: %{}
        skills = if ats_data, do: ats_data.skills || %{}, else: %{}

        technical_skills = Map.get(skills, "technical_skills", [])
        non_technical_skills = Map.get(skills, "non_technical_skills", [])

        {:ok,
         socket
         |> assign(:valid, true)
         |> assign(:current_scope, nil)
         |> assign(:page_title, "#{name} — Profile")
         |> assign(:name, name)
         |> assign(:initials, initials)
         |> assign(:student, student)
         |> assign(:preferred_role, preferred_role)
         |> assign(:location, personal_info["location"] || personal_info["city"])
         |> assign(:summary_text, summary["summary"] || summary["professional_summary"])
         |> assign(:total_experience, summary["total_experience"])
         |> assign(:technical_skills, technical_skills)
         |> assign(:non_technical_skills, non_technical_skills)
         |> assign(:rankings, rankings)
         |> assign(:ai8_data, ai8_data)
         |> assign(:tenant_name, if(tenant, do: tenant.full_name, else: ""))}
      else
        {:ok, assign(socket, :valid, false) |> assign(:current_scope, nil) |> assign(:page_title, "Profile Not Found")}
      end
    rescue
      e ->
        Logger.error("SharedProfileLive error: #{inspect(e)}")
        {:ok, assign(socket, :valid, false) |> assign(:current_scope, nil) |> assign(:page_title, "Error")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @valid do %>
        <!-- Header -->
        <div class="bg-white border-b border-gray-200 shadow-sm">
          <div class="max-w-4xl mx-auto px-4 sm:px-6 py-4 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <img src="/images/logo.png" alt="Vyaasa" class="h-8" />
              <span class="text-sm text-gray-500">Verified Student Profile</span>
            </div>
            <span class="text-xs text-gray-400">{@tenant_name}</span>
          </div>
        </div>

        <div class="max-w-4xl mx-auto px-4 sm:px-6 py-8">
          <!-- Profile Card -->
          <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
            <div class="flex flex-col sm:flex-row sm:items-start gap-4">
              <div class="w-16 h-16 bg-linear-to-br from-orange-400 to-orange-600 rounded-xl flex items-center justify-center text-white font-bold text-xl shrink-0">
                {@initials}
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex flex-wrap items-center gap-2 mb-1">
                  <h1 class="text-2xl font-bold text-gray-900">{@name}</h1>
                  <%= if @student.status == "verified" do %>
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-green-100 text-green-700 text-xs font-medium rounded-full">
                      <.icon name="hero-check" class="w-3 h-3" />
                      Verified
                    </span>
                  <% end %>
                </div>
                <%= if @preferred_role do %>
                  <p class="text-gray-600 font-medium mb-2">{@preferred_role}</p>
                <% end %>
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-gray-500">
                  <%= if @location do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-map-pin" class="w-4 h-4" />
                      {@location}
                    </span>
                  <% end %>
                  <%= if @total_experience do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-briefcase" class="w-4 h-4" />
                      {@total_experience}
                    </span>
                  <% end %>
                  <%= if @student.degree do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-academic-cap" class="w-4 h-4" />
                      {@student.degree}<%= if @student.specialization, do: " - #{@student.specialization}" %>
                    </span>
                  <% end %>
                  <%= if @student.cgpa do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-chart-bar" class="w-4 h-4" />
                      CGPA: {Decimal.to_float(@student.cgpa) |> Float.round(2)}
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <!-- About -->
          <%= if @summary_text do %>
            <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
              <h3 class="font-bold text-gray-900 mb-3">About</h3>
              <p class="text-sm text-gray-600 leading-relaxed">{@summary_text}</p>
            </div>
          <% end %>

          <!-- Vyaasa Score -->
          <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
            <h3 class="font-bold text-gray-900 mb-4">Vyaasa Score</h3>
            <div class="flex items-center gap-8">
              <div class="relative w-28 h-28 shrink-0">
                <svg class="w-full h-full" viewBox="0 0 120 120" style="transform: rotate(-90deg)">
                  <defs>
                    <linearGradient id="sharedGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                      <stop offset="0%" stop-color="#f97316"/>
                      <stop offset="100%" stop-color="#22c55e"/>
                    </linearGradient>
                  </defs>
                  <circle cx="60" cy="60" r="52" fill="none" stroke="#f3f4f6" stroke-width="8"/>
                  <circle cx="60" cy="60" r="52" fill="none" stroke="url(#sharedGrad)" stroke-width="8" stroke-linecap="round"
                    stroke-dasharray="326.73" stroke-dashoffset={326.73 * (1 - @ai8_data.ai8_score / 100)}/>
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-2xl font-bold text-gray-900">{round(@ai8_data.ai8_score)}</span>
                  <span class="text-xs text-gray-400">/ 100</span>
                </div>
              </div>
              <div class="flex-1 grid grid-cols-2 gap-3 text-sm">
                <.score_row label="Resume Score" data={@rankings.ats} />
                <.score_row label="Interview" data={@rankings.interview} />
                <.score_row label="MCQ" data={@rankings.mcq} field={:percentage} />
                <.score_row label="JAM" data={@rankings.jam} />
                <.score_row label="Behavioral" data={@rankings.behavioral} />
                <.score_row label="Psychometric" data={@rankings.psychometric} />
                <.score_row label="Case Study" data={@rankings.case_study} />
                <.score_row label="Mini Project" data={@rankings.mini_project} />
              </div>
            </div>
          </div>

          <!-- Skills -->
          <%= if @technical_skills != [] || @non_technical_skills != [] do %>
            <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
              <div class="flex items-center gap-2 mb-4">
                <.icon name="hero-check-circle" class="w-5 h-5 text-green-500" />
                <h3 class="font-bold text-gray-900">Verified Skills</h3>
              </div>
              <div class="flex flex-wrap gap-2">
                <%= for skill <- @technical_skills ++ @non_technical_skills do %>
                  <span class="inline-flex items-center gap-1.5 px-3 py-1.5 border border-gray-200 rounded-full text-sm text-gray-700 bg-white">
                    <span class="w-3 h-3 bg-green-500 rounded-full flex items-center justify-center">
                      <.icon name="hero-check" class="w-2 h-2 text-white" />
                    </span>
                    {skill}
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Assessment Scores Detail -->
          <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
            <h3 class="font-bold text-gray-900 mb-4">Assessment Scores</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.assessment_card name="Resume Analysis" icon="hero-document-text" color="orange" data={@rankings.ats} />
              <.assessment_card name="Interactive Session" icon="hero-microphone" color="indigo" data={@rankings.interview} />
              <.assessment_card name="Objective Eval" icon="hero-code-bracket" color="green" data={@rankings.mcq} field={:percentage} />
              <.assessment_card name="JAM Session" icon="hero-chat-bubble-left-right" color="blue" data={@rankings.jam} />
              <.assessment_card name="Behavioral" icon="hero-light-bulb" color="purple" data={@rankings.behavioral} />
              <.assessment_card name="Psychometric" icon="hero-face-smile" color="pink" data={@rankings.psychometric} />
              <.assessment_card name="Case Study" icon="hero-academic-cap" color="amber" data={@rankings.case_study} />
              <.assessment_card name="Mini Project" icon="hero-wrench-screwdriver" color="teal" data={@rankings.mini_project} />
            </div>
          </div>

          <!-- Behavioral Competencies -->
          <%= if @rankings.behavioral[:completed] do %>
            <% c = @rankings.behavioral[:competencies] || %{} %>
            <div class="bg-white border border-gray-100 rounded-xl p-6 mb-6 shadow-sm">
              <h3 class="font-bold text-gray-900 mb-4">Behavioral Competencies</h3>
              <div class="space-y-3">
                <%= for {key, label} <- [{:leadership, "Leadership"}, {:communication, "Communication"}, {:teamwork, "Teamwork"}, {:adaptability, "Adaptability"}, {:work_ethics, "Work Ethics"}] do %>
                  <% val = c[key] || 0 %>
                  <div>
                    <div class="flex justify-between text-sm mb-1">
                      <span class="text-gray-700">{label}</span>
                      <span class="font-semibold text-gray-900">{val}%</span>
                    </div>
                    <div class="h-1.5 bg-gray-200 rounded-full overflow-hidden">
                      <div class="h-full bg-linear-to-r from-orange-500 to-orange-400 rounded-full" style={"width: #{val}%"}></div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Verified Footer -->
          <div class="bg-linear-to-r from-green-50 to-emerald-50 border border-green-200 rounded-xl p-5 flex items-start gap-4">
            <div class="w-10 h-10 bg-green-500 rounded-full flex items-center justify-center shrink-0">
              <.icon name="hero-shield-check" class="w-5 h-5 text-white" />
            </div>
            <div>
              <h4 class="font-bold text-green-800">Verified by Vyaasa Campus</h4>
              <p class="text-sm text-green-700">All scores are generated through structured AI-powered assessments and verified by the platform.</p>
            </div>
          </div>
        </div>
      <% else %>
        <!-- Invalid Link -->
        <div class="min-h-screen flex items-center justify-center">
          <div class="text-center max-w-md">
            <div class="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-red-600" />
            </div>
            <h1 class="text-2xl font-bold text-gray-900 mb-2">Invalid or Expired Link</h1>
            <p class="text-gray-600">This profile link is no longer valid. Please ask the student for a new link.</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Components

  attr :label, :string, required: true
  attr :data, :map, required: true
  attr :field, :atom, default: :score

  defp score_row(assigns) do
    score = case assigns.data do
      %{completed: true} ->
        val = if assigns.field == :percentage, do: assigns.data[:percentage] || assigns.data[:score], else: assigns.data[:score]
        if val, do: round(val), else: "-"
      _ -> "-"
    end

    assigns = assign(assigns, :display_score, score)

    ~H"""
    <div class="flex justify-between">
      <span class="text-gray-500">{@label}</span>
      <span class="font-semibold text-gray-900">{@display_score}</span>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true
  attr :data, :map, required: true
  attr :field, :atom, default: :score

  defp assessment_card(assigns) do
    {score, rank, total, completed} = case assigns.data do
      %{completed: true} = d ->
        s = if assigns.field == :percentage, do: d[:percentage] || d[:score], else: d[:score]
        {if(s, do: round(s), else: 0), d[:rank], d[:total], true}
      _ -> {0, nil, nil, false}
    end

    assigns =
      assigns
      |> assign(:score, score)
      |> assign(:rank, rank)
      |> assign(:total_students, total)
      |> assign(:completed, completed)

    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 border border-gray-100">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <div class={"w-7 h-7 rounded-lg flex items-center justify-center bg-#{@color}-100"}>
            <.icon name={@icon} class={"w-4 h-4 text-#{@color}-600"} />
          </div>
          <span class="font-medium text-gray-900 text-sm">{@name}</span>
        </div>
        <span class="text-lg font-bold text-gray-900">
          <%= if @completed, do: @score, else: "-" %>
        </span>
      </div>
      <%= if @completed && @rank do %>
        <p class="text-xs text-gray-500">Rank {@rank} of {@total_students}</p>
      <% else %>
        <p class="text-xs text-gray-400">Not completed</p>
      <% end %>
    </div>
    """
  end
end
