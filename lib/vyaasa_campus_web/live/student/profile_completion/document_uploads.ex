defmodule VyaasaCampusWeb.Student.ProfileCompletion.DocumentUploads do
  @moduledoc """
  Document upload components for profile completion.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  attr :uploads, :any, required: true
  attr :reanalyze_mode?, :boolean, default: false
  attr :photo_status, :any, default: nil

  def render_documents_section(assigns) do
    ~H"""
    <div class={if(@reanalyze_mode?, do: "mb-8", else: "bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm")}>
      <h3 class="text-lg font-bold text-gray-900 flex items-center">
        <.icon name="hero-document-text" class="w-5 h-5 mr-2" />
        <%= if @reanalyze_mode?, do: "Upload New Resume", else: "Upload Required Documents" %>
      </h3>
      <p :if={!@reanalyze_mode?} class="text-sm text-gray-500 mt-1 mb-6">These will be included in your final student profile PDF.</p>
      <div :if={@reanalyze_mode?} class="mb-6"></div>

      <%= if @reanalyze_mode? do %>
        <!-- Re-analysis: only resume upload needed -->
        <div class="max-w-md">
          <.upload_section
            upload={@uploads.resume}
            upload_type="resume"
            title="Upload Resume (PDF)"
            icon="hero-document-text"
            icon_bg="bg-orange-100"
            icon_color="text-orange-600"
            form_id="resume-upload"
            submit_event="upload_resume"
            change_event="validate_resume"
          />
          <p class="text-xs text-gray-500 mt-3">
            Your ID card and profile photo are already verified — just upload
            your updated resume to see your new score.
          </p>
        </div>
      <% else %>
        <!-- First-time verification: all three documents -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <!-- Resume Upload -->
          <.upload_section
            upload={@uploads.resume}
            upload_type="resume"
            title="Upload Resume (PDF)"
            icon="hero-document-text"
            icon_bg="bg-orange-100"
            icon_color="text-orange-600"
            form_id="resume-upload"
            submit_event="upload_resume"
            change_event="validate_resume"
          />

          <!-- ID Card Upload -->
          <.upload_section
            upload={@uploads.id_card}
            upload_type="id_card"
            title="College ID Card"
            icon="hero-identification"
            icon_bg="bg-blue-100"
            icon_color="text-blue-600"
            form_id="id-card-upload"
            submit_event="upload_id_card"
            change_event="validate_id_card"
          />

          <!-- Profile Photo Upload -->
          <.upload_section
            upload={@uploads.profile_photo}
            upload_type="profile_photo"
            title="Profile Photo (optional)"
            icon="hero-camera"
            icon_bg="bg-purple-100"
            icon_color="text-purple-600"
            form_id="profile-photo-upload"
            submit_event="upload_profile_photo"
            change_event="validate_profile_photo"
            status={@photo_status}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :upload_type, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :icon_bg, :string, required: true
  attr :icon_color, :string, required: true
  attr :form_id, :string, required: true
  attr :submit_event, :string, required: true
  attr :change_event, :string, required: true
  attr :status, :any, default: nil

  defp upload_section(assigns) do
    ~H"""
    <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-orange-400 transition-colors">
      <div class={"w-12 h-12 #{@icon_bg} rounded-full flex items-center justify-center mx-auto mb-4"}>
        <.icon name={@icon} class={"w-6 h-6 #{@icon_color}"} />
      </div>
      <h4 class="text-sm font-medium text-gray-900 mb-2"><%= @title %></h4>

      <form id={@form_id} phx-submit={@submit_event} phx-change={@change_event}>
        <.live_file_input upload={@upload} class="hidden" />
        <label for={@upload.ref} class="inline-flex items-center px-4 py-2 bg-orange-500 text-white text-sm font-medium rounded-lg hover:bg-orange-600 transition-colors cursor-pointer">
          <.icon name="hero-cloud-arrow-up" class="w-4 h-4 mr-2" />
          Upload
        </label>
      </form>

      <%= if @status do %>
        <!-- Uploads that are consumed as soon as they finish streaming (no
             separate submit step) have no @upload.entries left to show once
             done — this renders the loader/filename/progress bar from
             server-tracked status instead, matching the entries display
             below, so the user still sees what happened. -->
        <div class="mt-2 text-xs">
          <div class="flex items-start justify-between gap-2 bg-gray-50 p-2 rounded">
            <span class="text-gray-700 flex items-start gap-1.5 min-w-0">
              <span :if={@status.state == :uploading} class="inline-block w-3 h-3 mt-0.5 border-2 border-orange-400 border-t-transparent rounded-full animate-spin shrink-0"></span>
              <span class="break-words text-left"><%= @status.filename %></span>
            </span>
            <button
              :if={@status.state != :uploading}
              phx-click="remove_profile_photo"
              class="text-red-600 hover:text-red-800 shrink-0"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-1 mt-1">
            <div class={[
              "h-1 rounded-full transition-all",
              @status.state == :error && "bg-red-500",
              @status.state != :error && "bg-orange-500"
            ]} style={"width: #{if @status.state == :uploading, do: 60, else: 100}%"}></div>
          </div>
        </div>
      <% else %>
        <%= for entry <- @upload.entries do %>
          <div class="mt-2 text-xs">
            <div class="flex items-start justify-between gap-2 bg-gray-50 p-2 rounded">
              <span class="text-gray-700 break-words text-left min-w-0"><%= entry.client_name %></span>
              <button
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                phx-value-type={@upload_type}
                class="text-red-600 hover:text-red-800 shrink-0"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-1 mt-1">
              <div class="bg-orange-500 h-1 rounded-full transition-all" style={"width: #{entry.progress}%"}></div>
            </div>
          </div>
        <% end %>

        <%= if @upload.entries == [] do %>
          <p class="text-xs text-gray-500 mt-2">No file chosen</p>
        <% end %>
      <% end %>

      <%= for error <- upload_errors(@upload) do %>
        <p class="text-xs text-red-500 mt-2"><%= error_to_string(error) %></p>
      <% end %>
      <p class="text-xs text-gray-400">Max size 5MB</p>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:too_many_files), do: "You can only upload one file"
  defp error_to_string(:not_accepted), do: "File type not supported"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
