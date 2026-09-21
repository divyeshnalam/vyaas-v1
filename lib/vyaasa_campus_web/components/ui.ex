defmodule VyaasaCampusWeb.Components.UI do
  @moduledoc """
  UI components for the Vyaasa Campus application.

  This module contains all reusable UI components built with DaisyUI and Tailwind CSS.
  Components are organized by type: basic components, page-specific components, and utilities.
  """

  use Phoenix.Component
  use Gettext, backend: VyaasaCampusWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  # ============================================================================
  # BASIC UI COMPONENTS
  # ============================================================================

  @doc """
  Renders a toast notification using DaisyUI alerts.

  ## Examples

      <.toast type="success" message="Student created successfully!" />
      <.toast type="error" message="Failed to create student" />
      <.toast type="warning" message="Please fill all required fields" />
      <.toast type="info" message="Profile completion email sent" />
  """
  attr :type, :string, required: true, values: ~w(success error warning info)
  attr :message, :string, required: true
  attr :id, :string, default: nil
  attr :dismissible, :boolean, default: true
  attr :duration, :integer, default: 5000

  def toast(assigns) do
    ~H"""
    <div
      id={@id || "toast-#{System.unique_integer([:positive])}"}
      class={[
        "toast toast-top toast-end z-50",
        @dismissible && "cursor-pointer"
      ]}
      phx-hook={@duration && "AutoDismissToast"}
      data-duration={@duration}
    >
      <div class={[
        "alert",
        toast_alert_class(@type),
        "min-w-0 max-w-sm shadow-lg"
      ]}>
        <.toast_icon type={@type} />
        <span class="text-sm font-medium">{@message}</span>
        <%= if @dismissible do %>
          <button
            class="btn btn-sm btn-circle btn-ghost ml-2"
            onclick="this.closest('.toast').remove()"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a simple alert using DaisyUI.

  ## Examples

      <.alert type="info" message="This is an info alert" />
      <.alert type="error" message="This is an error alert" />
  """
  attr :type, :string, required: true, values: ~w(success error warning info)
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def alert(assigns) do
    ~H"""
    <div class={[
      "alert",
      toast_alert_class(@type),
      @class
    ]}>
      <.toast_icon type={@type} />
      <span>{@message}</span>
    </div>
    """
  end

  @doc """
  Renders a form input using DaisyUI styling.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input field={@form[:name]} type="text" label="Full Name" />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :class, :string, default: nil
  attr :options, :list, default: []

  attr :rest, :global,
    include: ~w(autocomplete disabled max maxlength min minlength pattern readonly required rows size step)

  def input(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label" :if={@label}>
        <span class="label-text">{@label}</span>
      </label>
      <%= if @type == "textarea" do %>
        <textarea
          name={@field.name}
          id={@field.id}
          placeholder={@placeholder}
          class={[
            "textarea textarea-bordered w-full",
            @field.errors != [] && "textarea-error",
            @class
          ]}
          {@rest}
        >{Form.normalize_value("textarea", @field.value)}</textarea>
      <% else %>
      <%= if @type == "select" do %>
        <select
          name={@field.name}
          id={@field.id}
          class={[
            "select select-bordered w-full",
            @field.errors != [] && "select-error",
            @class
          ]}
          {@rest}
        >
          <option value="">{@placeholder || "Select an option"}</option>
          <option :for={option <- @options} value={option_value(option)} selected={option_value(option) == @field.value}>
            {option_label(option)}
          </option>
        </select>
      <% else %>
        <%= if @type == "password" do %>
          <div class="relative" id={@field.id <> "-wrapper"} phx-hook="PasswordToggle">
            <input
              type="password"
              name={@field.name}
              id={@field.id}
              value={Form.normalize_value("password", @field.value)}
              placeholder={@placeholder}
              class={[
                "input input-bordered w-full !pr-11",
                @field.errors != [] && "input-error",
                @class
              ]}
              {@rest}
            />
            <button
              type="button"
              data-password-toggle
              tabindex="-1"
              aria-label="Show password"
              class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 focus:outline-none"
            >
              <span data-icon-show class="hero-eye w-5 h-5"></span>
              <span data-icon-hide class="hero-eye-slash w-5 h-5 hidden"></span>
            </button>
          </div>
        <% else %>
          <input
            type={@type}
            name={@field.name}
            id={@field.id}
            value={Form.normalize_value(@type, @field.value)}
            placeholder={@placeholder}
            class={[
              "input input-bordered w-full",
              @field.errors != [] && "input-error",
              @class
            ]}
            {@rest}
          />
        <% end %>
      <% end %>
      <% end %>
      <.error :for={msg <- @field.errors}>{translate_error(msg)}</.error>
    </div>
    """
  end

  @doc """
  Renders a button using DaisyUI styling.

  ## Examples

      <.button type="submit">Save</.button>
      <.button type="button" variant="outline">Cancel</.button>
      <.button type="button" variant="error">Delete</.button>
  """
  attr :type, :string, default: "button"

  attr :variant, :string,
    default: "primary",
    values: ~w(primary secondary accent neutral outline error warning success info)

  attr :size, :string, default: "md", values: ~w(xs sm md lg)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "btn",
        button_variant_class(@variant),
        button_size_class(@size),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a Heroicon.

  ## Examples

      <.icon name="hero-home" />
      <.icon name="hero-user" class="w-6 h-6" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "w-5 h-5"
  attr :style, :string, default: nil
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} style={@style} {@rest} />
    """
  end

  # ============================================================================
  # PAGE-SPECIFIC UI COMPONENTS
  # ============================================================================

  @doc """
  Renders a page header with title and optional actions.

  ## Examples

      <.page_header title="Students" subtitle="Manage student accounts" />
      <.page_header title="Dashboard">
        <:actions>
          <.button type="button" variant="primary">Add Student</.button>
        </:actions>
      </.page_header>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :string, default: nil

  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class={[
      "flex items-center justify-between gap-6 pb-6",
      @class
    ]}>
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{@title}</h1>
        <p :if={@subtitle} class="text-sm text-gray-600 mt-1">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-3">
        <%= for action <- @actions do %>
          {render_slot(action)}
        <% end %>
      </div>
    </header>
    """
  end

  @doc """
  Renders a data table using DaisyUI styling.

  ## Examples

      <.data_table id="students" rows={@students}>
        <:col :let={student} label="Name">{student.name}</:col>
        <:col :let={student} label="Email">{student.email}</:col>
        <:action :let={student}>
          <.button type="button" variant="outline" size="sm">Edit</.button>
        </:action>
      </.data_table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_click, :any, default: nil
  attr :class, :string, default: nil

  slot :col, required: true do
    attr :label, :string, required: true
  end

  slot :action

  def data_table(assigns) do
    ~H"""
    <div class={["overflow-x-auto", @class]}>
      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th :for={col <- @col}>{col.label}</th>
            <th :if={@action != []}>
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @rows}
            class={[@row_click && "hover:cursor-pointer hover:bg-base-200"]}
            phx-click={@row_click && @row_click.(row)}
          >
            <td :for={col <- @col}>
              {render_slot(col, row)}
            </td>
            <td :if={@action != []} class="w-0">
              <div class="flex gap-2">
                <%= for action <- @action do %>
                  {render_slot(action, row)}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a card container using DaisyUI styling.

  ## Examples

      <.card>
        <h3>Student Information</h3>
        <p>Student details go here...</p>
      </.card>

      <.card class="bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Card title!</h2>
          <p>Card content...</p>
        </div>
      </.card>
  """
  attr :class, :string, default: "bg-base-100 shadow-sm border border-base-300"
  attr :rest, :global

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["card", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a modal using DaisyUI styling.

  ## Examples

      <.modal id="confirm-modal" title="Confirm Action">
        <p>Are you sure you want to delete this student?</p>
        <:actions>
          <.button type="button" variant="error">Delete</.button>
          <.button type="button" variant="outline">Cancel</.button>
        </:actions>
      </.modal>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <dialog id={@id} class={["modal", @class]}>
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{@title}</h3>
        <div class="py-4">
          {render_slot(@inner_block)}
        </div>
        <div :if={@actions != []} class="modal-action">
          <%= for action <- @actions do %>
            {render_slot(action)}
          <% end %>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  @doc """
  Renders a loading spinner using DaisyUI styling.

  ## Examples

      <.loading_spinner />
      <.loading_spinner size="lg" />
      <.loading_spinner text="Loading students..." />
  """
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :text, :string, default: nil
  attr :class, :string, default: nil

  def loading_spinner(assigns) do
    ~H"""
    <div class={[
      "flex flex-col items-center justify-center gap-2",
      @class
    ]}>
      <span class={[
        "loading loading-spinner",
        loading_size_class(@size)
      ]}></span>
      <p :if={@text} class="text-sm text-gray-600">{@text}</p>
    </div>
    """
  end

  # ============================================================================
  # LIVEWIEW COMPATIBILITY COMPONENTS
  # ============================================================================

  @doc """
  Renders flash notices using the basic toast component.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss, :boolean, default: true,
    doc: "auto-close after `auto_dismiss_after` ms (set false for connection-state flashes)"
  attr :auto_dismiss_after, :integer, default: 5000
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook={@auto_dismiss && "AutoDismissToast"}
      data-duration={@auto_dismiss && @auto_dismiss_after}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50 cursor-pointer"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.nav_button>Send!</.nav_button>
      <.nav_button phx-click="go" variant="primary">Send!</.nav_button>
      <.nav_button navigate={~p"/"}>Home</.nav_button>
  """
  attr :rest, :global, include: ~w(href navigate patch method)
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def nav_button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}
    assigns = assign(assigns, :class, Map.fetch!(variants, assigns[:variant]))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={["btn", @class]} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={["btn", @class]} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  # ============================================================================
  # JS COMMANDS
  # ============================================================================

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.add_class("modal-open", to: "body")
  end

  def hide_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.hide(transition: "fade-out", to: "##{id}")
    |> JS.remove_class("modal-open", to: "body")
  end

  def toggle(js \\ %JS{}, selector) do
    JS.toggle(js,
      to: selector,
      in:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"},
      out:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def focus(js \\ %JS{}, selector) do
    JS.focus(js, to: selector)
  end

  def push_focus(js \\ %JS{}, selector) do
    JS.push_focus(js, to: selector)
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  defp toast_alert_class("success"), do: "alert-success"
  defp toast_alert_class("error"), do: "alert-error"
  defp toast_alert_class("warning"), do: "alert-warning"
  defp toast_alert_class("info"), do: "alert-info"
  defp toast_alert_class(_), do: "alert-info"

  defp toast_icon(%{type: "success"} = assigns) do
    ~H"""
    <.icon name="hero-check-circle" class="w-5 h-5" />
    """
  end

  defp toast_icon(%{type: "error"} = assigns) do
    ~H"""
    <.icon name="hero-x-circle" class="w-5 h-5" />
    """
  end

  defp toast_icon(%{type: "warning"} = assigns) do
    ~H"""
    <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
    """
  end

  defp toast_icon(%{type: "info"} = assigns) do
    ~H"""
    <.icon name="hero-information-circle" class="w-5 h-5" />
    """
  end

  defp button_variant_class("primary"), do: "btn-primary"
  defp button_variant_class("secondary"), do: "btn-secondary"
  defp button_variant_class("accent"), do: "btn-accent"
  defp button_variant_class("neutral"), do: "btn-neutral"
  defp button_variant_class("outline"), do: "btn-outline"
  defp button_variant_class("error"), do: "btn-error"
  defp button_variant_class("warning"), do: "btn-warning"
  defp button_variant_class("success"), do: "btn-success"
  defp button_variant_class("info"), do: "btn-info"
  defp button_variant_class(_), do: "btn-primary"

  defp button_size_class("xs"), do: "btn-xs"
  defp button_size_class("sm"), do: "btn-sm"
  defp button_size_class("md"), do: "btn-md"
  defp button_size_class("lg"), do: "btn-lg"
  defp button_size_class(_), do: "btn-md"

  defp loading_size_class("sm"), do: "loading-sm"
  defp loading_size_class("md"), do: "loading-md"
  defp loading_size_class("lg"), do: "loading-lg"
  defp loading_size_class(_), do: "loading-md"

  # Helper functions for select options
  defp option_value(option) when is_tuple(option), do: elem(option, 0)
  defp option_value(option) when is_binary(option), do: option
  defp option_value(option), do: to_string(option)

  defp option_label(option) when is_tuple(option), do: elem(option, 1)
  defp option_label(option) when is_binary(option), do: option
  defp option_label(option), do: to_string(option)

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="label-text-alt text-error mt-1">
      <.icon name="hero-exclamation-circle" class="w-4 h-4 inline mr-1" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Helper to translate Ecto validation error tuples to strings
  defp translate_error({msg, opts}) do
    # If you have a translation backend, you can use it here
    # For now, we'll just return the message as-is
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg) when is_binary(msg), do: msg
  defp translate_error(msg), do: to_string(msg)

  @doc """
  Reusable paginator. Renders "Showing X–Y of Z" + Prev/Next + windowed page numbers.

  Sends a `phx-click={@event}` with `phx-value-page={page}` for each control.
  The owning LiveView handles that event to slice its in-memory list and reset
  the `current_page` assign.

  Renders nothing when `total <= per_page` (single page).

  ## Attrs
    * `current_page` (integer, required) — 1-based current page
    * `total` (integer, required) — total number of items across all pages
    * `per_page` (integer, default 10)
    * `event` (string, required) — phx-click event name (e.g. `"goto_students_page"`)
    * `class` (string, default nil) — extra wrapper classes
    * `label` (string, default `"results"`) — shown in summary text
  """
  attr :current_page, :integer, required: true
  attr :total, :integer, required: true
  attr :per_page, :integer, default: 10
  attr :event, :string, required: true
  attr :class, :string, default: nil
  attr :label, :string, default: "results"

  def paginator(assigns) do
    total = max(assigns.total, 0)
    per_page = max(assigns.per_page, 1)
    total_pages = if total == 0, do: 1, else: div(total - 1, per_page) + 1
    current = assigns.current_page |> max(1) |> min(total_pages)
    start_item = if total == 0, do: 0, else: (current - 1) * per_page + 1
    end_item = min(current * per_page, total)
    pages = paginator_window(current, total_pages)

    assigns =
      assigns
      |> assign(:current_page, current)
      |> assign(:total_pages, total_pages)
      |> assign(:start_item, start_item)
      |> assign(:end_item, end_item)
      |> assign(:pages, pages)

    ~H"""
    <div :if={@total_pages > 1 or @total > 0} class={["flex flex-wrap items-center justify-between gap-3 mt-4", @class]}>
      <div class="text-sm text-gray-600">
        <%= if @total == 0 do %>
          No <%= @label %>
        <% else %>
          Showing <span class="font-medium"><%= @start_item %></span>–<span class="font-medium"><%= @end_item %></span>
          of <span class="font-medium"><%= @total %></span> <%= @label %>
        <% end %>
      </div>

      <div :if={@total_pages > 1} class="flex items-center space-x-1">
        <button
          type="button"
          phx-click={@event}
          phx-value-page={@current_page - 1}
          disabled={@current_page <= 1}
          class={[
            "px-3 py-1.5 text-sm font-medium rounded-md border",
            if(@current_page <= 1, do: "border-gray-200 text-gray-300 cursor-not-allowed", else: "border-gray-300 text-gray-700 hover:bg-gray-50")
          ]}
        >
          Prev
        </button>

        <%= for entry <- @pages do %>
          <%= case entry do %>
            <% :gap -> %>
              <span class="px-2 py-1.5 text-sm text-gray-400">…</span>
            <% page when is_integer(page) -> %>
              <button
                type="button"
                phx-click={@event}
                phx-value-page={page}
                class={[
                  "px-3 py-1.5 text-sm font-medium rounded-md border",
                  if(page == @current_page,
                    do: "bg-orange-500 border-orange-500 text-white",
                    else: "border-gray-300 text-gray-700 hover:bg-gray-50")
                ]}
              >
                <%= page %>
              </button>
          <% end %>
        <% end %>

        <button
          type="button"
          phx-click={@event}
          phx-value-page={@current_page + 1}
          disabled={@current_page >= @total_pages}
          class={[
            "px-3 py-1.5 text-sm font-medium rounded-md border",
            if(@current_page >= @total_pages, do: "border-gray-200 text-gray-300 cursor-not-allowed", else: "border-gray-300 text-gray-700 hover:bg-gray-50")
          ]}
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders the standard "Something went wrong" error card with Retry and
  Back to Dashboard actions, shared across all student assessment/session
  LiveViews (behavioral, interview, JAM, case study, MCQ, mini project,
  psychometric, resume insights).

  ## Examples

      <.error_card error_message={@error_message} retry_event="start_new_assessment" />
      <.error_card
        error_message={@error}
        retry_event="retry_interview"
        dashboard_event="go_to_dashboard"
      />
  """
  attr :title, :string, default: "Something went wrong"
  attr :error_message, :string, default: nil
  attr :retry_event, :string, required: true
  attr :dashboard_event, :string, default: "back_to_dashboard"
  attr :enter_fullscreen, :boolean, default: false
  attr :class, :string, default: ""

  def error_card(assigns) do
    ~H"""
    <div class={["bg-white rounded-2xl border p-6", @class]} style="border-color: #FECACA;">
      <div class="flex items-start gap-3 mb-3">
        <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-red-600 mt-0.5" />
        <div>
          <h3 class="text-base font-bold text-red-700">{@title}</h3>
          <p class="text-sm text-gray-600 mt-1">{@error_message || "Please try again."}</p>
        </div>
      </div>
      <div class="flex gap-2 mt-4">
        <button
          phx-click={@retry_event}
          data-enter-fullscreen={@enter_fullscreen}
          class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold transition"
          style="background-color: #FF8B00;"
        >↻ Retry</button>
        <button
          phx-click={@dashboard_event}
          class="px-4 py-2.5 rounded-lg border border-gray-200 text-sm text-gray-700 hover:bg-cream-50 transition"
        >← Back to Dashboard</button>
      </div>
    </div>
    """
  end

  # Build a windowed page list around `current` for `total_pages`.
  # Returns integers and `:gap` markers, e.g. [1, :gap, 5, 6, 7, :gap, 20].
  defp paginator_window(_current, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..max(total_pages, 1))

  defp paginator_window(current, total_pages) when current <= 4,
    do: [1, 2, 3, 4, 5, :gap, total_pages]

  defp paginator_window(current, total_pages) when current >= total_pages - 3,
    do: [1, :gap, total_pages - 4, total_pages - 3, total_pages - 2, total_pages - 1, total_pages]

  defp paginator_window(current, total_pages),
    do: [1, :gap, current - 1, current, current + 1, :gap, total_pages]

  @doc """
  Helper: slice an in-memory list to a given page (1-based) with a page size.
  Pairs with `paginator/1` so the LiveView and component agree on indexing.
  """
  def paginate_list(items, page, per_page) when is_list(items) do
    page = max(page, 1)
    per_page = max(per_page, 1)
    Enum.slice(items, (page - 1) * per_page, per_page)
  end
end
