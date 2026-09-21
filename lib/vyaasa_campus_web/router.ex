defmodule VyaasaCampusWeb.Router do
  use VyaasaCampusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VyaasaCampusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_secure_headers
    plug VyaasaCampusWeb.Plugs.TenantPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug VyaasaCampusWeb.Plugs.TenantPlug
  end

  pipeline :auth do
    plug VyaasaCampusWeb.Plugs.AuthPlug
  end

  pipeline :require_auth do
    plug VyaasaCampusWeb.Plugs.AuthPlug, :require_auth
    plug VyaasaCampusWeb.Plugs.ScopePlug
  end

  pipeline :require_admin do
    plug VyaasaCampusWeb.Plugs.AuthPlug, :require_admin
    plug VyaasaCampusWeb.Plugs.ScopePlug
  end

  pipeline :require_tenant_user_or_admin do
    plug VyaasaCampusWeb.Plugs.AuthPlug, :require_tenant_user_or_admin
    plug VyaasaCampusWeb.Plugs.ScopePlug
  end

  pipeline :require_tenant_user_only do
    plug VyaasaCampusWeb.Plugs.AuthPlug, :require_tenant_user_only
    plug VyaasaCampusWeb.Plugs.ScopePlug
  end

  pipeline :require_student do
    plug VyaasaCampusWeb.Plugs.AuthPlug, :require_student
    plug VyaasaCampusWeb.Plugs.ScopePlug
  end

  # NOTE: All AI feature callback pipelines (ATS, JAM, Behavioral, Psychometric)
  # removed — every service now runs natively in Elixir, no Python callbacks needed.

  # ------------------- Homepage Route -------------------
  scope "/", VyaasaCampusWeb do
    pipe_through [:browser]

    live_session :homepage do
      # Root homepage for institution selection
      live "/", HomepageLive, :index
    end
  end

  # ------------------- Super Admin Routes -------------------
  scope "/admin", VyaasaCampusWeb do
    pipe_through :browser

    live_session :admin_auth do
      live "/login", Admin.LoginLive, :index
      live "/forgot-password", Admin.ForgotPasswordLive, :index
      live "/reset-password/:token", Admin.ResetPasswordLive, :index
    end

    live_session :authenticated_admin, on_mount: {VyaasaCampusWeb.Plugs.AuthPlug, :require_admin} do
      live "/dashboard", Admin.DashboardLive, :index
      live "/colleges", Admin.CollegesLive, :index
      live "/colleges/new", Admin.AddCollegeLive, :index
      live "/colleges/:id/config", Admin.CollegeConfigLive, :index
      live "/ai8-config", Admin.AI8ConfigLive, :index
      live "/degrees", Admin.DegreesLive, :index
      live "/question-bank", Admin.QuestionBankLive, :index
      live "/jobs", Admin.JobsLive, :index
      live "/change-password", Shared.ChangePasswordLive, :admin_change_password
    end
  end

  # Super-admin controller routes (CSV exports etc.)
  scope "/admin", VyaasaCampusWeb do
    pipe_through [:browser, :require_admin]

    get "/colleges/export", Admin.CollegesController, :export
  end

  # ------------------- Authentication Frontend Routes -------------------
  scope "/auth", VyaasaCampusWeb do
    pipe_through :browser

    live_session :auth do
      # Unified authentication routes for both tenant users and students
      live "/tenant/:tenant/login", Auth.LoginLive, :index
      live "/tenant/:tenant/forgot-password", Auth.ForgotPasswordLive, :index
      live "/tenant/:tenant/reset-password/:token", Auth.ResetPasswordLive, :index
    end

    # Logout is a controller route on the plain browser pipeline (no auth), so it
    # clears the session even for a superseded single-session token.
    get "/tenant/:tenant/logout", SessionController, :tenant_logout
  end

  # ------------------- User Dashboard Routes -------------------
  scope "/user", VyaasaCampusWeb do
    pipe_through :browser

    live_session :authenticated_user, on_mount: {VyaasaCampusWeb.Plugs.AuthPlug, :require_tenant_user_only} do
      # User Dashboard (tenant users only)
      live "/:tenant/dashboard", TenantUser.DashboardLive, :index
      live "/:tenant/dashboard/addstudent", TenantUser.DashboardLive, :add_student

      # Dashboard child routes
      live "/:tenant/dashboard/students", TenantUser.StudentsLive, :index
      live "/:tenant/dashboard/students/new", TenantUser.AddStudentLive, :index
      live "/:tenant/dashboard/programs", TenantUser.ProgramsLive, :index
      live "/:tenant/change-password", Shared.ChangePasswordLive, :user_change_password
    end

    # Server-side PDF report downloads (admin only)
    scope "/" do
      pipe_through :require_tenant_user_or_admin
      get "/:tenant/reports/leaderboard", ReportController, :download_leaderboard
      get "/:tenant/reports/specialization", ReportController, :download_specialization
      get "/:tenant/reports/analytics", ReportController, :download_analytics
      get "/:tenant/reports/readiness", ReportController, :download_readiness
    end
  end

  # ------------------- Student Dashboard Routes -------------------
  scope "/student", VyaasaCampusWeb do
    pipe_through :browser

    live_session :authenticated_student, on_mount: {VyaasaCampusWeb.Plugs.AuthPlug, :require_student} do
      # Student Dashboard (students only)
      live "/:tenant/ai8-overview", Student.AI8OverviewLive, :index
      live "/:tenant/dashboard", Student.DashboardLive, :index
      live "/:tenant/profile", Student.ProfileLive, :index
      live "/:tenant/change-password", Shared.ChangePasswordLive, :student_change_password

      # Assessment flow
      live "/:tenant/assessment/instructions", Student.Assessment.InstructionsLive, :index
      live "/:tenant/assessment/behavioral", Student.BehavioralLive, :index
      live "/:tenant/assessment/:id/test", Student.Assessment.TestLive, :test
      live "/:tenant/assessment/:id/review", Student.Assessment.ReviewLive, :review
      live "/:tenant/assessment/:id/result", Student.Assessment.ResultLive, :result

      # JAM session flow
      live "/:tenant/jam/session", Student.Jam.JamSessionLive, :index

      # AI Interview session flow
      live "/:tenant/interview/session", Student.Interview.InterviewSessionLive, :index

      # Psychometric Assessment flow
      live "/:tenant/assessment/psychometric", Student.Psychometric.PsychometricLive, :index

      # AI-Generated Case Study flow
      live "/:tenant/case-study", Student.CaseStudy.CaseStudyLive, :index

      # Domain Mini Project
      # Domain Mini Project — the original engine/UI (no full screen, file upload)
      # is the canonical route. The V4 viva-driven engine stays available at
      # /mini-project-v4 for evaluation.
      live "/:tenant/mini-project", Student.MiniProject.MiniProjectLive, :index
      live "/:tenant/mini-project-v4", Student.MiniProject.MiniProjectV4Live, :index

      # Resume Insights — full Resume Analysis Dashboard
      live "/:tenant/resume/insights", Student.Resume.InsightsLive, :index

      # Resume Re-analysis (tracks score improvements over time)
      # Reuses ProfileCompletionLive but with current_user authentication and
      # :reanalyze_mode? set, so only a new resume + job role are required.
      live "/:tenant/resume/reanalyze", Student.ProfileCompletionLive, :reanalyze
    end

    # Student assessment reports are delivered by email only (no direct download).
    # See VyaasaCampus.Jobs.ReportGenerator (auto-enqueued on completion).
  end

  # ------------------- All the APIS -------------------
  scope "/api", VyaasaCampusWeb do
    pipe_through :api

    # Authentication routes (no auth required)
    post "/auth/platform-admin/login", Auth.AuthController, :platform_admin_login
    post "/auth/tenant-user/login", Auth.AuthController, :tenant_user_login
    post "/auth/student/login", Auth.AuthController, :student_login
    post "/auth/student/register", Auth.AuthController, :student_register
    post "/auth/refresh", API.Auth.RefreshTokenController, :refresh
    post "/auth/password-reset/request", API.Auth.PasswordResetController, :request_reset
    post "/auth/password-reset/reset", API.Auth.PasswordResetController, :reset_password

    # Profile completion routes (no auth required - uses tokens)
    get "/student/profile-completion/verify", Student.ProfileController, :verify_token
    post "/student/profile-completion/submit", Student.ProfileController, :submit_profile

    # NOTE: All AI feature callback routes (ATS, JAM, Behavioral, Psychometric)
    # removed — every service now runs natively in Elixir.

    # Protected routes (auth required)
    scope "/" do
      pipe_through :require_auth
      get "/auth/me", Auth.AuthController, :me
      post "/auth/logout", Auth.AuthController, :logout
      post "/auth/clear-temp-password", API.Auth.PasswordResetController, :clear_temp_password
      post "/auth/change-password", API.Auth.PasswordResetController, :change_password
    end

    # Platform Admin routes (platform admin only)
    scope "/platform_admin" do
      pipe_through :require_admin

      # Tenant management (only platform admin)
      resources "/tenants", PlatformAdmin.TenantController, except: [:new, :edit] do
        post "/activate", PlatformAdmin.TenantController, :activate
        post "/deactivate", PlatformAdmin.TenantController, :deactivate
      end

      # Tenant locations (only platform admin - uses x-tenant header for tenant resolution)
      resources "/locations", PlatformAdmin.TenantLocationController, except: [:new, :edit] do
        post "/set_primary", PlatformAdmin.TenantLocationController, :set_primary
      end
    end

    # Tenant-scoped routes (tenant users + platform admin - uses x-tenant header for tenant resolution)
    scope "/tenant" do
      pipe_through :require_tenant_user_or_admin

      # User management (tenant users + platform admin)
      resources "/users", TenantAdmin.UserManagement.UserController, except: [:new, :edit]
      resources "/roles", TenantAdmin.UserManagement.RoleController, except: [:new, :edit]

      resources "/user_roles", TenantAdmin.UserManagement.UserRoleController, only: [:index, :create]

      # Student management (tenant users only)
      get "/students/pending", TenantAdmin.StudentManagement.StudentController, :list_pending
      post "/students/:id/approve", TenantAdmin.StudentManagement.StudentController, :approve
      post "/students/:id/reject", TenantAdmin.StudentManagement.StudentController, :reject

      # Student document downloads (tenant users only)
      get "/students/:student_id/resume/*filename", TenantAdmin.StudentManagement.StudentController, :download_resume
      get "/students/:student_id/document/id_card", TenantAdmin.StudentManagement.StudentController, :download_id_card

      get "/students/:student_id/document/profile_photo",
          TenantAdmin.StudentManagement.StudentController,
          :download_profile_photo

      get "/students/edit-requests",
          TenantAdmin.StudentManagement.StudentController,
          :list_edit_requests

      post "/students/:id/approve-edit",
           TenantAdmin.StudentManagement.StudentController,
           :approve_edit

      post "/students/:id/reject-edit",
           TenantAdmin.StudentManagement.StudentController,
           :reject_edit

      resources "/students", TenantAdmin.StudentManagement.StudentController, only: [:create, :index, :update]

      post "/students/bulk", TenantAdmin.StudentManagement.StudentController, :bulk_create

      # Assessment management (tenant users only)
      resources "/assessments", TenantAdmin.AssessmentManagement.AssessmentController, except: [:new, :edit] do
        post "/publish", TenantAdmin.AssessmentManagement.AssessmentController, :publish
        post "/archive", TenantAdmin.AssessmentManagement.AssessmentController, :archive
      end
    end

    # Student routes (students only)

    scope "/student" do
      pipe_through :require_student

      get "/assessments", Student.AssessmentController, :index_published
      get "/assessments/:id", Student.AssessmentController, :show_published
      post "/assessments/:id/start", Student.AssessmentController, :start_attempt
      get "/attempts/:id", Student.AssessmentController, :show_attempt
      put "/attempts/:id/submit", Student.AssessmentController, :submit_attempt
      get "/my-attempts", Student.AssessmentController, :my_attempts

      # Profile edit request (students only)
      post "/profile/edit-request", Student.ProfileController, :request_edit

      # Profile completion resend (admin only)
      post "/profile-completion/resend", Student.ProfileController, :resend_profile_email

      # JAM session management (students only)
      resources "/jam/sessions", Controllers.API.Student.JamController, only: [:create, :show, :update] do
        post "/start", Controllers.API.Student.JamController, :start
        post "/decide-topic", Controllers.API.Student.JamController, :decide_topic
        post "/start-preparation", Controllers.API.Student.JamController, :start_preparation
        post "/start-speaking", Controllers.API.Student.JamController, :start_speaking
        post "/upload-audio", Controllers.API.Student.JamController, :upload_audio
        get "/status", Controllers.API.Student.JamController, :status
        get "/results", Controllers.API.Student.JamController, :results
      end
    end
  end

  # ------------------- Session Management Routes -------------------
  scope "/", VyaasaCampusWeb do
    pipe_through [:browser, VyaasaCampusWeb.Plugs.TenantPlug]

    # Session token setting route
    get "/auth/set-session/:tenant", SessionController, :set_session
  end

  # Admin session routes (no tenant required)
  scope "/auth/admin", VyaasaCampusWeb do
    pipe_through :browser

    get "/set-session", SessionController, :set_admin_session
    get "/logout", SessionController, :admin_logout
  end

  # ------------------- Profile Completion Routes -------------------
  scope "/profile", VyaasaCampusWeb do
    pipe_through :browser

    live_session :profile_completion do
      live "/:profile_token/ats", Student.ProfileCompletionLive, :index
      live "/:tenant/submitted", Student.ProfileSubmittedLive, :index
    end

    # Public shared profile (no auth required — short public slug)
    live_session :shared_profile do
      live "/shared/:token", Student.SharedProfileLive, :index
    end
  end

  # ------------------- ATS Upload Routes -------------------
  # These routes are outside the /api scope and use the browser pipeline
  scope "/", VyaasaCampusWeb do
    pipe_through [:browser, VyaasaCampusWeb.Plugs.TenantPlug]

    # Student dashboard route (no auth required - uses profile tokens)
    live "/student/dashboard/:profile_token", Student.DashboardLive, :index, as: :student_dashboard
  end

  # ------------------- Development routes -------------------
  if Application.compile_env(:vyaasa_campus, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :require_admin]
      live_dashboard "/dashboard", metrics: VyaasaCampusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # ------------------- Catch-all 404 -------------------
  # Must stay last: renders the friendly 404 page for any request that
  # doesn't match a route above, instead of raising NoRouteError.
  scope "/", VyaasaCampusWeb do
    pipe_through :browser

    match :*, "/*path", ErrorController, :not_found
  end

  # Security headers plug
  defp put_secure_headers(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data: https: blob:; " <>
        "font-src 'self' data:; " <>
        "connect-src 'self' ws: wss:; " <>
        "media-src 'self' blob: data:; " <>
        "frame-ancestors 'none'; " <>
        "base-uri 'self'; " <>
        "form-action 'self'"
    )
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.put_resp_header("x-frame-options", "DENY")
    |> Plug.Conn.put_resp_header("x-xss-protection", "1; mode=block")
    |> Plug.Conn.put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
  end
end
