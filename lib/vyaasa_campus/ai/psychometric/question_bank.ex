defmodule VyaasaCampus.AI.Psychometric.QuestionBank do
  @moduledoc """
  Predefined psychometric question bank (600 items: 5 traits × 4 themes ×
  30 items, balanced positive/negative across base/scenario/stakes/edge depths).

  Base questions are served directly from this bank — no LLM generation. Each
  item: `id, trait, theme, depth, keyed, text, technique`. Sourced from the
  dev-psychometric `question_bank.py`.
  """

  @external_resource "priv/data/psychometric_question_bank.json"
  @bank "priv/data/psychometric_question_bank.json" |> File.read!() |> Jason.decode!()

  # Follow-up depth tiers, deepest last (reference DEPTH_ORDER). A follow-up at
  # consecutive index N pulls depth DEPTH_ORDER[N].
  @depth_order ["base", "scenario", "stakes", "edge"]
  def depth_order, do: @depth_order

  # theme list per trait, in first-seen order (reference THEMES_BY_TRAIT).
  @themes_by_trait @bank
                   |> Enum.reduce(%{}, fn q, acc ->
                     Map.update(acc, q["trait"], [q["theme"]], fn ts ->
                       if q["theme"] in ts, do: ts, else: ts ++ [q["theme"]]
                     end)
                   end)

  @doc "All themes registered for a given trait (first-seen order)."
  def themes_for_trait(trait), do: Map.get(@themes_by_trait, trait, [])

  @doc "All questions."
  def all, do: @bank

  @doc "Total item count."
  def size, do: length(@bank)

  @doc "Fetch a question by its stable id (or nil)."
  def get(id), do: Enum.find(@bank, &(&1["id"] == id))

  @doc """
  Questions matching the filters. `keyed` ("positive"/"negative") and `theme`
  are optional; `exclude_ids` (a MapSet or list) drops already-used items.
  """
  def candidates(trait, depth, opts \\ []) do
    keyed = Keyword.get(opts, :keyed)
    theme = Keyword.get(opts, :theme)
    exclude = opts |> Keyword.get(:exclude_ids, []) |> MapSet.new()

    Enum.filter(@bank, fn q ->
      q["trait"] == trait and q["depth"] == depth and
        (is_nil(keyed) or q["keyed"] == keyed) and
        (is_nil(theme) or q["theme"] == theme) and
        not MapSet.member?(exclude, q["id"])
    end)
  end

  @doc """
  Pick one base-depth question for the trait + keying, avoiding used ids.
  Falls back to ignoring keying, then to any base question. Returns the item
  map or nil if the bank has nothing for the trait.
  """
  def pick_base(trait, keyed, exclude_ids) do
    pick(trait, "base", keyed, exclude_ids) ||
      pick(trait, "base", nil, exclude_ids) ||
      pick(trait, "base", nil, [])
  end

  defp pick(trait, depth, keyed, exclude_ids) do
    case candidates(trait, depth, keyed: keyed, exclude_ids: exclude_ids) do
      [] -> nil
      list -> Enum.random(list)
    end
  end
end
