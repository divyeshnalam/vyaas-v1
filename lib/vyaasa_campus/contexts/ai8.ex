defmodule VyaasaCampus.Contexts.AI8 do
  @moduledoc """
  Context for the AI8 evaluation framework.

  Two concerns:

    * **Config** — the global super-admin matrix (`ai8_module_dimensions`)
      deciding which of the 8 skill dimensions each module evaluates. Public
      schema; one config for all tenants.

    * **Results** — per-student, per-module evaluations (`ai8_module_evaluations`),
      stored in each tenant schema. Each module's engine produces raw 0–100
      per-dimension scores; `module_score` is aggregated here deterministically
      using the configured Module × Dimension weights.
  """

  import Ecto.Query, warn: false

  alias VyaasaCampus.Repo
  alias VyaasaCampus.AI8.{Dimensions, Modules}
  alias VyaasaCampus.Schema.AI8.{DimensionWeight, ModuleDimension, ModuleEvaluation}

  # ======================================================================
  # Config (global / public schema)
  # ======================================================================

  @doc "All config rows."
  def list_config, do: Repo.all(ModuleDimension)

  @doc """
  Config grouped for the admin matrix: `%{module_key => %{dimension_key => row}}`.
  Always returns every (module, dimension) cell (seeds first if needed).
  """
  def config_matrix do
    ensure_seeded()

    list_config()
    |> Enum.group_by(& &1.module)
    |> Map.new(fn {module, rows} ->
      {module, Map.new(rows, fn r -> {r.dimension, r} end)}
    end)
  end

  @doc """
  Enabled dimension keys (strings) for a module, in display order.
  `module` may be an atom or string.
  """
  def enabled_dimensions(module) do
    module = to_string(module)

    ModuleDimension
    |> where([d], d.module == ^module and d.enabled == true)
    |> order_by([d], asc: d.position)
    |> select([d], d.dimension)
    |> Repo.all()
  end

  @doc "Enabled dimensions for a module as `{key, label}` tuples (for UI pills)."
  def enabled_dimension_labels(module) do
    module |> enabled_dimensions() |> Enum.map(&{&1, Dimensions.label(&1)})
  end

  @doc """
  Enabled dimension keys grouped by module, in display order:
  `%{module_string => [dimension_string, ...]}`. One query.
  """
  def enabled_dimensions_by_module do
    ModuleDimension
    |> where([d], d.enabled == true)
    |> order_by([d], asc: d.position)
    |> Repo.all()
    |> Enum.group_by(& &1.module, & &1.dimension)
  end

  @doc """
  Dimension keys that have a percentage weight assigned, grouped by module, in
  display order: `%{module_string => [dimension_string, ...]}`.

  This is what the dashboard pills use — a dimension only appears once the
  super admin has given it a percentage (not merely enabled it).
  """
  def weighted_dimensions_by_module do
    ModuleDimension
    |> where([d], not is_nil(d.weight) and d.weight > 0)
    |> order_by([d], asc: d.position)
    |> Repo.all()
    |> Enum.group_by(& &1.module, & &1.dimension)
  end

  @doc "Configured (weighted) dimension keys for a single module."
  def weighted_dimensions(module) do
    module = to_string(module)

    case weighted_dimensions_by_module() do
      %{^module => dims} -> dims
      _ -> []
    end
  end

  @doc """
  Map a module's per-dimension scores onto its configured dimensions and publish.

  `raw_scores` is `%{dimension => 0..100}` (the module's natural mapping); only
  the dimensions the super admin configured for that module are kept (until a
  module is configured, the raw set is published as-is). `meta` carries
  `:student_id`, `:tenant_id`, `:source_type`, `:source_id`, `:raw_payload`.
  """
  def publish_module(module, raw_scores, meta, prefix) when is_map(raw_scores) and is_binary(prefix) do
    module = to_string(module)
    raw = stringify_keys(raw_scores) |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
    configured = weighted_dimensions(module)
    skill_scores = if configured == [], do: raw, else: Map.take(raw, configured)

    if map_size(skill_scores) > 0 do
      attrs = meta |> Map.put(:module, module) |> Map.put(:skill_scores, skill_scores)
      publish_evaluation(attrs, prefix)
    else
      {:ok, :skipped}
    end
  end

  def publish_module(_module, _raw, _meta, _prefix), do: {:ok, :skipped}

  @doc "Toggle a single (module, dimension) cell on/off."
  def set_enabled(module, dimension, enabled?) when is_boolean(enabled?) do
    upsert_cell(module, dimension, %{enabled: enabled?})
  end

  @doc """
  Set the percentage weight for a (module, dimension) cell. A positive weight
  enables the cell; `nil`/0 disables it. Drives both coverage and aggregation.
  """
  def set_weight(module, dimension, weight) do
    enabled = is_number(weight) and weight > 0
    upsert_cell(module, dimension, %{weight: weight, enabled: enabled})
  end

  defp upsert_cell(module, dimension, attrs) do
    module = to_string(module)
    dimension = to_string(dimension)

    row =
      Repo.get_by(ModuleDimension, module: module, dimension: dimension) ||
        %ModuleDimension{module: module, dimension: dimension, position: Dimensions.position(dimension)}

    row
    |> ModuleDimension.changeset(Map.merge(%{module: module, dimension: dimension}, attrs))
    |> Repo.insert_or_update()
  end

  @doc """
  Idempotently ensure every (module, dimension) cell exists, all disabled with
  no weight. The super admin builds the matrix from scratch by assigning
  percentages — nothing is pre-enabled. Existing rows are never overwritten.
  """
  def ensure_seeded do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for {mkey, _name} <- Modules.all(),
          {dkey, _label} <- Dimensions.all() do
        %{
          module: Atom.to_string(mkey),
          dimension: Atom.to_string(dkey),
          enabled: false,
          position: Dimensions.position(dkey),
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(ModuleDimension, entries,
      on_conflict: :nothing,
      conflict_target: [:module, :dimension]
    )

    :ok
  end

  # The production AI8 configuration. Per-module dimension weights (each module
  # sums to 100) + global dimension weights for the overall index (sum to 100).
  #
  # INVARIANT: every cell here must be a dimension the module's engine actually
  # emits (see `@emitted_dimensions`). A configured dimension no engine produces
  # is permanent dead weight in that dimension's denominator, capping it below
  # 100 forever. `config_audit/0` checks this.
  @production_module_weights %{
    "resume" => %{"domain_expertise" => 100},
    "interview" => %{"communication" => 27, "cultural_fit" => 9, "leadership" => 18, "domain_expertise" => 46},
    "mcq" => %{"domain_expertise" => 63, "problem_solving" => 37},
    "jam" => %{"communication" => 56, "adaptability" => 44},
    "behavioral" => %{"collaboration" => 30, "leadership" => 30, "cultural_fit" => 16, "work_ethics" => 24},
    "case_study" => %{"problem_solving" => 32, "domain_expertise" => 20, "leadership" => 48},
    # Psychometric maps Big Five → work_ethics / adaptability / cultural_fit (see
    # Contexts.Psychometric.publish_ai8/2). It does NOT emit collaboration or
    # leadership — an earlier version of this constant listed those, which is the
    # bug fixed in d975697.
    "psychometric" => %{"work_ethics" => 30, "adaptability" => 20, "cultural_fit" => 50},
    "mini_project" => %{"domain_expertise" => 56, "collaboration" => 22, "leadership" => 22}
  }

  @production_global_weights %{
    "domain_expertise" => 25, "communication" => 15, "problem_solving" => 15,
    "adaptability" => 12, "collaboration" => 10, "cultural_fit" => 5,
    "leadership" => 10, "work_ethics" => 8
  }

  @doc """
  Apply the production AI8 configuration (per-module + global weights). Idempotent
  and safe to run on deploy — sets the canonical weights, leaving any dimension
  not in the config disabled. Run with:

      mix run -e "VyaasaCampus.Contexts.AI8.seed_config()"
  """
  def seed_config do
    ensure_seeded()
    ensure_global_seeded()

    for {module, dims} <- @production_module_weights, {dimension, weight} <- dims do
      set_weight(module, dimension, weight)
    end

    for {dimension, weight} <- @production_global_weights do
      set_global_weight(dimension, weight)
    end

    :ok
  end

  # The dimensions each module's engine can actually produce, read off its publish
  # site. `:any` = the engine asks the LLM for whatever the config enables, so any
  # dimension is fillable.
  @emitted_dimensions %{
    "resume" => ["domain_expertise"],
    "interview" => :any,
    "mcq" => ["domain_expertise", "problem_solving"],
    "jam" => :any,
    "behavioral" => ["work_ethics", "collaboration", "adaptability", "leadership", "cultural_fit"],
    "case_study" => ["domain_expertise", "problem_solving", "leadership"],
    "psychometric" => ["work_ethics", "adaptability", "cultural_fit"],
    "mini_project" => ["domain_expertise", "collaboration", "leadership"]
  }

  @doc """
  Audit the **live** config for cells no engine can fill.

  Since a dimension's score is divided by the total weight configured for it, a
  weighted cell whose module never emits that dimension is dead weight that caps
  the dimension below 100 permanently. Returns `[]` when the config is sound.

      mix run -e "VyaasaCampus.Contexts.AI8.config_audit() |> IO.inspect()"
  """
  def config_audit do
    for {module, dims} <- module_dimension_weights(),
        {dimension, weight} <- dims,
        emits = Map.get(@emitted_dimensions, module, :any),
        emits != :any and dimension not in emits do
      %{module: module, dimension: dimension, weight: weight, problem: :never_emitted}
    end
  end

  @doc "Weight map for a module: `%{dimension_string => float}` (nil weights dropped)."
  def weight_map(module) do
    module = to_string(module)

    ModuleDimension
    |> where([d], d.module == ^module and d.enabled == true)
    |> Repo.all()
    |> Enum.reduce(%{}, fn d, acc ->
      case d.weight do
        nil -> acc
        w -> Map.put(acc, d.dimension, Decimal.to_float(w))
      end
    end)
  end

  # ======================================================================
  # Global dimension weights (drive the overall AI8 Index)
  # ======================================================================

  @doc "Ensure a row exists for every dimension (weight unset). Idempotent."
  def ensure_global_seeded do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for {dkey, _label} <- Dimensions.all() do
        %{
          dimension: Atom.to_string(dkey),
          position: Dimensions.position(dkey),
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(DimensionWeight, entries, on_conflict: :nothing, conflict_target: [:dimension])
    :ok
  end

  @doc "All global dimension-weight rows, in display order."
  def list_global_weights do
    DimensionWeight |> order_by([d], asc: d.position) |> Repo.all()
  end

  @doc "Global weights as `%{dimension_string => float}` (unset weights dropped)."
  def global_weights do
    DimensionWeight
    |> Repo.all()
    |> Enum.reduce(%{}, fn d, acc ->
      case d.weight do
        nil -> acc
        w -> Map.put(acc, d.dimension, Decimal.to_float(w))
      end
    end)
  end

  @doc "Sum of all configured global weights (should be 100)."
  def global_weight_total do
    global_weights() |> Map.values() |> Enum.sum() |> Float.round(1)
  end

  @doc "Set the global weight (percentage) for a dimension. nil clears it."
  def set_global_weight(dimension, weight) do
    dim = to_string(dimension)

    row =
      Repo.get_by(DimensionWeight, dimension: dim) ||
        %DimensionWeight{dimension: dim, position: Dimensions.position(dim)}

    row
    |> DimensionWeight.changeset(%{dimension: dim, weight: weight})
    |> Repo.insert_or_update()
  end

  # ======================================================================
  # Aggregation
  # ======================================================================

  @doc """
  Deterministically aggregate raw per-dimension scores into a 0–100 module score.

  - If the module has configured weights, ONLY weighted dimensions contribute
    (weighted average over them). Dimensions the admin didn't configure are
    ignored — they never leak into the score.
  - If no weights are configured at all, falls back to a plain average of every
    scored dimension (pre-config default).
  """
  def aggregate_score(module, skill_scores) when is_map(skill_scores) do
    weights = weight_map(module)

    if map_size(weights) > 0 do
      {num, den} =
        Enum.reduce(skill_scores, {0.0, 0.0}, fn {dim, score}, {n, d} ->
          case {is_number(score), Map.get(weights, to_string(dim))} do
            {true, w} when is_number(w) -> {n + score * w, d + w}
            _ -> {n, d}
          end
        end)

      if den > 0.0, do: Float.round(num / den, 1), else: 0.0
    else
      vals = skill_scores |> Map.values() |> Enum.filter(&is_number/1)
      if vals == [], do: 0.0, else: Float.round(Enum.sum(vals) / length(vals), 1)
    end
  end

  # ======================================================================
  # Results (per tenant schema — pass `prefix`)
  # ======================================================================

  @doc """
  Publish a module's AI8 evaluation for a student.

  `attrs` keys (atoms): `:student_id`, `:tenant_id`, `:module`,
  `:skill_scores` (%{dimension => 0..100}), optional `:source_type`,
  `:source_id`, `:raw_payload`, `:attempt_number`.

  `dimensions_assessed` and `module_score` are derived here. Upserts on
  (student_id, module, attempt_number).
  """
  def publish_evaluation(attrs, prefix) when is_map(attrs) and is_binary(prefix) do
    module = to_string(attrs[:module] || attrs["module"])
    skill_scores = stringify_keys(attrs[:skill_scores] || attrs["skill_scores"] || %{})

    full =
      attrs
      |> Map.merge(%{
        module: module,
        skill_scores: skill_scores,
        dimensions_assessed: Map.keys(skill_scores),
        module_score: aggregate_score(module, skill_scores),
        completed_at: attrs[:completed_at] || DateTime.utc_now() |> DateTime.truncate(:second)
      })

    result =
      %ModuleEvaluation{}
      |> ModuleEvaluation.changeset(full)
      |> Repo.insert(
        prefix: prefix,
        on_conflict: {:replace, [:skill_scores, :dimensions_assessed, :module_score, :raw_payload, :source_type, :source_id, :status, :completed_at, :updated_at]},
        conflict_target: [:student_id, :module, :attempt_number]
      )

    # Notify dashboards AFTER the row lands. Every module reaches AI8 through
    # here, so this one broadcast covers all 8 and can never race ahead of the
    # write the way per-engine broadcasts do.
    with {:ok, eval} <- result do
      notify_dashboards(prefix, eval.student_id, module)
    end

    result
  end

  defp notify_dashboards(prefix, student_id, module) do
    VyaasaCampus.DashboardEvents.broadcast_ai8_event(prefix, student_id, module)
    :ok
  rescue
    e ->
      require Logger
      Logger.warning("AI8 dashboard broadcast failed (#{module}): #{Exception.message(e)}")
      :ok
  end

  @doc "All AI8 evaluations for a student (latest attempt per module not deduped here)."
  def list_evaluations(student_id, prefix) do
    ModuleEvaluation
    |> where([e], e.student_id == ^student_id)
    |> order_by([e], asc: e.module, desc: e.attempt_number)
    |> Repo.all(prefix: prefix)
  end

  @doc "Latest evaluation per module for a student: `%{module_string => %ModuleEvaluation{}}`."
  def latest_by_module(student_id, prefix) do
    student_id
    |> list_evaluations(prefix)
    |> Enum.group_by(& &1.module)
    |> Map.new(fn {module, evals} ->
      {module, Enum.max_by(evals, & &1.attempt_number)}
    end)
  end

  @doc """
  Aggregate a student's AI8 profile across all modules.

  Returns `%{dimensions: %{dim => 0..100}, overall: float, modules: map,
  modules_total: int, modules_completed: int}`. Each dimension is a weighted
  average over every module **configured** to measure it — modules the student
  hasn't completed count as 0 — so a dimension only reaches 100 once all its
  assessments are done. `modules` is the latest `module_score` per module.
  """
  def student_profile(student_id, prefix) do
    profile_from_latest(latest_by_module(student_id, prefix), module_dimension_weights())
  end

  # Pure roll-up: `latest` is `%{module => %ModuleEvaluation{}}`. Shared by the
  # single-student path and the bulk path (`ai8_indexes/2`) so the student AI8
  # page and the admin dashboard can never drift apart.
  defp profile_from_latest(latest, weights_by_module) do
    # Each dimension is combined across the modules that measured it, weighting
    # each module by its configured Module×Dimension weight (normalised across the
    # contributing modules — i.e. "made to 100" for that dimension). Modules with
    # no configured weight fall back to an equal-weight average.
    per_dimension =
      latest
      |> Enum.flat_map(fn {module, e} ->
        (e.skill_scores || %{})
        |> Enum.map(fn {dim, score} -> {dim, {to_string(module), score}} end)
      end)
      |> Enum.group_by(fn {dim, _} -> dim end, fn {_, module_score} -> module_score end)
      |> Map.new(fn {dim, module_scores} ->
        {dim, weighted_dimension(dim, module_scores, weights_by_module)}
      end)

    module_scores =
      Map.new(latest, fn {module, e} -> {module, e.module_score} end)

    overall =
      case Map.values(per_dimension) do
        [] -> 0.0
        vals -> avg(vals)
      end

    # Every module the super admin gave a weight to is part of the AI8; the index
    # only reaches 100 when all of them are completed.
    configured_modules = weights_by_module |> Map.keys() |> MapSet.new()

    modules_completed =
      latest |> Map.keys() |> Enum.count(&MapSet.member?(configured_modules, to_string(&1)))

    %{
      dimensions: per_dimension,
      overall: overall,
      modules: module_scores,
      modules_total: MapSet.size(configured_modules),
      modules_completed: modules_completed
    }
  end

  # Weighted average of a dimension's score across **every module configured to
  # measure it**, each weighted by its configured Module×Dimension weight.
  #
  # The denominator is the full configured weight for the dimension — including
  # modules the student has NOT completed yet, which contribute 0. That is what
  # makes the AI8 a true completion-sensitive index: a dimension only reaches 100
  # when every assessment feeding it has been taken and aced. When no module has a
  # configured weight for the dimension, falls back to a plain equal-weight
  # average of whatever was scored.
  defp weighted_dimension(dim, module_scores, weights_by_module) do
    dim = to_string(dim)
    scored = Map.new(module_scores)

    {num, den} =
      Enum.reduce(weights_by_module, {0.0, 0.0}, fn {module, dims}, {n, d} ->
        case Map.get(dims, dim) do
          w when is_number(w) and w > 0.0 ->
            score = Map.get(scored, module)
            {if(is_number(score), do: n + score * w, else: n), d + w}

          _ ->
            {n, d}
        end
      end)

    if den > 0.0 do
      Float.round(num / den, 1)
    else
      scores = module_scores |> Enum.map(&elem(&1, 1)) |> Enum.filter(&is_number/1)
      avg(scores)
    end
  end

  # %{module => %{dimension => weight_float}} for every configured (weighted) cell.
  defp module_dimension_weights do
    ModuleDimension
    |> where([d], not is_nil(d.weight) and d.weight > 0)
    |> Repo.all()
    |> Enum.group_by(& &1.module)
    |> Map.new(fn {module, rows} ->
      {module, Map.new(rows, fn r -> {r.dimension, Decimal.to_float(r.weight)} end)}
    end)
  end

  @doc """
  The student's overall **AI8 Index** (assessment index / total percentage) for
  the AI8 Overview.

  Rolls each dimension up across all the student's exams (`student_profile`),
  then combines the 8 dimensions using the **global** dimension weights. The
  index is a true total percentage: every assessment the student hasn't taken
  contributes 0 to the dimensions it feeds, so the index rises as more exams are
  completed and only reaches 100 when **all** AI8 assessments are done and aced.

  Returns the full profile plus:
    * `:index`      — 0–100 AI8 Index
    * `:completion` — % of the AI8 assessments completed (nil if no global
      weights configured)

  Falls back to the equal-weight `overall` (assessed-only) when no global
  weights are configured.
  """
  def ai8_index(student_id, prefix) do
    profile = student_profile(student_id, prefix)
    index_from_profile(profile, global_weights())
  end

  @doc """
  Bulk AI8 index for many students — the list/dashboard counterpart of
  `ai8_index/2`.

  Returns `%{student_id => profile_with_index}`. Runs a fixed **three** queries
  regardless of how many students are passed (evaluations, module weights, global
  weights) instead of three per student, and shares the exact same computation as
  `ai8_index/2` so a list view can never disagree with the student's own page.
  """
  def ai8_indexes(student_ids, prefix) when is_list(student_ids) and is_binary(prefix) do
    ids = Enum.uniq(student_ids)

    if ids == [] do
      %{}
    else
      weights_by_module = module_dimension_weights()
      globals = global_weights()

      evals_by_student =
        ModuleEvaluation
        |> where([e], e.student_id in ^ids)
        |> Repo.all(prefix: prefix)
        |> Enum.group_by(& &1.student_id)

      Map.new(ids, fn id ->
        latest =
          evals_by_student
          |> Map.get(id, [])
          |> Enum.group_by(& &1.module)
          |> Map.new(fn {module, evals} -> {module, Enum.max_by(evals, & &1.attempt_number)} end)

        profile = latest |> profile_from_latest(weights_by_module) |> index_from_profile(globals)
        {id, profile}
      end)
    end
  end

  def ai8_indexes(_ids, _prefix), do: %{}

  # Pure: profile + global dimension weights → index & completion. Shared by the
  # single and bulk paths.
  defp index_from_profile(profile, weights) do
    if map_size(weights) > 0 do
      total_weight = weights |> Map.values() |> Enum.sum()

      weighted =
        Enum.reduce(weights, 0.0, fn {dim, w}, acc ->
          acc + Map.get(profile.dimensions, dim, 0.0) * w
        end)

      index = if total_weight > 0.0, do: Float.round(weighted / total_weight, 1), else: 0.0

      # Completion counts ASSESSMENTS taken, not dimensions touched — dimension
      # coverage overlaps heavily (3 assessments can touch all 8 dimensions), so
      # counting dimensions read as "100% complete" long before the AI8 was done.
      completion =
        if profile.modules_total > 0 do
          Float.round(profile.modules_completed / profile.modules_total * 100, 1)
        else
          0.0
        end

      Map.merge(profile, %{index: index, completion: completion})
    else
      Map.merge(profile, %{index: profile.overall, completion: nil})
    end
  end

  # ======================================================================
  # Helpers
  # ======================================================================

  defp avg([]), do: 0.0

  defp avg(list) do
    nums = Enum.filter(list, &is_number/1)
    if nums == [], do: 0.0, else: Float.round(Enum.sum(nums) / length(nums), 1)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
