defmodule VyaasaCampus.AI.Tracing do
  @moduledoc """
  Opik grouping helpers on top of OpenTelemetry.

    * `span/3` opens a parent span, so every LLM call an operation makes lands
      in ONE Opik trace instead of one trace per call.
    * A `thread_id` attribute groups traces into an Opik thread (one thread per
      assessment session). Engines whose state carries a session id pass it to
      `span/3`; for the rest, the owning process (LiveView / Oban job) calls
      `put_thread_id/1` once and every span that process starts picks it up.
    * `put_metadata/1` labels every span with filterable Opik metadata
      (student_id, module, tenant) — sent as `opik.metadata.<key>` attributes,
      which Opik stores as span metadata (and trace metadata on the root span).
  """

  require OpenTelemetry.Tracer, as: Tracer

  @key :opik_thread_id
  @meta_key :opik_metadata

  def put_thread_id(nil), do: :ok
  def put_thread_id(id), do: Process.put(@key, to_string(id))

  def thread_id, do: Process.get(@key)

  @doc """
  Runs `fun` with `id` as this process's Opik thread id, then restores the
  previous value — so the id never leaks past the call (safe in reused
  processes such as an HTTP request handler). Returns `fun`'s result
  untouched; a nil `id` just runs `fun`.
  """
  def with_thread_id(nil, fun), do: fun.()

  def with_thread_id(id, fun) do
    previous = Process.get(@key)
    put_thread_id(id)

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc """
  Remember Opik filter metadata (e.g. `%{student_id: id, module: "jam", tenant: schema}`)
  for this process. Spans opened by this process — or by any Task it starts,
  via `$callers` — carry it. Replaces any previous value; nil values are
  dropped. Tracing-only: never raises and never affects the caller.
  """
  def put_metadata(meta) when is_map(meta) do
    clean = for {k, v} <- meta, not is_nil(v), into: %{}, do: {to_string(k), to_string(v)}
    Process.put(@meta_key, clean)
    :ok
  rescue
    _ -> :ok
  end

  def put_metadata(_), do: :ok

  @doc """
  The current metadata as `opik.metadata.<key>` span attributes (`%{}` when
  none). Looks in this process first, then up the `$callers` chain that
  Task / Task.Supervisor set, so a LiveView's Task inherits the LiveView's
  metadata without being changed. Never raises.
  """
  def metadata_attributes do
    case Process.get(@meta_key) || metadata_from_callers(Process.get(:"$callers", [])) do
      meta when is_map(meta) -> Map.new(meta, fn {k, v} -> {"opik.metadata." <> k, v} end)
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp metadata_from_callers([pid | rest]) when is_pid(pid) do
    with {:dictionary, dict} <- Process.info(pid, :dictionary),
         {_, meta} <- List.keyfind(dict, @meta_key, 0) do
      meta
    else
      _ -> metadata_from_callers(rest)
    end
  end

  defp metadata_from_callers([_ | rest]), do: metadata_from_callers(rest)
  defp metadata_from_callers(_), do: nil

  def span(name, thread_id \\ nil, fun) do
    # Remember the session for this process, so the caller's own direct
    # GroqClient calls (e.g. transcribe / TTS from the LiveView) join the thread too.
    put_thread_id(thread_id)

    Tracer.with_span name do
      if id = thread_id || thread_id(), do: Tracer.set_attribute("thread_id", to_string(id))
      Tracer.set_attributes(metadata_attributes())

      result = fun.()

      with {:error, reason} <- result do
        Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
      end

      result
    end
  end
end