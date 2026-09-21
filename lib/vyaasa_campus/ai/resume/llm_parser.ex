defmodule VyaasaCampus.AI.Resume.LlmParser do
  @moduledoc """
  Single Groq call: validate that the document is a resume, parse every
  section into structured JSON, and collect linguistic-sanity hints.

  Mirrors `llm_validate_and_parse` from the Python pipeline. Uses the existing
  `GroqClient` (rate-limited, retried, pooled) so this benefits from the same
  500-user infrastructure as other AI engines.
  """

  alias VyaasaCampus.AI.GroqClient
  alias VyaasaCampus.AI.Resume.Extractor

  require Logger

  @model "openai/gpt-oss-120b"
  @max_text_chars 6000

  @system_prompt "You are an expert resume analyst. You MUST output ONLY valid JSON — no markdown fences, no prose before or after."

  @doc """
  Returns `{:ok, %{is_resume, rejection_reason, parsed, sanity_hints}}` or
  `{:error, reason}`.
  """
  def validate_and_parse(raw_text) when is_binary(raw_text) do
    user_prompt = build_prompt(raw_text)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_prompt}
    ]

    case GroqClient.chat(messages,
           model: @model,
           temperature: 0.0,
           max_tokens: 4096,
           response_format: %{"type" => "json_object"},
           reasoning_effort: "low",
           timeout: 60_000
         ) do
      {:ok, %{"content" => content}} ->
        decode_response(content)

      {:error, reason} = err ->
        Logger.error("RESUME_PARSER | Groq call failed | reason=#{inspect(reason)}")
        err
    end
  end

  defp decode_response(content) do
    case content |> GroqClient.strip_reasoning() |> GroqClient.extract_json() do
      {:ok, result} ->
        is_resume = !!result["is_resume"]
        parsed = if is_resume, do: normalise_parsed(result["parsed"] || %{}), else: nil

        {:ok,
         %{
           is_resume: is_resume,
           rejection_reason: result["rejection_reason"] || "",
           inferred_domain_family: result["inferred_domain_family"] || "default",
           parsed: parsed,
           sanity_hints: result["sanity_hints"] || %{}
         }}

      {:error, reason} ->
        {:error, "JSON decode failed: #{reason}"}
    end
  end

  # Normalise variant skill key the LLM sometimes emits ("Non-Technical" vs "Non_Technical").
  defp normalise_parsed(parsed) when is_map(parsed) do
    skills = parsed["Skills"] || %{}

    skills =
      case Map.pop(skills, "Non-Technical") do
        {nil, s} -> s
        {value, s} -> Map.put_new(s, "Non_Technical", value)
      end

    Map.put(parsed, "Skills", skills)
  end

  defp normalise_parsed(_), do: %{}

  defp build_prompt(raw_text) do
    cleaned = raw_text |> Extractor.clean_text() |> String.slice(0, @max_text_chars)

    """
    Analyze the following text and return a single JSON object with this exact schema:

    {
      "is_resume": true,
      "rejection_reason": "",
      "inferred_domain_family": "tech",
      "parsed": {
        "Full_Name": "",
        "Contact_Number": "",
        "Email_Address": "",
        "Location": "",
        "LinkedIn_Profile": "",
        "GitHub_Profile": "",
        "Professional_Summary": [],
        "Skills": {
          "Technical": [],
          "Non_Technical": []
        },
        "Education": [
          {
            "Degree": "",
            "Institution": "",
            "Years": "",
            "Specialization": "",
            "CGPA_Percentage": ""
          }
        ],
        "Work_Experience": [
          {
            "Company_Name": "",
            "Job_Title": "",
            "start_date": "",
            "end_date": "",
            "Responsibilities": []
          }
        ],
        "Projects": [
          {
            "Project_Name": "",
            "Technologies_Used": [],
            "Description": [],
            "Github_Link": ""
          }
        ],
        "Certifications": [],
        "Languages_Spoken": [],
        "Achievements": [],
        "Volunteer_Or_Extra": []
      },
      "sanity_hints": {
        "typos": [],
        "weak_verbs": [],
        "repetitive_verbs": [],
        "informal_phrases": [],
        "grammar_issues": []
      }
    }

    RULES:
    - Set "is_resume" to false if the text is NOT a resume (e.g. article, code file, random text).
      In that case populate "rejection_reason" and set "parsed" to null.
    - For Skills, include ALL mentioned skills — theoretical, domain-specific, soft skills.
      Separate into Technical (tools, languages, frameworks, methodologies) and Non_Technical (soft/interpersonal).
    - For each Project, set "Github_Link" to that project's GitHub/GitLab/repo URL if one is
      present (next to the project, in its description, or as a hyperlink). Use "" if none.
    - For sanity_hints:
      * typos: real spelling errors ONLY — not jargon, acronyms, or hyphenated tech terms.
      * weak_verbs: genuinely passive verbs (helped, assisted, tried, was responsible for).
      * repetitive_verbs: strong verbs used more than 3 times (e.g., "Developed — used 5 times").
      * informal_phrases: colloquial language (basically, stuff, things, etc.).
      * grammar_issues: clearly broken grammar (missing articles, subject-verb disagreement).
    - Set "inferred_domain_family" to the best-fit domain family for this candidate:
      "tech" (CS/IT/engineering/software), "healthcare" (MBBS/BDS/nursing/pharmacy/physiotherapy),
      "finance" (CA/CFA/MBA-finance/accounting/banking), "law" (LLB/LLM/legal),
      "education" (B.Ed/teaching/academia), "design" (BDes/MFA/architecture/UX),
      "trades" (ITI/diploma/polytechnic/vocational), or "default" if unclear.
    - Use "" or [] for missing fields. NEVER omit a key.

    TEXT TO ANALYZE:
    ---
    #{cleaned}
    ---
    """
  end
end
