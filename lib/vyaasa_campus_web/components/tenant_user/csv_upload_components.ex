defmodule VyaasaCampusWeb.Components.TenantUser.CsvUploadComponents do
  @moduledoc """
  Shared markup for the bulk-student CSV upload modal used by both the tenant
  dashboard and the dedicated students page.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  attr :uploads, :map, required: true
  attr :uploading?, :boolean, default: false
  attr :result, :map, default: nil

  def csv_upload_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-900 bg-opacity-75 overflow-y-auto h-full w-full z-50" id="csv-upload-modal">
      <div class="relative top-12 mx-auto p-6 border w-full max-w-2xl shadow-2xl rounded-lg bg-white">
        <div class="flex items-center justify-between pb-3 border-b">
          <h3 class="text-xl font-semibold text-gray-900">Bulk Upload Students (CSV)</h3>
          <button
            type="button"
            phx-click="hide_csv_upload"
            class="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-full hover:bg-gray-100"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </button>
        </div>

        <div class="mt-4 space-y-4">
          <div class="bg-blue-50 border border-blue-200 rounded-md p-3 text-sm text-blue-800 flex items-start">
            <.icon name="hero-information-circle" class="w-5 h-5 mr-2 shrink-0 mt-0.5" />
            <div>
              <p>
                Required columns:
                <code class="font-mono text-xs">email, first_name, last_name, phone, registration_id, degree, specialization, year_of_passing, cgpa</code>.
              </p>
              <p class="mt-1">
                <a href="/templates/student_bulk_template.csv" download class="underline font-medium">
                  Download CSV template
                </a>
              </p>
            </div>
          </div>

          <form id="csv-upload-form" phx-submit="submit_csv_upload" phx-change="validate_csv_upload">
            <label class="block text-sm font-medium text-gray-700 mb-2">Choose CSV file</label>
            <.live_file_input
              upload={@uploads.csv_students}
              class="block w-full text-sm text-gray-700 border border-gray-300 rounded-md p-2 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:bg-orange-50 file:text-orange-700 hover:file:bg-orange-100"
            />

            <%= for entry <- @uploads.csv_students.entries do %>
              <div class="mt-3 flex items-center justify-between text-sm">
                <span class="text-gray-700"><%= entry.client_name %></span>
                <button
                  type="button"
                  phx-click="cancel_csv_entry"
                  phx-value-ref={entry.ref}
                  class="text-red-600 hover:text-red-800"
                >
                  Remove
                </button>
              </div>
              <%= for err <- upload_errors(@uploads.csv_students, entry) do %>
                <p class="mt-1 text-sm text-red-600"><%= csv_upload_error(err) %></p>
              <% end %>
            <% end %>

            <%= for err <- upload_errors(@uploads.csv_students) do %>
              <p class="mt-1 text-sm text-red-600"><%= csv_upload_error(err) %></p>
            <% end %>

            <div class="flex items-center justify-end space-x-3 mt-6 pt-4 border-t">
              <button
                type="button"
                phx-click="hide_csv_upload"
                class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={@uploading? or @uploads.csv_students.entries == []}
                class="px-4 py-2 rounded-md text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 disabled:bg-gray-300 disabled:cursor-not-allowed inline-flex items-center"
              >
                <%= if @uploading? do %>
                  <.icon name="hero-arrow-path" class="w-4 h-4 mr-2 animate-spin" />
                  Uploading...
                <% else %>
                  <.icon name="hero-arrow-up-tray" class="w-4 h-4 mr-2" />
                  Upload &amp; Create
                <% end %>
              </button>
            </div>
          </form>

          <%= if @result do %>
            <div class="mt-4 border-t pt-4">
              <div class="flex items-center space-x-4 text-sm">
                <span class="inline-flex items-center px-2 py-1 rounded-full bg-green-100 text-green-800 font-medium">
                  <%= @result.success_count %> created
                </span>
                <%= if @result.error_count > 0 do %>
                  <span class="inline-flex items-center px-2 py-1 rounded-full bg-red-100 text-red-800 font-medium">
                    <%= @result.error_count %> failed
                  </span>
                <% end %>
                <span class="text-gray-500">in <%= @result.duration_ms %>ms</span>
              </div>

              <%= if @result.errors != [] do %>
                <div class="mt-3 max-h-48 overflow-y-auto border border-red-200 rounded-md">
                  <table class="w-full text-xs">
                    <thead class="bg-red-50 text-red-800">
                      <tr>
                        <th class="px-3 py-2 text-left">Row</th>
                        <th class="px-3 py-2 text-left">Email</th>
                        <th class="px-3 py-2 text-left">Errors</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-red-100">
                      <%= for err <- @result.errors do %>
                        <tr class="bg-white">
                          <td class="px-3 py-2 align-top text-gray-700"><%= err.row %></td>
                          <td class="px-3 py-2 align-top text-gray-700"><%= err.email || "-" %></td>
                          <td class="px-3 py-2 align-top text-red-700">
                            <%= for {field, msgs} <- err.errors do %>
                              <div>
                                <strong><%= field %>:</strong> <%= Enum.join(List.wrap(msgs), ", ") %>
                              </div>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp csv_upload_error(:too_large), do: "File is larger than the 5MB limit"
  defp csv_upload_error(:not_accepted), do: "Only .csv files are accepted"
  defp csv_upload_error(:too_many_files), do: "Only one file at a time"
  defp csv_upload_error(err), do: "Upload error: #{inspect(err)}"
end
