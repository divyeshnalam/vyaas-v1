defmodule VyaasaCampus.Mail.Templates do
  @moduledoc """
  Unified email templates for VyaasaCampus application.
  Provides templates for all email types with automatic context detection.
  """

  # Frontend URL used in every email link. Reads `:frontend_url` from
  # config (set via `FRONTEND_URL` env var in runtime.exs). Falls back
  # to localhost for tests / first-run dev where the env isn't set.
  defp frontend_url do
    Application.get_env(:vyaasa_campus, :frontend_url, "http://localhost:4000")
  end

  @doc """
  Get email template based on type and user context.
  """
  def get_template(email_type, user, opts \\ []) do
    template_functions = %{
      :password_reset => &password_reset_template/2,
      :welcome => &welcome_template/2,
      :welcome_with_role => &welcome_with_role_template/2,
      :tenant_creation => &tenant_creation_template/2,
      :profile_completion => &profile_completion_template/2,
      :profile_approved => &profile_approved_template/2,
      :profile_edit_request => &profile_edit_request_template/2,
      :profile_edit_approved => &profile_edit_approved_template/2,
      :profile_edit_rejected => &profile_edit_rejected_template/2,
      :assessment_report => &assessment_report_template/2
    }

    case Map.get(template_functions, email_type) do
      nil -> {:error, :unknown_template_type}
      template_fn -> template_fn.(user, opts)
    end
  end

  @spec password_reset_template(any(), %{
          :reset_url => any(),
          :tenant_alias => any(),
          optional(any()) => any()
        }) :: %{
          html_body: <<_::64, _::_*8>>,
          subject: <<_::64, _::_*8>>,
          text_body: <<_::64, _::_*8>>
        }
  @doc """
  Generate password reset email template.
  """
  def password_reset_template(user, %{reset_url: reset_url, tenant_alias: tenant_alias}) do
    context = get_context(user, tenant_alias)

    %{
      subject: "Password Reset Request - #{context.name}",
      html_body: password_reset_html(user, reset_url, context),
      text_body: password_reset_text(user, reset_url, context)
    }
  end

  @doc """
  Generate welcome email template with temporary password.
  """
  def welcome_template(user, %{temp_password: temp_password, tenant_alias: tenant_alias}) do
    context = get_context(user, tenant_alias)

    %{
      subject: "Welcome to #{context.name} - Your Account is Ready",
      html_body: welcome_html(user, temp_password, context),
      text_body: welcome_text(user, temp_password, context)
    }
  end

  @doc """
  Generate welcome email template with role assignment details and temporary password.
  """
  def welcome_with_role_template(user, %{
        role: role,
        assigner: assigner,
        tenant_alias: tenant_alias
      }) do
    context = get_context(user, tenant_alias)

    %{
      subject: "Welcome to #{context.name} - Your Account is Ready with Role Assignment",
      html_body: welcome_with_role_html(user, role, assigner, context),
      text_body: welcome_with_role_text(user, role, assigner, context)
    }
  end

  @doc """
  Generate tenant creation notification email template.
  """
  def tenant_creation_template(tenant, _opts) do
    %{
      subject: "Welcome to VyaasaCampus - Your Institution Account is Ready",
      html_body: tenant_creation_html(tenant),
      text_body: tenant_creation_text(tenant)
    }
  end

  @doc """
  Generate profile completion email template.
  """
  def profile_completion_template(student, %{profile_url: profile_url, tenant_alias: tenant_alias}) do
    context = get_context(student, tenant_alias)

    %{
      subject: "Complete Your Profile - #{context.name}",
      html_body: profile_completion_html(student, profile_url, context),
      text_body: profile_completion_text(student, profile_url, context)
    }
  end

  @doc """
  Generate profile approved email template with temporary password.
  """
  def profile_approved_template(student, %{
        temp_password: temp_password,
        tenant_alias: tenant_alias
      }) do
    context = get_context(student, tenant_alias)

    %{
      subject: "Profile Approved - Welcome to #{context.name}",
      html_body: profile_approved_html(student, temp_password, context),
      text_body: profile_approved_text(student, temp_password, context)
    }
  end

  @doc """
  Generate profile edit request email template with feedback.
  """
  def profile_edit_request_template(student, %{
        profile_url: profile_url,
        admin_notes: admin_notes,
        edit_request_notes: edit_request_notes,
        tenant_alias: tenant_alias
      }) do
    context = get_context(student, tenant_alias)

    %{
      subject: "Profile Review - Updates Required - #{context.name}",
      html_body: profile_edit_request_html(student, profile_url, admin_notes, edit_request_notes, context),
      text_body: profile_edit_request_text(student, profile_url, admin_notes, edit_request_notes, context)
    }
  end

  @doc """
  Generate profile edit approved email template with profile completion token.
  """
  def profile_edit_approved_template(student, %{
        admin_notes: admin_notes,
        tenant_alias: tenant_alias
      }) do
    context = get_context(student, tenant_alias)

    %{
      subject: "Profile Edit Request Approved - #{context.name}",
      html_body: profile_edit_approved_html(student, admin_notes, context),
      text_body: profile_edit_approved_text(student, admin_notes, context)
    }
  end

  @doc """
  Generate profile edit rejected email template.
  """
  def profile_edit_rejected_template(student, %{
        admin_notes: admin_notes,
        rejection_notes: rejection_notes,
        tenant_alias: tenant_alias
      }) do
    context = get_context(student, tenant_alias)

    %{
      subject: "Profile Edit Request Rejected - #{context.name}",
      html_body: profile_edit_rejected_html(student, admin_notes, rejection_notes, context),
      text_body: profile_edit_rejected_text(student, admin_notes, rejection_notes, context)
    }
  end

  # Private functions

  defp get_context(_user, nil) do
    %{
      name: "VyaasaCampus Platform",
      is_admin: true,
      user_type: "Platform Admin"
    }
  end

  defp get_context(user, tenant_alias) do
    %{
      name: tenant_alias,
      is_admin: false,
      user_type: get_user_type(user)
    }
  end

  defp get_user_type(user) do
    cond do
      Map.has_key?(user, :registration_id) -> "Student"
      Map.has_key?(user, :role) -> "User"
      true -> "User"
    end
  end

  # ------------------- HTML Templates -------------------
  # ------------------- Password Reset Template -------------------

  defp password_reset_html(user, reset_url, context) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Password Reset - #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Password Reset Request</h1>
        </div>
        <div class="content">
          <h2>Hello #{user.first_name}!</h2>
          <p>We received a request to reset your password for your #{context.name} account.</p>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{reset_url}" class="button">Reset My Password</a>
          </p>

          <div class="warning">
            <strong>Security Notice:</strong>
            <ul>
              <li>This link will expire in 24 hours</li>
              <li>If you didn't request this password reset, please ignore this email</li>
              <li>Never share this link with anyone</li>
            </ul>
          </div>

          <p>If the button above doesn't work, you can copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6b7280;">#{reset_url}</p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  # ------------------- Welcome Template -------------------
  defp welcome_html(user, temp_password, context) do
    user_info =
      if Map.has_key?(user, :registration_id) do
        "<strong>Registration ID:</strong> #{user.registration_id}<br>"
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Welcome to #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .password-box { background: #e5e7eb; padding: 15px; border-radius: 6px; margin: 20px 0; text-align: center; font-family: monospace; font-size: 18px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Welcome to #{context.name}</h1>
        </div>
        <div class="content">
          <h2>Hello #{user.first_name}!</h2>
          <p>Your #{String.downcase(context.user_type)} account has been created successfully. Here are your login credentials:</p>

          <div class="password-box">
            <strong>Email:</strong> #{user.email}<br>
            #{user_info}
            <strong>Temporary Password:</strong> #{temp_password}
          </div>

          <div class="warning">
            <strong>Important:</strong> Please change your password immediately after your first login for security.
          </div>

          <h3>Next Steps:</h3>
          <ol>
            <li>Log in using the credentials above</li>
            <li>Change your password to something secure</li>
            <li>Complete your profile information</li>
            <li>Start using the platform</li>
          </ol>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{frontend_url()}" class="button" style="color: #FFFFFF;">Log In Now</a>
          </p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_with_role_html(user, role, assigner, context) do
    user_info =
      if Map.has_key?(user, :registration_id) do
        "<strong>Registration ID:</strong> #{user.registration_id}<br>"
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Welcome to #{context.name} - Role Assigned</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .password-box { background: #e5e7eb; padding: 15px; border-radius: 6px; margin: 20px 0; text-align: center; font-family: monospace; font-size: 18px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
        .role-info { background: #dbeafe; border: 1px solid #3b82f6; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Welcome to #{context.name}</h1>
        </div>
        <div class="content">
          <h2>Hello #{user.first_name}!</h2>
          <p>Your #{String.downcase(context.user_type)} account has been created and a role has been assigned to you. Here are your login credentials:</p>

                     <div class="password-box">
             <strong>Email:</strong> #{user.email}<br>
             #{user_info}
             #{if user.temp_password do
      "<strong>Temporary Password:</strong> #{user.temp_password}<br>"
    else
      "<strong>Note:</strong> Please use your existing password to log in<br>"
    end}
           </div>

          <div class="role-info">
            <h3>Role Assignment Details:</h3>
            <p><strong>Assigned Role:</strong> #{role.name}</p>
            <p><strong>Role Description:</strong> #{role.description || "No description available"}</p>
            <p><strong>Assigned By:</strong> #{assigner.name} (#{assigner.email})</p>
            <p><strong>Assigned At:</strong> #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")}</p>
          </div>

          #{if user.temp_password do
      "<div class=\"warning\">
              <strong>Important:</strong> Please change your password immediately after your first login for security.
            </div>"
    else
      "<div class=\"warning\">
              <strong>Note:</strong> You can continue using your existing password to access the platform with your new role.
            </div>"
    end}

          <h3>Next Steps:</h3>
          <ol>
            <li>Log in using the credentials above</li>
            <li>Change your password to something secure</li>
            <li>Complete your profile information</li>
            <li>Start using the platform with your assigned role</li>
          </ol>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{frontend_url()}" class="button" style="color: #FFFFFF;">Log In Now</a>
          </p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_with_role_text(user, role, assigner, context) do
    user_info =
      if Map.has_key?(user, :registration_id) do
        "Registration ID: #{user.registration_id}\n"
      else
        ""
      end

    """
    Welcome to #{context.name} - Role Assigned!

    Hello #{user.first_name}!

    Your #{String.downcase(context.user_type)} account has been created and a role has been assigned to you. Here are your login credentials:

         Email: #{user.email}
     #{user_info}#{if user.temp_password do
      "Temporary Password: #{user.temp_password}"
    else
      "Note: Please use your existing password to log in"
    end}

         ROLE ASSIGNMENT DETAILS:
     - Assigned Role: #{role.name}
     - Role Description: #{role.description || "No description available"}
     - Assigned By: #{assigner.name} (#{assigner.email})
     - Assigned At: #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")}

     #{if user.temp_password do
      "IMPORTANT: Please change your password immediately after your first login for security."
    else
      "NOTE: You can continue using your existing password to access the platform with your new role."
    end}

    Next Steps:
    1. Log in using the credentials above
    2. Change your password to something secure
    3. Complete your profile information
    4. Start using the platform with your assigned role

    Log in at: #{frontend_url()}

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp tenant_creation_html(tenant) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Welcome to VyaasaCampus</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Welcome to VyaasaCampus</h1>
        </div>
        <div class="content">
          <h2>Hello!</h2>
          <p>Your institution <strong>#{tenant.full_name}</strong> has been successfully created on VyaasaCampus.</p>

          <h3>Institution Details:</h3>
          <ul>
            <li><strong>Name:</strong> #{tenant.full_name}</li>
            <li><strong>Short Name:</strong> #{tenant.short_name}</li>
            <li><strong>Alias:</strong> #{tenant.alias}</li>
            <li><strong>Type:</strong> #{String.capitalize(tenant.affiliation_type)}</li>
          </ul>

          <p>You can now:</p>
          <ul>
            <li>Log in to your institution dashboard</li>
            <li>Create user accounts for your staff</li>
            <li>Add student accounts</li>
            <li>Configure assessments and courses</li>
          </ul>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{frontend_url()}" class="button">Access Your Dashboard</a>
          </p>

          <p>If you have any questions or need assistance, please don't hesitate to contact our support team.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from VyaasaCampus. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  # Text Templates

  defp password_reset_text(user, reset_url, context) do
    """
    Password Reset Request - #{context.name}

    Hello #{user.first_name}!

    We received a request to reset your password for your #{context.name} account.

    To reset your password, click the following link:
    #{reset_url}

    Security Notice:
    - This link will expire in 24 hours
    - If you didn't request this password reset, please ignore this email
    - Never share this link with anyone

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp welcome_text(user, temp_password, context) do
    user_info =
      if Map.has_key?(user, :registration_id) do
        "Registration ID: #{user.registration_id}\n"
      else
        ""
      end

    """
    Welcome to #{context.name}!

    Hello #{user.first_name}!

    Your #{String.downcase(context.user_type)} account has been created successfully. Here are your login credentials:

    Email: #{user.email}
    #{user_info}Temporary Password: #{temp_password}

    IMPORTANT: Please change your password immediately after your first login for security.

    Next Steps:
    1. Log in using the credentials above
    2. Change your password to something secure
    3. Complete your profile information
    4. Start using the platform

    Log in at: #{frontend_url()}

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp tenant_creation_text(tenant) do
    """
    Welcome to VyaasaCampus!

    Your institution #{tenant.full_name} has been successfully created on VyaasaCampus.

    Institution Details:
    - Name: #{tenant.full_name}
    - Short Name: #{tenant.short_name}
    - Alias: #{tenant.alias}
    - Type: #{String.capitalize(tenant.affiliation_type)}

    You can now:
    - Log in to your institution dashboard
    - Create user accounts for your staff
    - Add student accounts
    - Configure assessments and courses

    Access your dashboard at: #{frontend_url()}

    If you have any questions or need assistance, please don't hesitate to contact our support team.

    This is an automated message from VyaasaCampus. Please do not reply to this email.
    """
  end

  # ------------------- Profile Completion Templates -------------------

  defp profile_completion_html(student, profile_url, context) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Complete Your Profile - #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Complete Your Profile</h1>
        </div>
        <div class="content">
          <h2>Hello #{student.first_name}!</h2>
          <p>Your student account has been created at #{context.name}. To complete your registration and access the platform, please upload your resume for automated analysis.</p>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{profile_url}" class="button" style="background: #f97316; color: #FFFFFF;">Upload Resume & Complete Profile</a>
          </p>

          <div class="warning">
            <strong>Important:</strong>
            <ul>
              <li>This link will expire in 48 hours</li>
              <li>You'll need to upload your resume (PDF/DOCX format)</li>
              <li>Select your preferred job role for ATS analysis</li>
              <li>After upload, your resume will be automatically analyzed</li>
              <li>High-quality resumes may be auto-approved</li>
            </ul>
          </div>

          <h3>What happens next:</h3>
          <ul>
            <li><strong>Resume Upload:</strong> Upload your resume in PDF or DOCX format (max 5MB)</li>
            <li><strong>Role Selection:</strong> Choose your preferred job role from available options</li>
            <li><strong>Resume Analysis:</strong> Your resume will be automatically analyzed for job fit</li>
            <li><strong>Review Process:</strong> High-scoring resumes may be auto-approved</li>
            <li><strong>Admin Review:</strong> Lower-scoring resumes will be reviewed by administrators</li>
          </ul>

          <p>If the button above doesn't work, you can copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6b7280;">#{profile_url}</p>

          <h3>After Profile Completion:</h3>
          <p>Once you've completed your profile and it's been approved, you can log in to your student dashboard:</p>
          <p style="text-align: center; margin: 20px 0;">
            <a href="#{frontend_url()}/auth/tenant/#{context.name}/login" class="button" style="background: #f97316; color: #FFFFFF;">Student Login</a>
          </p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp profile_completion_text(student, profile_url, context) do
    """
    Upload Resume & Complete Your Profile - #{context.name}

    Hello #{student.first_name}!

    Your student account has been created at #{context.name}. To complete your registration and access the platform, please upload your resume for automated analysis.

    Upload your resume at: #{profile_url}

    IMPORTANT:
    - This link will expire in 48 hours
    - You'll need to upload your resume (PDF/DOCX format, max 5MB)
    - Select your preferred job role for resume analysis
    - After upload, your resume will be automatically analyzed
    - High-quality resumes may be auto-approved

    What happens next:
    - Resume Upload: Upload your resume in PDF or DOCX format (max 5MB)
    - Role Selection: Choose your preferred job role from available options
    - Resume Analysis: Your resume will be automatically analyzed for job fit
    - Review Process: High-scoring resumes may be auto-approved
    - Admin Review: Lower-scoring resumes will be reviewed by administrators

    After Profile Completion:
    Once you've completed your profile and it's been approved, you can log in to your student dashboard:
    #{frontend_url()}/auth/tenant/#{context.name}/login

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp profile_approved_html(student, temp_password, context) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Profile Approved - Welcome to #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .password-box { background: #e5e7eb; padding: 15px; border-radius: 6px; margin: 20px 0; text-align: center; font-family: monospace; font-size: 18px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Profile Approved!</h1>
        </div>
        <div class="content">
          <h2>Congratulations #{student.first_name}!</h2>
          <p>Your profile has been reviewed and approved by the administrator. Your account is now active and ready to use.</p>

          <div class="password-box">
            <strong>Email:</strong> #{student.email}<br>
            <strong>Registration ID:</strong> #{student.registration_id}<br>
            <strong>Temporary Password:</strong> #{temp_password}
          </div>

          <div class="warning">
            <strong>Important:</strong> Please change your password immediately after your first login for security.
          </div>

          <h3>Next Steps:</h3>
          <ol>
            <li>Log in using the credentials above</li>
            <li>Change your password to something secure</li>
            <li>Access your student dashboard</li>
            <li>Start taking assessments</li>
          </ol>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{frontend_url()}" class="button" style="color: #FFFFFF;">Log In Now</a>
          </p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp profile_approved_text(student, temp_password, context) do
    """
    Profile Approved - Welcome to #{context.name}!

    Congratulations #{student.first_name}!

    Your profile has been reviewed and approved by the administrator. Your account is now active and ready to use.

    Login Credentials:
    Email: #{student.email}
    Registration ID: #{student.registration_id}
    Temporary Password: #{temp_password}

    IMPORTANT: Please change your password immediately after your first login for security.

    Next Steps:
    1. Log in using the credentials above
    2. Change your password to something secure
    3. Access your student dashboard
    4. Start taking assessments

    Log in at: #{frontend_url()}

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp profile_edit_request_html(student, _profile_url, admin_notes, edit_request_notes, context) do
    base_url = frontend_url()
    ats_upload_url = "#{base_url}/profile/#{student.profile_token}/ats"

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Profile Review - Updates Required - #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Profile Review - Updates Required</h1>
        </div>
        <div class="content">
          <h2>Hello #{student.first_name}!</h2>
          <p>Your profile has been reviewed by an administrator, and updates are required. Please review the notes and make the necessary changes.</p>

          <h3>Admin Notes:</h3>
          <p>#{admin_notes}</p>

          <h3>Edit Request Notes:</h3>
          <p>#{edit_request_notes}</p>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{ats_upload_url}" class="button">Review and Update Profile</a>
          </p>

          <div class="warning">
            <strong>Important:</strong>
            <ul>
              <li>You must complete all updates within 24 hours to avoid account deactivation.</li>
              <li>Failure to comply may result in your account being locked.</li>
              <li>Do not share this link with anyone.</li>
            </ul>
          </div>

          <p>If the button above doesn't work, you can copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6b7280;">#{ats_upload_url}</p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp profile_edit_request_text(student, _profile_url, admin_notes, edit_request_notes, context) do
    base_url = frontend_url()
    ats_upload_url = "#{base_url}/profile/#{student.profile_token}/ats"

    """
    Profile Review - Updates Required - #{context.name}

    Hello #{student.first_name}!

    Your profile has been reviewed by an administrator, and updates are required. Please review the notes and make the necessary changes.

    Admin Notes:
    #{admin_notes}

    Edit Request Notes:
    #{edit_request_notes}

    Complete your profile at: #{ats_upload_url}

    IMPORTANT:
    - You must complete all updates within 24 hours to avoid account deactivation.
    - Failure to comply may result in your account being locked.
    - Do not share this link with anyone.

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp profile_edit_approved_html(student, admin_notes, context) do
    base_url = frontend_url()

    profile_url =
      "#{base_url}/profile/#{student.profile_token}/ats"

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Profile Edit Request Approved - #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Profile Edit Request Approved</h1>
        </div>
        <div class="content">
          <h2>Hello #{student.first_name}!</h2>
          <p>Your profile edit request has been approved by the administrator. You can now update your profile using the link below.</p>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{profile_url}" class="button">Edit My Profile</a>
          </p>

          <div class="warning">
            <strong>Important:</strong>
            <ul>
              <li>This link will expire in 48 hours</li>
              <li>You can update your resume, skills, work experience, and other profile information</li>
              <li>After completion, your updated profile will be reviewed by an administrator</li>
            </ul>
          </div>

          #{if admin_notes && admin_notes != "" do
      """
      <h3>Admin Notes:</h3>
      <p>#{admin_notes}</p>
      """
    else
      ""
    end}

          <p>If the button above doesn't work, you can copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6b7280;">#{profile_url}</p>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp profile_edit_approved_text(student, admin_notes, context) do
    base_url = frontend_url()

    profile_url =
      "#{base_url}/profile/#{student.profile_token}/ats"

    """
    Profile Edit Request Approved - #{context.name}

    Hello #{student.first_name}!

    Your profile edit request has been approved by the administrator. You can now update your profile using the link below.

    Edit your profile at: #{profile_url}

    IMPORTANT:
    - This link will expire in 48 hours
    - You can update your resume, skills, work experience, and other profile information
    - After completion, your updated profile will be reviewed by an administrator

    #{if admin_notes && admin_notes != "" do
      "Admin Notes: #{admin_notes}"
    else
      ""
    end}

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  defp profile_edit_rejected_html(student, admin_notes, rejection_notes, context) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Profile Edit Rejected - #{context.name}</title>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #f97316; color: #FFFFFF; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9fafb; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 14px; }
        .button { display: inline-block; padding: 12px 24px; background: #f97316; color: #FFFFFF; text-decoration: none; border-radius: 6px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Profile Edit Rejected!</h1>
        </div>
        <div class="content">
          <h2>Hello #{student.first_name}!</h2>
          <p>Your profile has been reviewed and rejected by the administrator. Please review the rejection notes and make the necessary changes.</p>

          <h3>Admin Notes:</h3>
          <p>#{admin_notes}</p>

          <h3>Rejection Notes:</h3>
          <p>#{rejection_notes}</p>

          <p style="text-align: center; margin: 30px 0;">
            <a href="#{frontend_url()}" class="button" style="color: #FFFFFF;">Log In Now</a>
          </p>

          <div class="warning">
            <strong>Important:</strong>
            <ul>
              <li>You must re-submit your profile for review after making the necessary changes.</li>
              <li>Failure to comply may result in your account being locked.</li>
              <li>Do not share this link with anyone.</li>
            </ul>
          </div>

          <p>If you have any questions or need assistance, please contact support.</p>
        </div>
        <div class="footer">
          <p>This is an automated message from #{context.name}. Please do not reply to this email.</p>
          <p>&copy; #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")} VyaasaCampus. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp profile_edit_rejected_text(student, admin_notes, rejection_notes, context) do
    """
    Profile Edit Rejected - #{context.name}!

    Hello #{student.first_name}!

    Your profile has been reviewed and rejected by the administrator. Please review the rejection notes and make the necessary changes.

    Admin Notes:
    #{admin_notes}

    Rejection Notes:
    #{rejection_notes}

    IMPORTANT:
    - You must re-submit your profile for review after making the necessary changes.
    - Failure to comply may result in your account being locked.
    - Do not share this link with anyone.

    If you have any questions or need assistance, please contact support.

    This is an automated message from #{context.name}. Please do not reply to this email.
    """
  end

  # ------------------- Assessment Report Template -------------------

  @doc """
  Generate assessment report delivery email.
  `opts` expects:
    * `:report_title` — human-readable report title (e.g. "MCQ Assessment Report")
    * `:assessment_title` — the specific assessment name
    * `:tenant_alias` — tenant alias (optional)
  """
  def assessment_report_template(user, opts) do
    report_type = Map.get(opts, :report_type)
    report_title = Map.get(opts, :report_title, "Assessment Report")
    assessment_title = Map.get(opts, :assessment_title, "your recent assessment")
    tenant_alias = Map.get(opts, :tenant_alias)
    context = get_context(user, tenant_alias)

    %{
      subject: "#{report_title} — #{assessment_title}",
      html_body: assessment_report_html(user, report_type, report_title, assessment_title, context),
      text_body: assessment_report_text(user, report_type, report_title, assessment_title, context)
    }
  end

  # Per-report "what's inside" highlights so each email is tailored to its
  # assessment rather than showing generic MCQ bullets everywhere.
  defp report_highlights(:mcq),
    do: [
      "Overall score and percentage",
      "Question-wise breakdown (correct, wrong, unanswered)",
      "Accuracy and completion rate",
      "Time analysis"
    ]

  defp report_highlights(:jam),
    do: [
      "Overall speaking score",
      "Fluency, coherence, vocabulary & confidence",
      "Full speech transcript",
      "Strengths & areas to improve"
    ]

  defp report_highlights(:psychometric),
    do: [
      "Big Five personality profile",
      "Trait-by-trait breakdown",
      "Competency composites (work ethic, collaboration, leadership)",
      "Strengths & development areas"
    ]

  defp report_highlights(:behavioral),
    do: [
      "Overall behavioural score",
      "STAR-based competency breakdown",
      "Scenario-by-scenario feedback",
      "Strengths & areas to improve"
    ]

  defp report_highlights(:interview),
    do: [
      "Overall interview score",
      "Communication, cultural-fit & domain evaluation",
      "Question-by-question feedback",
      "Strengths & areas to improve"
    ]

  defp report_highlights(:case_study),
    do: [
      "Overall case-study score",
      "Domain, problem-solving & leadership breakdown",
      "Evaluator summary & verdict",
      "Strengths & areas for improvement"
    ]

  defp report_highlights(:mini_project),
    do: [
      "Overall project score & grade band",
      "Domain, collaboration & leadership indexes",
      "Evaluator report",
      "Strengths & areas for improvement"
    ]

  defp report_highlights(:resume),
    do: [
      "ATS match score",
      "Section-by-section resume analysis",
      "Keyword & skills gaps",
      "Concrete improvement suggestions"
    ]

  defp report_highlights(:ai8),
    do: [
      "Your AI8 employability index",
      "All eight competency dimensions",
      "Your strongest area & biggest opportunity"
    ]

  defp report_highlights(:employability_card),
    do: [
      "Your verified AI8 employability score",
      "Your employability tier & percentile",
      "A QR code linking to your public profile",
      "Card front (page 1) & back (page 2), ready to share"
    ]

  defp report_highlights(:certificate),
    do: [
      "Your VYAASA Certificate of Career Readiness",
      "Certificate ID, issue date & validity",
      "A QR code linking to your verified public profile",
      "CEO & Co-Founder signed, ready to share"
    ]

  defp report_highlights(_),
    do: [
      "Overall score and performance summary",
      "Detailed competency breakdown",
      "Strengths & areas to improve"
    ]

  defp assessment_report_html(user, report_type, report_title, assessment_title, context) do
    highlights =
      report_highlights(report_type)
      |> Enum.map_join("", fn h ->
        "<tr><td style=\"padding:4px 0;color:#374151;font-size:14px;\">" <>
          "<span style=\"color:#f97316;font-weight:bold;\">&#10003;</span>&nbsp;&nbsp;#{h}</td></tr>"
      end)

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>#{report_title}</title></head>
    <body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">
      <div style="max-width:600px;margin:0 auto;padding:24px 16px;">
        <div style="background:#ffffff;border-radius:14px;overflow:hidden;border:1px solid #e5e7eb;">
          <!-- Header -->
          <div style="background:#f97316;padding:28px 28px 22px;">
            <p style="margin:0;color:#ffedd5;font-size:12px;letter-spacing:1.5px;text-transform:uppercase;font-weight:bold;">#{context.name}</p>
            <h1 style="margin:6px 0 0;color:#ffffff;font-size:22px;">#{report_title}</h1>
            <p style="margin:6px 0 0;color:#ffedd5;font-size:14px;">#{assessment_title}</p>
          </div>
          <!-- Body -->
          <div style="padding:26px 28px;">
            <p style="margin:0 0 14px;font-size:15px;">#{report_greeting(report_type, user)}</p>
            <p style="margin:0 0 20px;font-size:14px;line-height:1.6;color:#374151;">
              #{report_intro_html(report_type, assessment_title)}
            </p>
            <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:10px;padding:16px 18px;">
              <p style="margin:0 0 8px;font-weight:bold;font-size:13px;color:#9a3412;">What's inside your report</p>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;">#{highlights}</table>
            </div>
            <p style="margin:22px 0 0;font-size:13px;color:#6b7280;line-height:1.6;">
              You can also re-download the latest version any time from your #{context.name} dashboard.
            </p>
          </div>
          <!-- Footer -->
          <div style="padding:18px 28px;background:#f9fafb;border-top:1px solid #e5e7eb;">
            <p style="margin:0;color:#9ca3af;font-size:12px;line-height:1.5;">
              This is an automated message from #{context.name}. Please do not reply to this email.
            </p>
          </div>
        </div>
        <p style="text-align:center;color:#c4c4c4;font-size:11px;margin:14px 0 0;">Powered by Vyaasa</p>
      </div>
    </body>
    </html>
    """
  end

  defp assessment_report_text(user, report_type, report_title, assessment_title, context) do
    highlights =
      report_highlights(report_type)
      |> Enum.map_join("\n", fn h -> "  - #{h}" end)

    """
    #{report_greeting(report_type, user)}

    #{report_intro_text(report_type, assessment_title, report_title)}

    What's inside your report:
    #{highlights}

    You can also re-download the latest version from your #{context.name} dashboard.

    This is an automated message from #{context.name}. Please do not reply.
    """
  end

  # Most report types get the neutral "Hi {name}," salutation; the
  # employability card is meant to feel like a personal hand-off ("here's
  # your card"), so it gets the warmer "Hey {name}," greeting instead.
  defp report_greeting(:employability_card, user), do: "Hey #{user.first_name},"
  defp report_greeting(:certificate, user), do: "Hey #{user.first_name},"
  defp report_greeting(_report_type, user), do: "Hi #{user.first_name},"

  defp report_intro_html(:employability_card, assessment_title) do
    "Here's your <strong>#{assessment_title}</strong> — your verified AI8 employability score, tier, " <>
      "and QR-verified profile link, ready to share with recruiters. It's attached to this email as a " <>
      "<strong>PDF</strong> (card front on page 1, back on page 2)."
  end

  defp report_intro_html(:certificate, assessment_title) do
    "Here's your <strong>VYAASA Certificate of Career Readiness</strong> (#{assessment_title}) — signed, " <>
      "QR-verified, and ready to share with recruiters. It's attached to this email as a <strong>PDF</strong>."
  end

  defp report_intro_html(_report_type, assessment_title) do
    "Your <strong>#{assessment_title}</strong> has been evaluated. Your detailed report is " <>
      "attached to this email as a <strong>PDF</strong>."
  end

  defp report_intro_text(:employability_card, assessment_title, _report_title) do
    "Here's your #{assessment_title} — your verified AI8 employability score, tier, and QR-verified " <>
      "profile link, ready to share with recruiters. It's attached to this email as a PDF " <>
      "(card front on page 1, back on page 2)."
  end

  defp report_intro_text(:certificate, assessment_title, _report_title) do
    "Here's your VYAASA Certificate of Career Readiness (#{assessment_title}) — signed, QR-verified, " <>
      "and ready to share with recruiters. It's attached to this email as a PDF."
  end

  defp report_intro_text(_report_type, assessment_title, report_title) do
    "Your #{assessment_title} has been evaluated. Your detailed " <>
      "#{String.downcase(report_title)} is attached to this email as a PDF."
  end
end
