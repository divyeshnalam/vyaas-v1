defmodule VyaasaCampusWeb.Admin.AddCollegeLive do
  @moduledoc """
  Super-admin "Add College" — onboards a new college tenant (schema + record +
  tenant admin user) via `Tenants.create_tenant`. Matched to the Figma mockup.
  """

  use VyaasaCampusWeb, :live_view

  alias VyaasaCampus.Contexts.Tenants
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Accounts.User

  import VyaasaCampusWeb.Components.UI
  import VyaasaCampusWeb.Components.Admin.SuperAdminShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_tenants, length(Tenants.list_tenants()))
     |> assign(:user_info, user_info(socket.assigns[:current_user]))
     |> assign(:form, to_form(%{}, as: :college))
     |> assign(:code_taken?, false)
     |> assign(:saving?, false)}
  end

  @impl true
  def handle_event("validate", %{"college" => params}, socket) do
    # Inline duplicate-code check (Vya-008): surface a persistent field error as
    # the admin types, instead of only a transient flash on a failed submit.
    code_taken? = Tenants.alias_taken?(sanitize_alias(params["college_code"]))
    # Strip non-digits and cap at 6 chars as the admin types, since India PIN
    # codes are always 6 numeric digits (maxlength/pattern alone don't stop paste).
    params = Map.update(params, "pin_code", "", &sanitize_pin_code/1)

    {:noreply,
     socket
     |> assign(:form, to_form(params, as: :college))
     |> assign(:code_taken?, code_taken?)}
  end

  @impl true
  def handle_event("show_coming_soon", _params, socket) do
    {:noreply, put_flash(socket, :info, "Coming soon!")}
  end

  @impl true
  def handle_event("create_college", %{"college" => p}, socket) do
    socket = assign(socket, :saving?, true)
    current_user = socket.assigns.current_user
    alias_code = sanitize_alias(p["college_code"])
    pin_code = sanitize_pin_code(p["pin_code"])

    cond do
      blank?(p["college_name"]) or blank?(alias_code) ->
        {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "College name and code are required.")}

      blank?(p["admin_email"]) ->
        {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "Tenant admin email is required.")}

      blank?(p["contact_email"]) ->
        {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "College contact email is required.")}

      pin_code != "" and String.length(pin_code) != 6 ->
        {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "Pin code must be exactly 6 digits.")}

      true ->
        tenant_attrs = %{
          "full_name" => p["college_name"],
          "short_name" => p["college_code"],
          "alias" => alias_code,
          "affiliation_type" => p["affiliation_type"] || "college",
          "email" => p["contact_email"],
          "phone" => p["contact_phone"],
          "website_url" => p["website"],
          "status" => "active",
          "settings" => %{
            "university" => p["university"],
            "accreditation" => p["accreditation"],
            "contact_person" => p["contact_person"]
          },
          "created_by" => current_user.id
        }

        case Tenants.create_tenant(tenant_attrs) do
          {:ok, tenant} ->
            create_tenant_location(tenant, p, pin_code)

            case create_tenant_admin(tenant, p, current_user) do
              :ok ->
                {:noreply,
                 socket
                 |> put_flash(:info, "College \"#{p["college_name"]}\" created. Admin account set up for #{p["admin_email"]}.")
                 |> push_navigate(to: ~p"/admin/colleges")}

              {:error, reason} ->
                require Logger
                Logger.warning("College created but admin user failed: #{inspect(reason)}")
                {:noreply,
                 socket
                 |> assign(:saving?, false)
                 |> put_flash(:info, "College \"#{p["college_name"]}\" created, but admin account setup failed. Please add the admin manually.")
                 |> push_navigate(to: ~p"/admin/colleges")}
            end

          {:error, :tenant_already_exists} ->
            {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "A college with this code already exists. Use a different code.")}

          {:error, %Ecto.Changeset{} = cs} ->
            msgs =
              cs.errors
              |> Enum.map(fn {f, {m, opts}} ->
                message = Enum.reduce(opts, m, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
                "#{Phoenix.Naming.humanize(f)}: #{message}"
              end)
              |> Enum.join(", ")

            {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "Please fix the following: #{msgs}.")}

          {:error, _} ->
            {:noreply, socket |> assign(:saving?, false) |> put_flash(:error, "College creation failed. Please try again or contact support.")}
        end
    end
  end

  defp create_tenant_location(tenant, p, pin_code) do
    if blank?(p["address"]) and pin_code == "" do
      :ok
    else
      case Tenants.create_tenant_location(%{
             "name" => tenant.full_name,
             "address" => p["address"],
             "pincode" => pin_code,
             "is_primary" => true,
             "tenant_id" => tenant.id
           }) do
        {:ok, _location} ->
          :ok

        {:error, reason} ->
          require Logger
          Logger.warning("College created but location failed: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp create_tenant_admin(tenant, p, current_user) do
    {first, last} = split_name(p["admin_name"], tenant.short_name)
    password = if blank?(p["admin_password"]), do: random_password(), else: p["admin_password"]

    admin_attrs = %{
      email: p["admin_email"],
      encrypted_password: Bcrypt.hash_pwd_salt(password),
      first_name: first,
      last_name: last,
      role: "admin",
      status: "active",
      tenant_id: tenant.id,
      created_by_id: current_user.id,
      created_by_type: "public"
    }

    try do
      case %User{} |> User.changeset(admin_attrs) |> Repo.insert(prefix: tenant.schema_name) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={:super_admin}>
      <.admin_layout active_tenants={@active_tenants} user_info={@user_info} current_section="colleges">
        <.form for={@form} phx-change="validate" phx-submit="create_college" id="add-college-form">
          <div class="px-4 sm:px-6 lg:px-10 py-8 max-w-275 mx-auto w-full">
            <div class="flex flex-wrap items-start justify-between gap-4 mb-6">
              <div>
                <p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#F97316] mb-1">Tenants</p>
                <div class="flex items-center gap-2">
                  <.link navigate={~p"/admin/colleges"} class="text-gray-400 hover:text-gray-700">
                    <.icon name="hero-arrow-left" class="w-5 h-5" />
                  </.link>
                  <h1 class="text-2xl font-bold text-gray-900">Add College</h1>
                </div>
                <p class="text-sm text-gray-500 mt-0.5">Onboard a new college tenant. They'll be live on VYAASA in minutes.</p>
              </div>
              <div class="flex items-center gap-2">
                <.link navigate={~p"/admin/colleges"} class="px-4 py-2 rounded-lg text-sm font-medium text-gray-600 hover:bg-gray-50 transition">Cancel</.link>
                <button type="button" phx-click="show_coming_soon" class="px-4 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 transition">Save Draft</button>
                <button type="submit" disabled={@saving? or @code_taken?} class="inline-flex items-center gap-1.5 px-5 py-2 rounded-lg text-sm font-semibold text-white transition disabled:opacity-60 disabled:cursor-not-allowed" style="background-color: #F97316;">
                  {if @saving?, do: "Creating…", else: "Create College"}
                </button>
              </div>
            </div>

            <.section_card title="College Information">
              <.fld field={@form[:college_name]} label="College Name" placeholder="Vellore Institute of Technology" />
              <.fld field={@form[:college_code]} label="College Code" placeholder="VIT-VLR" debounce="350"
                error={if @code_taken?, do: "This college code is already taken. Choose a different one.", else: nil} />
              <.select_fld field={@form[:affiliation_type]} label="Institution Type"
                options={[{"College", "college"}, {"University", "university"}, {"Institute", "institute"}, {"School", "school"}, {"Corporate", "corporate"}]}
                value={@form[:affiliation_type].value || "college"} />
              <.fld field={@form[:university]} label="University / Board" placeholder="VIT University" />
              <.fld field={@form[:website]} label="Website" placeholder="https://vit.ac.in" />
              <.fld field={@form[:accreditation]} label="Accreditation" placeholder="NAAC A++, NBA" />
              <.fld field={@form[:address]} label="Address" placeholder="Enter College Address" />
              <.fld field={@form[:pin_code]} type="text" inputmode="numeric" maxlength="6" label="Pin Code" placeholder="Enter Pin Code"/>
            </.section_card>

            <.section_card title="Contact Information">
              <.fld field={@form[:contact_person]} label="Contact Person" placeholder="Dr. Suresh Kumar" />
              <.fld field={@form[:contact_email]} label="Email" type="email" placeholder="placement@vit.ac.in" />
              <.fld field={@form[:contact_phone]} inputmode="numeric" label="Phone" placeholder="+91 9876543210" />
            </.section_card>

            <.section_card title="Tenant Admin">
              <.fld field={@form[:admin_name]} label="Admin Name" placeholder="Placement Officer" />
              <.fld field={@form[:admin_email]} label="Admin Email" type="email" placeholder="Admin@vit.ac.in" />
              <.fld field={@form[:admin_password]} label="Temporary Password" type="password" placeholder="Generate or set" />
            </.section_card>
          </div>
        </.form>
      </.admin_layout>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 mb-5">
      <h3 class="text-[11px] font-bold uppercase tracking-[0.12em] text-gray-500 mb-4">{@title}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :error, :string, default: nil
  attr :debounce, :string, default: nil
  attr :inputmode, :string, default: nil
  attr :maxlength, :string, default: nil

  defp fld(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">{@label}</label>
      <div class="relative">
        <input type={@type} name={@field.name} id={@field.id} value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
          placeholder={@placeholder} phx-debounce={@debounce} inputmode={@inputmode} maxlength={@maxlength}
          class={[
            "w-full px-3 py-2 rounded-lg bg-white border text-sm text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-2",
            @type == "password" && "pr-9",
            if(@error, do: "border-red-300 focus:ring-red-100 focus:border-red-400", else: "border-gray-200 focus:ring-orange-100 focus:border-[#F97316]")
          ]} />
        <button
          :if={@type == "password"}
          type="button"
          tabindex="-1"
          phx-click={
            JS.toggle_attribute({"type", "text", "password"}, to: "##{@field.id}")
            |> JS.toggle_class("hero-eye hero-eye-slash", to: "##{@field.id}-eye-icon")
          }
          class="absolute right-2.5 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
        >
          <.icon name="hero-eye" id={"#{@field.id}-eye-icon"} class="w-4 h-4" />
        </button>
      </div>
      <p :if={@error} class="mt-1 text-xs text-red-600 flex items-center gap-1">
        <.icon name="hero-exclamation-circle" class="w-3.5 h-3.5" />{@error}
      </p>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: ""

  defp select_fld(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1.5">{@label}</label>
      <select name={@field.name} id={@field.id}
        class="w-full px-3 py-2 rounded-lg bg-white border border-gray-200 text-sm text-gray-800 focus:outline-none focus:ring-2 focus:ring-orange-100 focus:border-[#F97316]">
        <%= for {label, val} <- @options do %>
          <option value={val} selected={@value == val}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────────
  defp user_info(nil), do: %{name: "Super Admin", role: "Platform Admin"}
  defp user_info(u), do: %{name: String.trim("#{u.first_name} #{u.last_name}"), role: "Platform Admin", email: u.email}

  defp sanitize_alias(nil), do: ""
  defp sanitize_alias(code), do: code |> to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "") |> String.downcase()

  defp sanitize_pin_code(nil), do: ""
  defp sanitize_pin_code(code), do: code |> to_string() |> String.replace(~r/[^0-9]/, "") |> String.slice(0, 6)

  defp blank?(nil), do: true
  defp blank?(v), do: String.trim(to_string(v)) == ""

  defp split_name(nil, fallback), do: {"Admin", fallback || ""}

  defp split_name(name, fallback) do
    case String.split(String.trim(name), ~r/\s+/, parts: 2) do
      [f, l] -> {f, l}
      [f] -> {f, fallback || ""}
      _ -> {"Admin", fallback || ""}
    end
  end

  defp random_password do
    :crypto.strong_rand_bytes(9) |> Base.url_encode64() |> binary_part(0, 12)
  end
end
