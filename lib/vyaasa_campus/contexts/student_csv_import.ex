defmodule VyaasaCampus.Contexts.StudentCsvImport do
  @moduledoc """
  Parses a CSV file of student records and creates them via
  `Students.create_partial_student/3`, preserving per-row error context so the
  UI can report which CSV row failed and why.
  """

  require Logger
  alias VyaasaCampus.Contexts.{Academics, Students}

  @required_headers ~w(email first_name last_name phone registration_id degree specialization year_of_passing cgpa)

  @type ctx :: %{
          required(:tenant_id) => binary(),
          required(:tenant_alias) => binary(),
          required(:tenant_schema) => binary(),
          required(:created_by_id) => binary(),
          required(:created_by_type) => binary()
        }

  @type result :: %{
          successes: [map()],
          errors: [%{row: integer(), email: String.t() | nil, errors: map()}],
          total: non_neg_integer(),
          success_count: non_neg_integer(),
          error_count: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @spec parse_and_create(Path.t(), ctx) ::
          {:ok, result}
          | {:error, :invalid_csv, String.t()}
          | {:error, :missing_headers, [String.t()]}
          | {:error, :no_rows}

  def parse_and_create(path, ctx) do
    with {:ok, rows} <- parse(path),
         :ok <- validate_headers(rows) do
      indexed_rows = Enum.with_index(rows, 2)
      start_time = System.monotonic_time(:millisecond)
      allowed = load_allowed_academics(ctx.tenant_id)

      results =
        indexed_rows
        |> Task.async_stream(
          fn {row, idx} -> create_one(row, idx, ctx, allowed) end,
          max_concurrency: System.schedulers_online(),
          ordered: true,
          timeout: :infinity,
          on_timeout: :kill_task
        )
        |> Enum.to_list()

      duration = System.monotonic_time(:millisecond) - start_time
      {successes, errors} = split_results(results, indexed_rows)

      {:ok,
       %{
         successes: successes,
         errors: errors,
         total: length(indexed_rows),
         success_count: length(successes),
         error_count: length(errors),
         duration_ms: duration
       }}
    end
  end

  defp parse(path) do
    rows =
      path
      |> File.stream!()
      |> CSV.decode!(headers: true)
      |> Enum.to_list()

    {:ok, rows}
  rescue
    e -> {:error, :invalid_csv, Exception.message(e)}
  end

  defp validate_headers([]), do: {:error, :no_rows}

  defp validate_headers([first | _]) do
    headers =
      first
      |> Map.keys()
      |> Enum.map(&normalize_header/1)

    missing = @required_headers -- headers
    if missing == [], do: :ok, else: {:error, :missing_headers, missing}
  end

  defp normalize_header(h) when is_binary(h), do: h |> String.trim() |> String.downcase()
  defp normalize_header(h), do: h

  defp create_one(row, idx, ctx, allowed) do
    params = build_params(row, ctx)

    case validate_academics(params, allowed) do
      {:error, errors} ->
        {:error, idx, params["email"], errors}

      :ok ->
        case Students.create_partial_student(params, ctx.tenant_alias, ctx.tenant_schema) do
          {:ok, student} ->
            {:ok, idx, student}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, idx, params["email"], format_errors(changeset)}

          {:error, reason} ->
            {:error, idx, params["email"], %{base: ["#{inspect(reason)}"]}}
        end
    end
  end

  # The tenant's offered degrees + specializations as downcased name sets (the
  # same source as the Add Student dropdowns). Empty set = not configured →
  # skip validation rather than reject every row.
  defp load_allowed_academics(tenant_id) do
    {degrees, specializations} = Academics.get_tenant_degree_options(tenant_id)
    %{degrees: name_set(degrees), specializations: name_set(specializations)}
  rescue
    _ -> %{degrees: MapSet.new(), specializations: MapSet.new()}
  end

  defp name_set(options) do
    options
    |> Enum.map(fn {_label, value} -> value end)
    |> Enum.reject(&(to_string(&1) == ""))
    |> Enum.map(&String.downcase(String.trim(to_string(&1))))
    |> MapSet.new()
  end

  # Reject a row whose (non-blank) degree/specialization isn't offered by the
  # tenant. Skipped when the tenant has nothing configured.
  defp validate_academics(params, allowed) do
    errors =
      %{}
      |> check_offered("degree", params["degree"], allowed.degrees)
      |> check_offered("specialization", params["specialization"], allowed.specializations)

    if errors == %{}, do: :ok, else: {:error, errors}
  end

  defp check_offered(errors, field, value, allowed) do
    val = value |> to_string() |> String.trim()

    cond do
      MapSet.size(allowed) == 0 -> errors
      val == "" -> errors
      MapSet.member?(allowed, String.downcase(val)) -> errors
      true -> Map.put(errors, field, ["\"#{val}\" is not offered by this college"])
    end
  end

  defp build_params(row, ctx) do
    row
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, normalize_header(k), normalize_value(v))
    end)
    |> Map.take(@required_headers)
    |> Map.put("tenant_id", ctx.tenant_id)
    |> Map.put("created_by_id", ctx.created_by_id)
    |> Map.put("created_by_type", ctx.created_by_type)
  end

  defp normalize_value(v) when is_binary(v), do: String.trim(v)
  defp normalize_value(v), do: v

  defp split_results(results, indexed_rows) do
    Enum.zip(results, indexed_rows)
    |> Enum.reduce({[], []}, fn
      {{:ok, {:ok, idx, student}}, _}, {oks, errs} ->
        {[%{row: idx, student: student} | oks], errs}

      {{:ok, {:error, idx, email, errors}}, _}, {oks, errs} ->
        {oks, [%{row: idx, email: email, errors: errors} | errs]}

      {{:exit, reason}, {row_data, idx}}, {oks, errs} ->
        email = Map.get(row_data, "email") || Map.get(row_data, :email)
        {oks, [%{row: idx, email: email, errors: %{base: ["task failed: #{inspect(reason)}"]}} | errs]}
    end)
    |> then(fn {oks, errs} -> {Enum.reverse(oks), Enum.reverse(errs)} end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
