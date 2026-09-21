defmodule VyaasaCampus.Contexts.Entitlements do
  @moduledoc """
  Per-tenant quotas and the subscription period they reset on (public schema).

  Entitlements are string-keyed integers, so adding a new quota is a new key
  rather than a migration. The first (and currently only enforced) family is
  assessment attempts:

      attempts.default    # applies to every assessment
      attempts.mcq        # overrides the default for one module
      attempts.interview
      …

  **Unlimited is the default.** A missing row, or a row with a NULL value, means
  no cap — so every existing tenant behaves exactly as it did before limits
  existed, until a super admin configures one.
  """

  import Ecto.Query, warn: false

  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Tenants.{Entitlement, Subscription}

  @public "public"

  @doc "Every assessment module an attempt limit can apply to, in display order."
  def attempt_modules,
    do: ~w(resume mcq behavioral psychometric jam interview case_study mini_project)

  @doc "Entitlement key for a module's attempt cap (`nil`/`:default` → the global default)."
  def attempts_key(module \\ :default)
  def attempts_key(module) when module in [nil, :default, "default"], do: "attempts.default"
  def attempts_key(module), do: "attempts.#{module}"

  # ======================================================================
  # Reads
  # ======================================================================

  @doc "All entitlement rows for a tenant as `%{key => value}` (value may be nil)."
  def map_for_tenant(tenant_id) do
    Entitlement
    |> where([e], e.tenant_id == ^tenant_id)
    |> Repo.all(prefix: @public)
    |> Map.new(&{&1.key, &1.value})
  end

  @doc "Entitlement rows for a tenant (for the admin UI)."
  def list_for_tenant(tenant_id) do
    Entitlement
    |> where([e], e.tenant_id == ^tenant_id)
    |> order_by([e], asc: e.key)
    |> Repo.all(prefix: @public)
  end

  @doc """
  The attempt limit for a module: **per-module override → global default →
  `nil` (unlimited)**.

  Pass `entitlements` (from `map_for_tenant/1`) to resolve several modules
  without re-querying.
  """
  def attempt_limit(tenant_id, module) when is_binary(tenant_id) do
    attempt_limit(map_for_tenant(tenant_id), module)
  end

  def attempt_limit(entitlements, module) when is_map(entitlements) do
    module_key = attempts_key(to_string(module))

    cond do
      # A key present with an explicit value wins, including 0 ("blocked entirely").
      is_integer(Map.get(entitlements, module_key)) -> Map.get(entitlements, module_key)
      is_integer(Map.get(entitlements, "attempts.default")) -> Map.get(entitlements, "attempts.default")
      true -> nil
    end
  end

  @doc "Raw value for a key, or nil."
  def get(tenant_id, key) do
    case Repo.get_by(Entitlement, [tenant_id: tenant_id, key: key], prefix: @public) do
      nil -> nil
      row -> row.value
    end
  end

  # ======================================================================
  # Writes
  # ======================================================================

  @doc """
  Set an entitlement. `nil` stores "unlimited" explicitly; use `clear/2` to
  remove the row so it falls back to the default instead.
  """
  def put(tenant_id, key, value, updated_by_id \\ nil) do
    row =
      Repo.get_by(Entitlement, [tenant_id: tenant_id, key: key], prefix: @public) ||
        %Entitlement{}

    row
    |> Entitlement.changeset(%{
      tenant_id: tenant_id,
      key: key,
      value: value,
      updated_by_id: updated_by_id
    })
    |> Repo.insert_or_update(prefix: @public)
  end

  @doc "Remove an entitlement so it inherits the default (or unlimited)."
  def clear(tenant_id, key) do
    Entitlement
    |> where([e], e.tenant_id == ^tenant_id and e.key == ^key)
    |> Repo.delete_all(prefix: @public)

    :ok
  end

  @doc """
  Apply a whole attempt configuration at once.

  `attrs` is `%{"default" => 3, "mcq" => 5, "interview" => nil, …}` where a nil
  or blank value clears the override.
  """
  def put_attempt_limits(tenant_id, attrs, updated_by_id \\ nil) when is_map(attrs) do
    Enum.each(attrs, fn {module, value} ->
      key = attempts_key(to_string(module))

      case normalize_limit(value) do
        :clear -> clear(tenant_id, key)
        {:ok, v} -> put(tenant_id, key, v, updated_by_id)
      end
    end)

    :ok
  end

  # "" / nil → remove the row; "0" → a real zero (blocked); "5" → 5.
  defp normalize_limit(v) when v in [nil, ""], do: :clear
  defp normalize_limit(v) when is_integer(v), do: {:ok, v}

  defp normalize_limit(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} when n >= 0 -> {:ok, n}
      _ -> :clear
    end
  end

  defp normalize_limit(_), do: :clear

  # ======================================================================
  # Subscription period
  # ======================================================================

  @doc "The tenant's subscription row, or nil."
  def get_subscription(tenant_id) do
    Repo.get_by(Subscription, [tenant_id: tenant_id], prefix: @public)
  end

  @doc """
  The window attempts are counted in: `{period_start, period_end}`, or `nil`
  meaning "count everything ever".

  Either bound may be nil (an open-ended period).
  """
  def current_period(tenant_id) do
    case get_subscription(tenant_id) do
      nil -> nil
      %Subscription{period_start: nil, period_end: nil} -> nil
      %Subscription{} = sub -> {sub.period_start, sub.period_end}
    end
  end

  @doc "Create or update the tenant's subscription window."
  def put_subscription(tenant_id, attrs) do
    row = get_subscription(tenant_id) || %Subscription{}

    # Ecto rejects params with mixed atom/string keys, so stringify everything
    # before merging in tenant_id.
    params = attrs |> normalize_keys() |> Map.put("tenant_id", tenant_id)

    row
    |> Subscription.changeset(params)
    |> Repo.insert_or_update(prefix: @public)
  end

  defp normalize_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
