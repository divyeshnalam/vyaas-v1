defmodule VyaasaCampus.AI8.Dimensions do
  @moduledoc """
  Canonical AI8 skill dimensions — the single source of truth.

  Every module evaluates some configurable subset of these 8 dimensions; the
  super-admin matrix (`ai8_module_dimensions`) decides which. Raw per-dimension
  scores are always on a 0–100 scale.
  """

  # {key, label, short_label} in canonical display order.
  @dimensions [
    {:domain_expertise, "Domain Expertise & Technical Skills", "Domain"},
    {:communication, "Communication & Interpersonal Skills", "Communication"},
    {:problem_solving, "Problem-Solving & Critical Thinking", "Problem-Solving"},
    {:adaptability, "Adaptability & Learning Agility", "Adaptability"},
    {:collaboration, "Collaboration & Teamwork", "Collaboration"},
    {:leadership, "Initiative & Leadership Potential", "Leadership"},
    {:work_ethics, "Work Ethics & Reliability", "Work Ethics"},
    {:cultural_fit, "Cultural Fit & Emotional Intelligence", "Cultural Fit / EQ"}
  ]

  @doc "All dimensions as `{key, label}` tuples in display order."
  def all, do: Enum.map(@dimensions, fn {k, l, _s} -> {k, l} end)

  @doc "Atom keys in display order."
  def keys, do: Enum.map(@dimensions, &elem(&1, 0))

  @doc "String keys in display order (DB / JSON form)."
  def string_keys, do: Enum.map(keys(), &Atom.to_string/1)

  @doc "Human label for a dimension key (atom or string). Falls back to the key."
  def label(key) when is_atom(key), do: label(Atom.to_string(key))

  def label(key) when is_binary(key) do
    Enum.find_value(@dimensions, key, fn {k, l, _s} ->
      if Atom.to_string(k) == key, do: l
    end)
  end

  @doc "Short/compact label for a dimension key (atom or string). Falls back to full label."
  def short_label(key) when is_atom(key), do: short_label(Atom.to_string(key))

  def short_label(key) when is_binary(key) do
    Enum.find_value(@dimensions, label(key), fn {k, _l, s} ->
      if Atom.to_string(k) == key, do: s
    end)
  end

  @doc "0-based display position for a key (atom or string); 999 if unknown."
  def position(key) do
    str = to_string(key)
    Enum.find_index(string_keys(), &(&1 == str)) || 999
  end

  @doc "Whether a key (atom or string) is a valid AI8 dimension."
  def valid?(key), do: to_string(key) in string_keys()
end
