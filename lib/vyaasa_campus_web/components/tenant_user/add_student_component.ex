defmodule VyaasaCampusWeb.Components.TenantUser.AddStudentComponent do
  @moduledoc """
  AddStudent component for tenant user dashboard.
  Handles student creation with form validation and file upload.
  Uses DaisyUI components for consistent styling.
  """

  use Phoenix.Component
  import VyaasaCampusWeb.Components.UI

  attr :form, :map, required: true
  attr :tenant_alias, :string, required: true
  attr :errors, :list, default: []
  attr :loading, :boolean, default: false
  attr :phx_change, :string, default: "validate_new_student"
  attr :phx_submit, :string, default: "save_new_student"
  attr :degree_options, :list, default: nil
  attr :specialization_options, :list, default: nil

  def add_student_form(assigns) do
    ~H"""
    <div class="min-h-screen">
      <div class="w-full">
        <!-- Header with breadcrumb -->
        <div class="mb-6"></div>


          <!-- Back button and title --
        <!-- Main form card -->
        <div class="card">
          <div class="card-body">
            <.form
              for={@form}
              id="add-student-form"
              phx-change={@phx_change}
              phx-submit={@phx_submit}
              class="space-y-6"
            >
              <!-- Personal Information Section -->
              <div class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                  <!-- First Name -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">First Name</span>
                    </label>
                    <.input
                      field={@form[:first_name]}
                      type="text"
                      placeholder="Enter first name"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      required
                    />
                  </div>

                  <!-- Middle Name -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Middle Name (optional)</span>
                    </label>
                    <.input
                      field={@form[:middle_name]}
                      type="text"
                      placeholder="Enter your middle name"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                    />
                  </div>

                  <!-- Last Name -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Last Name</span>
                    </label>
                    <.input
                      field={@form[:last_name]}
                      type="text"
                      placeholder="Enter your last name"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      required
                    />
                  </div>

                  <!-- Email -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Email</span>
                    </label>
                    <.input
                      field={@form[:email]}
                      type="email"
                      placeholder="Enter your email ID"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      required
                    />
                  </div>
                </div>
              </div>

              <!-- Academic Information Section -->
              <div class="space-y-4">


                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                  <!-- Phone Number -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Phone Number</span>
                    </label>
                    <.input
                      field={@form[:phone]}
                      type="tel"
                      placeholder="Enter your phone number"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      inputmode="numeric"
                      pattern="[0-9]{10}"
                      title="Mobile number must be exactly 10 digits"
                      maxlength="10"
                      data-maxlength="10"
                      phx-hook="DigitsOnly"
                      required
                    />
                  </div>

                  <!-- Registration ID -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Registration ID</span>
                    </label>
                    <.input
                      field={@form[:registration_id]}
                      type="text"
                      placeholder="Enter registration ID"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      pattern="[A-Za-z0-9].*"
                      title="Registration ID must start with a letter or number"
                    />
                  </div>

                  <!-- Degree / Class -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Degree / Class</span>
                    </label>
                    <.input
                      field={@form[:degree]}
                      type="select"
                      options={@degree_options || default_degree_options()}
                      class="select select-bordered w-full text-gray-500 border-gray-300"
                      required
                    />
                  </div>

                  <!-- Specialization -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Specialization</span>
                    </label>
                    <.input
                      field={@form[:specialization]}
                      type="select"
                      options={@specialization_options || default_specialization_options()}
                      class="select select-bordered w-full text-gray-500 border-gray-300"
                    />
                  </div>

                  <!-- Year of Passing -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Year of Passing</span>
                    </label>
                    <.input
                      field={@form[:year_of_passing]}
                      type="text"
                      placeholder="Your passing year, eg: '2024'"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                      pattern="[0-9]{4}"
                      required
                    />
                  </div>

                  <!-- CGPA -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">CGPA</span>
                    </label>
                    <.input
                      field={@form[:cgpa]}
                      type="number"
                      step="0.01"
                      min="0"
                      max="10"
                      placeholder="Enter CGPA"
                      class="input input-bordered w-full text-gray-500 border-gray-300"
                    />
                  </div>

                  <!-- Current Academic Year -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Current Academic Year</span>
                    </label>
                    <.input
                      field={@form[:current_academic_year]}
                      type="select"
                      options={[
                        {"Select year", ""},
                        {"1st Year", "1st Year"},
                        {"2nd Year", "2nd Year"},
                        {"3rd Year", "3rd Year"},
                        {"4th Year", "4th Year"},
                        {"Final Year", "Final Year"},
                        {"Graduated", "Graduated"}
                      ]}
                      class="select select-bordered w-full text-gray-500 border-gray-300"
                    />
                  </div>

                  <!-- Tenure -->
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium text-black">Tenure</span>
                    </label>
                    <.input
                      field={@form[:tenure]}
                      type="select"
                      options={[
                        {"Select tenure", ""},
                        {"3 Years", "3 Years"},
                        {"4 Years", "4 Years"},
                        {"5 Years", "5 Years"},
                        {"2 Years (Masters)", "2 Years"}
                      ]}
                      class="select select-bordered w-full text-gray-500 border-gray-300"
                    />
                  </div>
                </div>
              </div>
              <!-- Error Messages -->
              <%= if @errors != [] do %>
                <div class="alert alert-error">
                  <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                  <div>
                    <h3 class="font-bold">Please fix the following errors:</h3>
                    <ul class="list-disc list-inside">
                      <%= for error <- @errors do %>
                        <li><%= error %></li>
                      <% end %>
                    </ul>
                  </div>
                </div>
              <% end %>

              <!-- Form Actions -->
              <div class="flex items-center justify-end space-x-4 pt-6 border-t border-base-300">
                <.link
                  navigate={"/user/#{@tenant_alias}/dashboard"}
                  class="btn btn-ghost"
                >
                  Cancel
                </.link>

                <button
                  type="submit"
                  class={[
                    "btn btn-primary",
                    @loading && "loading"
                  ]}
                  disabled={@loading}
                >
                  <%= if @loading do %>
                    <span class="loading loading-spinner"></span>
                    Creating...
                  <% else %>
                    <.icon name="hero-plus" class="w-4 h-4 mr-2" />
                    Add student
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp default_degree_options do
    [
      {"Select degree", ""},
      {"BCA", "BCA"},
      {"BTech CSE", "BTech CSE"},
      {"BTech IT", "BTech IT"},
      {"BTech ECE", "BTech ECE"},
      {"BTech EEE", "BTech EEE"},
      {"BTech Mech", "BTech Mech"},
      {"MTech", "MTech"},
      {"MBA", "MBA"},
      {"MCA", "MCA"}
    ]
  end

  defp default_specialization_options do
    [
      {"Select specialization", ""},
      {"Software Engineering", "Software Engineering"},
      {"Data Science", "Data Science"},
      {"Artificial Intelligence", "Artificial Intelligence"},
      {"Cyber Security", "Cyber Security"},
      {"Web Development", "Web Development"},
      {"Mobile Development", "Mobile Development"},
      {"Cloud Computing", "Cloud Computing"},
      {"DevOps", "DevOps"}
    ]
  end
end
