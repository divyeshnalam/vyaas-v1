defmodule VyaasaCampus.AI8.Modules do
  @moduledoc """
  The 8 AI8 evaluation modules — registry of keys, display names, and the
  default set of skill dimensions each one evaluates.

  Default dimensions are only used to seed the super-admin matrix
  (`ai8_module_dimensions`); after seeding, the admin's choices win.
  """

  # {key, display_name} in canonical order.
  @modules [
    {:resume, "AI Resume Scoring"},
    {:interview, "AI-led Introduction Session"},
    {:mcq, "Objective Evaluation (MCQs)"},
    {:jam, "JAM Session"},
    {:behavioral, "Situational & Behavioral Queries"},
    {:case_study, "AI-Generated Case Study"},
    {:psychometric, "Psychometric Assessment"},
    {:mini_project, "Domain Mini Project"}
  ]

  # Default dimension coverage per module — derived from the current engines
  # (audit) and the V1 interview sample. Super admin can override any of these.
  @default_dimensions %{
    resume: [:domain_expertise],
    interview: [:domain_expertise, :communication, :leadership, :cultural_fit],
    mcq: [:domain_expertise, :problem_solving],
    jam: [:communication],
    behavioral: [:work_ethics, :collaboration, :adaptability, :leadership, :communication],
    case_study: [:domain_expertise, :problem_solving],
    psychometric: [:cultural_fit, :work_ethics, :adaptability, :collaboration],
    mini_project: [:domain_expertise, :problem_solving, :work_ethics]
  }

  @doc "All modules as `{key, name}` tuples in display order."
  def all, do: @modules

  @doc "Atom keys in display order."
  def keys, do: Enum.map(@modules, &elem(&1, 0))

  @doc "String keys in display order."
  def string_keys, do: Enum.map(keys(), &Atom.to_string/1)

  @doc "Display name for a module key (atom or string). Falls back to the key."
  def name(key) when is_atom(key), do: name(Atom.to_string(key))

  def name(key) when is_binary(key) do
    Enum.find_value(@modules, key, fn {k, n} ->
      if Atom.to_string(k) == key, do: n
    end)
  end

  @doc "Whether a key (atom or string) is a valid AI8 module."
  def valid?(key), do: to_string(key) in string_keys()

  @doc "Default-enabled dimension keys (atoms) for a module key (atom or string)."
  def default_dimensions(key) do
    atom = if is_atom(key), do: key, else: safe_atom(key)
    Map.get(@default_dimensions, atom, [])
  end

  defp safe_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end
end
