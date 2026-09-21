defmodule VyaasaCampus.AI.Interview.ContentCheck do
  @moduledoc """
  Detects vulgar, abusive, or unethical content in candidate answers. Whole-word
  regex matching avoids false positives on substrings (e.g. "assessment" must not
  match "ass"). Port of the reference `core/content_check.py`.
  """

  @profanity [
    ~S"\bf+u+c+k+\w*",
    ~S"\bsh[i1]+t\w*",
    ~S"\ba+s+h+o+l+e+\b",
    ~S"\bb[i1]+tc+h\w*",
    ~S"\bbastard\b",
    ~S"\bc+u+n+t\b",
    ~S"\bp+u+s+s+y\b",
    ~S"\bwh[o0]+r+e\b",
    ~S"\bsl+u+t\b",
    ~S"\bn+[i1]+g+[ae]+r\b",
    ~S"\bn+[i1]+g+[ae]\b",
    ~S"\bf+[a@]+g+[o0]+t\b",
    ~S"\br+[e3]+t+[a@]+r+d\b",
    ~S"\bd+[i1]+c+k\b",
    ~S"\bc+[o0]+c+k\b"
  ]

  @threats [
    ~S"\bi.?ll kill",
    ~S"\bkill\s+you\b",
    ~S"\bgonna\s+kill\b",
    ~S"\bwant\s+to\s+kill\b",
    ~S"\bgo\s+to\s+hell\b",
    ~S"\bgo\s+f+u+c+k\b",
    ~S"\bi\s+hate\s+you\b",
    ~S"\bkill\s+(my)?self\b"
  ]

  @sexual [
    ~S"\bporn(ography)?\b",
    ~S"\bnude(s)?\b",
    ~S"\bnaked\b",
    ~S"\bmasturbat\w+",
    ~S"\bsex\s+(with|me|you)\b"
  ]

  @pattern (@profanity ++ @threats ++ @sexual) |> Enum.join("|") |> Regex.compile!("i")

  @doc """
  Returns `{flagged?, reason}` — `reason` is "" when not flagged.
  """
  def check(text) when is_binary(text) do
    case Regex.run(@pattern, text) do
      [match | _] -> {true, "Inappropriate content detected: '#{match}'"}
      nil -> {false, ""}
    end
  end

  def check(_), do: {false, ""}
end
