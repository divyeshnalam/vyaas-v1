defmodule VyaasaCampus.Auth.AuthServer do
  @moduledoc """
  GenServer for caching authenticated user data to reduce database hits.
  Stores user information with TTL to keep cache fresh.
  """

  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get user from cache by token (deprecated in favor of scopes). Retained for BC.
  """
  def get_user(token), do: GenServer.call(__MODULE__, {:get_user, token})

  @doc """
  Cache user with token (deprecated). Retained for BC.
  """
  def cache_user(token, user, ttl_seconds \\ 3600),
    do: GenServer.cast(__MODULE__, {:cache_user, token, user, ttl_seconds})

  @doc """
  Remove user from cache (logout)
  """
  def remove_user(token) do
    GenServer.cast(__MODULE__, {:remove_user, token})
  end

  @doc """
  Drop every cached token for a given user (all their other devices), so that
  after a new login the old devices miss the cache and are re-checked against the
  current session id. Accepts the user struct.
  """
  def invalidate_user(%{__struct__: mod, id: id}) do
    GenServer.cast(__MODULE__, {:invalidate_user, mod, id})
  end

  def invalidate_user(_), do: :ok

  @doc """
  Clear all cached users
  """
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  @doc """
  Get cache stats
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # =====================
  # Scope cache API (ETS)
  # =====================

  @doc """
  Get a cached scope by key (e.g., access token's jti or token string).
  Returns {:hit, scope} | {:miss} | {:expired}.
  """
  def get_scope(key), do: GenServer.call(__MODULE__, {:get_scope, key})

  @doc """
  Put a scope in cache with TTL seconds.
  """
  def put_scope(key, scope, ttl_seconds \\ default_ttl()),
    do: GenServer.cast(__MODULE__, {:put_scope, key, scope, ttl_seconds})

  @doc """
  Invalidate a scope by key (logout, role change, tenant disable).
  """
  def invalidate_scope(key), do: GenServer.cast(__MODULE__, {:invalidate_scope, key})

  defp default_ttl do
    String.to_integer(System.get_env("SCOPE_TTL_SECONDS") || "300")
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("AuthServer started")
    # Create ETS table for scopes
    table = :ets.new(__MODULE__, [:set, :public, :named_table, read_concurrency: true])
    # table stores: {key, scope, expires_at}

    # Schedule cleanup every 5 minutes
    schedule_cleanup()

    {:ok,
     %{
       # legacy token->user cache
       cache: %{},
       stats: %{hits: 0, misses: 0, size: 0},
       table: table,
       scope_size: 0
     }}
  end

  @impl true
  def handle_call({:get_user, token}, _from, state) do
    case Map.get(state.cache, token) do
      nil ->
        # Cache miss
        new_stats = %{state.stats | misses: state.stats.misses + 1}
        {:reply, {:miss}, %{state | stats: new_stats}}

      {user, expires_at} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          # Cache hit - not expired
          new_stats = %{state.stats | hits: state.stats.hits + 1}
          {:reply, {:hit, user}, %{state | stats: new_stats}}
        else
          # Expired - remove and return miss
          new_cache = Map.delete(state.cache, token)
          new_stats = %{state.stats | misses: state.stats.misses + 1, size: state.stats.size - 1}
          {:reply, {:miss}, %{state | cache: new_cache, stats: new_stats}}
        end
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:get_scope, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, scope, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:reply, {:hit, scope}, state}
        else
          :ets.delete(state.table, key)
          {:reply, {:expired}, %{state | scope_size: max(state.scope_size - 1, 0)}}
        end

      [] ->
        {:reply, {:miss}, state}
    end
  end

  @impl true
  def handle_cast({:cache_user, token, user, ttl_seconds}, state) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)

    # Check if token already exists to avoid double counting
    size_increment = if Map.has_key?(state.cache, token), do: 0, else: 1

    new_cache = Map.put(state.cache, token, {user, expires_at})
    new_stats = %{state.stats | size: state.stats.size + size_increment}

    Logger.debug("Cached user for token: #{String.slice(token, 0, 10)}...")

    {:noreply, %{state | cache: new_cache, stats: new_stats}}
  end

  @impl true
  def handle_cast({:remove_user, token}, state) do
    case Map.get(state.cache, token) do
      nil ->
        {:noreply, state}

      _ ->
        new_cache = Map.delete(state.cache, token)
        new_stats = %{state.stats | size: state.stats.size - 1}
        Logger.debug("Removed user from cache for token: #{String.slice(token, 0, 10)}...")
        {:noreply, %{state | cache: new_cache, stats: new_stats}}
    end
  end

  @impl true
  def handle_cast({:invalidate_user, mod, id}, state) do
    new_cache =
      state.cache
      |> Enum.reject(fn {_token, {user, _exp}} ->
        match?(%{__struct__: ^mod, id: ^id}, user)
      end)
      |> Map.new()

    {:noreply, %{state | cache: new_cache, stats: %{state.stats | size: map_size(new_cache)}}}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    Logger.info("Clearing auth cache")
    new_stats = %{state.stats | size: 0}
    {:noreply, %{state | cache: %{}, stats: new_stats}}
  end

  @impl true
  def handle_cast({:put_scope, key, scope, ttl_seconds}, state) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)
    existed_before = :ets.member(state.table, key)
    :ets.insert(state.table, {key, scope, expires_at})
    size_increment = if existed_before, do: 0, else: 1
    {:noreply, %{state | scope_size: state.scope_size + size_increment}}
  end

  @impl true
  def handle_cast({:invalidate_scope, key}, state) do
    :ets.delete(state.table, key)
    {:noreply, %{state | scope_size: max(state.scope_size - 1, 0)}}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()
    # legacy cache cleanup
    {expired_tokens, valid_cache} =
      Enum.split_with(state.cache, fn {_token, {_user, expires_at}} ->
        DateTime.compare(now, expires_at) != :lt
      end)

    expired_count = length(expired_tokens)

    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired tokens from auth cache")
    end

    new_stats = %{state.stats | size: state.stats.size - expired_count}

    # ETS scope cleanup
    expired =
      state.table
      |> :ets.tab2list()
      |> Enum.filter(fn {_k, _v, exp} -> DateTime.compare(now, exp) != :lt end)

    Enum.each(expired, fn {k, _v, _} -> :ets.delete(state.table, k) end)
    scope_size = max(state.scope_size - length(expired), 0)

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, %{state | cache: Map.new(valid_cache), stats: new_stats, scope_size: scope_size}}
  end

  # Private functions

  defp schedule_cleanup do
    # Clean up every 5 minutes
    Process.send_after(self(), :cleanup_expired, 5 * 60 * 1000)
  end
end
