defmodule VyaasaCampus.Mail.EmailService do
  @moduledoc """
  Unified email service for VyaasaCampus application.
  Handles all email types with automatic tenant context detection.
  """

  alias Swoosh.Email
  alias VyaasaCampus.Mail.Templates
  alias VyaasaCampus.Mailer

  @doc """
  Send email with unified interface that automatically detects context.
  """
  def send_email(email_type, user, opts \\ []) do
    template = Templates.get_template(email_type, user, opts)

    build_email(template, user, opts)
    |> Mailer.deliver()
  end

  @doc """
  Generate password reset URL based on user context.
  Automatically detects if it's a platform admin or tenant user/student.
  """
  def generate_reset_url(user, tenant_alias \\ nil) do
    base_url = Application.get_env(:vyaasa_campus, :frontend_url, "http://localhost:4000")
    token = user.password_reset_token

    case tenant_alias do
      nil -> "#{base_url}/admin/reset-password/#{token}"
      alias -> "#{base_url}/auth/tenant/#{alias}/reset-password/#{token}"
    end
  end

  @doc """
  Generate password reset URL when only the raw token is available (hashed stored in DB).
  """
  def generate_reset_url_with_token(raw_token, tenant_alias \\ nil) do
    base_url = Application.get_env(:vyaasa_campus, :frontend_url, "http://localhost:4000")

    case tenant_alias do
      nil -> "#{base_url}/admin/reset-password/#{raw_token}"
      alias -> "#{base_url}/auth/tenant/#{alias}/reset-password/#{raw_token}"
    end
  end

  @doc """
  Send password reset email with automatic context detection.
  """
  def send_password_reset_email(user, tenant_alias \\ nil) do
    reset_url = generate_reset_url(user, tenant_alias)

    send_email(:password_reset, user, %{
      reset_url: reset_url,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send welcome email with temporary password.
  """
  def send_welcome_email(user, temp_password, tenant_alias \\ nil) do
    send_email(:welcome, user, %{
      temp_password: temp_password,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send welcome email with role assignment details and temporary password.
  """
  def send_welcome_email_with_role(user, role, assigner, tenant_alias \\ nil) do
    send_email(:welcome_with_role, user, %{
      role: role,
      assigner: assigner,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send tenant creation notification email.
  """
  def send_tenant_creation_email(tenant) do
    send_email(:tenant_creation, tenant, %{})
  end

  @doc """
  Send profile completion email with secure link.
  """
  def send_profile_completion_email(student, profile_url, tenant_alias \\ nil) do
    send_email(:profile_completion, student, %{
      profile_url: profile_url,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send profile approved email with temporary password.
  """
  def send_profile_approved_email(student, temp_password, tenant_alias \\ nil) do
    send_email(:profile_approved, student, %{
      temp_password: temp_password,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send profile edit request email with feedback and new completion link.
  """
  def send_profile_edit_request_email(
        student,
        profile_url,
        admin_notes,
        edit_request_notes,
        tenant_alias \\ nil
      ) do
    send_email(:profile_edit_request, student, %{
      profile_url: profile_url,
      admin_notes: admin_notes,
      edit_request_notes: edit_request_notes,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send profile edit approved email with profile completion token.
  """
  def send_profile_edit_approved_email(student, admin_notes, tenant_alias \\ nil) do
    send_email(:profile_edit_approved, student, %{
      admin_notes: admin_notes,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send profile edit rejected email.
  """
  def send_profile_edit_rejected_email(student, admin_notes, rejection_notes, tenant_alias \\ nil) do
    send_email(:profile_edit_rejected, student, %{
      admin_notes: admin_notes,
      rejection_notes: rejection_notes,
      tenant_alias: tenant_alias
    })
  end

  @doc """
  Send an assessment report PDF to a student as an email attachment.

  `opts` expects the same keys as `Templates.assessment_report_template/2`
  (`:report_title`, `:assessment_title`, `:tenant_alias`) plus a `:filename`
  for the attachment (defaults to `Vyaasa-Report.pdf`).
  """
  def send_report_email(student, pdf_binary, opts) when is_binary(pdf_binary) do
    template = Templates.assessment_report_template(student, opts)

    filename = Map.get(opts, :filename, "Vyaasa-Report.pdf")

    attachment =
      Swoosh.Attachment.new({:data, pdf_binary},
        filename: filename,
        content_type: "application/pdf"
      )

    require Logger

    Logger.info(
      "REPORT_MAIL | delivering | to=#{student.email} filename=#{filename} " <>
        "pdf_bytes=#{byte_size(pdf_binary)} adapter=#{inspect(Application.get_env(:vyaasa_campus, VyaasaCampus.Contexts.Mailer)[:adapter])}"
    )

    result =
      build_email(template, student, opts)
      |> Email.attachment(attachment)
      |> Mailer.deliver()

    case result do
      {:ok, meta} -> Logger.info("REPORT_MAIL | delivered | to=#{student.email} meta=#{inspect(meta)}")
      {:error, reason} -> Logger.error("REPORT_MAIL | delivery FAILED | to=#{student.email} reason=#{inspect(reason)}")
    end

    result
  end

  # Private functions

  defp build_email(template, user, opts) do
    from_email = get_from_email(user, opts)
    from_name = get_from_name(user, opts)

    %Email{}
    |> Email.to(user.email)
    |> Email.from({from_name, from_email})
    |> Email.subject(template.subject)
    |> Email.html_body(template.html_body)
    |> Email.text_body(template.text_body)
  end

  defp get_from_email(_user, _) do
    Application.get_env(:vyaasa_campus, :smtp_from_email, "noreply@vyaasa.com")
  end

  defp get_from_name(_user, %{tenant_alias: nil}), do: "VyaasaCampus"
  defp get_from_name(_user, %{tenant_alias: tenant_alias}), do: tenant_alias
  defp get_from_name(_user, _), do: "VyaasaCampus"
end
