defmodule Mix.Tasks.Vyaasa.EmailCheck do
  @moduledoc """
  Sends every VyaasaCampus email type to a target address and reports the
  real delivery result for each, so you can confirm the mailer works
  end-to-end (SMTP credentials, from address, template rendering).

  In dev with `SMTP_USERNAME` set in `.env`, mail is sent over real SMTP.
  Without it, the Local adapter captures mail at `/dev/mailbox` instead of
  actually delivering — so `{:ok, ...}` there means "queued locally", not
  "landed in an inbox".

  Usage:
      mix vyaasa.email_check you@example.com
      mix vyaasa.email_check you@example.com --tenant BITE

  The `--tenant` alias is only used as the display "from name" / context in
  the templates; no database records are read or written.
  """

  use Mix.Task
  require Logger

  alias VyaasaCampus.Mail.EmailService

  @shortdoc "Send each email type to an address and print delivery results"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} = OptionParser.parse(args, switches: [tenant: :string])
    tenant_alias = Keyword.get(opts, :tenant)

    case positional do
      [to | _] ->
        adapter =
          Application.get_env(:vyaasa_campus, VyaasaCampus.Mailer)[:adapter]

        from = Application.get_env(:vyaasa_campus, :smtp_from_email)

        Mix.shell().info("""
        VyaasaCampus email check
          to:      #{to}
          from:    #{from}
          adapter: #{inspect(adapter)}
          tenant:  #{tenant_alias || "(none / platform)"}
        """)

        student = fake_student(to)
        user = fake_user(to)
        temp = "Temp-#{:rand.uniform(9999)}"

        [
          {"welcome (user + temp password)",
           fn -> EmailService.send_welcome_email(user, temp, tenant_alias) end},
          {"profile_approved (student + temp password)",
           fn -> EmailService.send_profile_approved_email(student, temp, tenant_alias) end},
          {"password_reset (student)",
           fn -> EmailService.send_password_reset_email(student, tenant_alias) end},
          {"profile_completion (student)",
           fn ->
             EmailService.send_profile_completion_email(
               student,
               "https://example.com/profile/token/ats",
               tenant_alias
             )
           end}
        ]
        |> Enum.each(fn {label, fun} -> report(label, fun) end)

      _ ->
        Mix.raise("Usage: mix vyaasa.email_check <to-address> [--tenant ALIAS]")
    end
  end

  defp report(label, fun) do
    case fun.() do
      {:ok, meta} ->
        Mix.shell().info("  ✅ #{label} — delivered (#{inspect(meta)})")

      {:error, reason} ->
        Mix.shell().error("  ❌ #{label} — FAILED: #{inspect(reason)}")
    end
  rescue
    e ->
      Mix.shell().error("  💥 #{label} — RAISED: #{Exception.message(e)}")
  end

  # Plain maps (not DB structs) are enough for the templates: they read fields
  # via `map.field` and detect the user type with `Map.has_key?/2`. Presence of
  # `:registration_id` marks a Student; `:role` marks a tenant User.
  defp fake_student(email) do
    %{
      email: email,
      first_name: "Test",
      last_name: "Student",
      registration_id: "REG-TEST-001",
      password_reset_token: "test-reset-token",
      temp_password: nil
    }
  end

  defp fake_user(email) do
    %{
      email: email,
      first_name: "Test",
      last_name: "User",
      role: "faculty",
      password_reset_token: "test-reset-token",
      temp_password: "Temp-1234"
    }
  end
end
