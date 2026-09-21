# VyaasaCampus File Structure

## Overview

This document provides a comprehensive overview of the VyaasaCampus project file structure, explaining the organization, purpose, and relationships between different directories and files.

## Root Directory Structure

```
VyaasaCampus/
├── README.md                    # Main project overview and quick start
├── LICENSE                      # MIT License
├── .gitignore                   # Git ignore rules
└── vyaasa_campus/              # Main application directory
    ├── lib/                    # Source code
    ├── config/                 # Configuration files
    ├── priv/                   # Private assets and migrations
    ├── assets/                 # Frontend assets
    ├── test/                   # Test files
    ├── scripts/                # Development and testing scripts
    ├── mix.exs                 # Mix project configuration
    ├── mix.lock                # Dependency lock file
    ├── .env                    # Environment variables
    ├── .credo.exs              # Code analysis configuration
    ├── .formatter.exs          # Code formatting configuration
    ├── .sobelow                # Security analysis configuration
    └── Documentation files     # Various .md documentation files
```

## Core Application Structure (`lib/`)

### Main Application Module (`lib/vyaasa_campus/`)

```
lib/vyaasa_campus/
├── application.ex              # OTP application supervisor
├── repo.ex                     # Ecto database repository
├── types.ex                    # Custom Ecto types
│
├── auth/                       # Authentication system
│   ├── auth_supervisor.ex      # Auth process supervisor
│   ├── auth_server.ex          # Auth state management (GenServer)
│   ├── auth.ex                 # Authentication logic
│   ├── guardian.ex             # JWT token handling
│   └── scope.ex                # Authorization scopes
│
├── contexts/                   # Business logic modules (Phoenix contexts)
│   ├── accounts.ex             # User account management
│   ├── assessments.ex          # Assessment business logic
│   ├── mailer.ex               # Email functionality
│   ├── platform.ex             # Platform admin operations
│   ├── students.ex             # Student management
│   └── tenant/                 # Multi-tenant operations
│       ├── locations.ex        # Tenant location management
│       ├── schema.ex           # Tenant schema operations
│       └── tenants.ex          # Tenant CRUD operations
│
├── mail/                       # Email system
│   ├── email_orchestrator.ex   # Email workflow management
│   ├── email_service.ex        # Email sending service
│   ├── password_reset_service.ex # Password reset emails
│   └── templates.ex            # Email templates
│
├── schema/                     # Database schemas (Ecto schemas)
│   ├── accounts/               # User account schemas
│   │   ├── role.ex             # Role definitions
│   │   ├── user.ex             # User schema
│   │   └── user_role.ex        # User-role associations
│   ├── assessments/            # Assessment schemas
│   │   ├── assessment.ex       # Assessment definition
│   │   └── assessment_attempt.ex # Student attempts
│   ├── platform/               # Platform schemas
│   │   └── platform_admin.ex   # Platform admin user
│   ├── students/               # Student schemas
│   │   └── student.ex          # Student profile
│   └── tenants/                # Tenant schemas
│       ├── tenant.ex           # Tenant organization
│       └── tenant_location.ex  # Tenant locations
│
├── schemas/                    # Shared schema behaviors
│   └── behaviours/
│       └── password_resettable.ex # Password reset interface
│
└── tenant/                     # Multi-tenancy system
    ├── tenant_supervisor.ex    # Tenant process supervisor
    └── tenant_worker.ex        # Tenant worker processes
```

### Web Interface Layer (`lib/vyaasa_campus_web/`)

```
lib/vyaasa_campus_web/
├── components/                 # Reusable UI components
│   ├── core_components.ex      # Core Phoenix components
│   └── layouts/                # Layout templates
│       └── root.html.heex      # Root layout
│
├── controllers/                # HTTP request handlers
│   ├── api/                    # REST API controllers
│   │   ├── auth/               # Authentication endpoints
│   │   │   ├── auth_controller.ex
│   │   │   ├── password_reset_controller.ex
│   │   │   └── refresh_token_controller.ex
│   │   ├── platform_admin/     # Platform admin API
│   │   │   ├── tenant_controller.ex
│   │   │   └── tenant_location_controller.ex
│   │   ├── student/            # Student API
│   │   │   ├── assessment_controller.ex
│   │   │   └── profile_controller.ex
│   │   ├── tenant_admin/       # Tenant admin API
│   │   │   ├── assessment_management/
│   │   │   ├── student_management/
│   │   │   └── user_management/
│   │   ├── jam_callback_controller.ex # JAM service callbacks
│   │   └── ats_callback_controller.ex # ATS service callbacks
│   │
│   ├── error_handlers/         # Error handling
│   ├── shared/                 # Shared controller logic
│   └── web/                    # Web page controllers
│
├── live/                       # Phoenix LiveView modules
│   ├── student_dashboard_live.ex
│   ├── tenant_admin_dashboard_live.ex
│   └── platform_admin_dashboard_live.ex
│
├── plugs/                      # HTTP request processing middleware
│   ├── auth_plug.ex            # Authentication middleware
│   ├── scope_plug.ex           # Authorization scoping
│   └── tenant_plug.ex          # Tenant resolution
│
├── endpoint.ex                 # Phoenix endpoint configuration
├── gettext.ex                  # Internationalization
├── router.ex                   # URL routing
└── telemetry.ex                # Application metrics
```

## Configuration (`config/`)

```
config/
├── config.exs                  # Base configuration
├── dev.exs                     # Development environment settings
├── prod.exs                    # Production environment settings
├── runtime.exs                 # Runtime configuration
└── test.exs                    # Test environment settings
```

### Configuration Files Purpose

- **config.exs**: Base configuration shared across all environments
- **dev.exs**: Development-specific settings (debugging, hot reload, etc.)
- **prod.exs**: Production settings (optimizations, security, etc.)
- **runtime.exs**: Runtime configuration from environment variables
- **test.exs**: Test environment settings (test database, mocking, etc.)

## Private Assets (`priv/`)

```
priv/
├── repo/                       # Database-related files
│   ├── migrations/             # Main database migrations
│   │   ├── 20250708052800_create_public_tables.exs
│   │   └── ...                 # Other public schema migrations
│   ├── tenant_migrations/      # Tenant database migrations
│   │   ├── 20250709093101_create_tenant_tables_new.exs
│   │   ├── 20241220000001_create_jam_sessions.exs
│   │   └── ...                 # Other tenant schema migrations
│   └── seeds.exs               # Database seeding
│
└── static/                     # Static files
    ├── images/                 # Static images
    ├── favicon.ico             # Favicon
    └── robots.txt              # Robots.txt
```

### Migration Structure

- **migrations/**: Public schema migrations (platform admins, tenants, tenant locations)
- **tenant_migrations/**: Tenant-specific migrations (users, students, assessments, etc.)
- **seeds.exs**: Initial data seeding (platform admins, default configurations)

## Frontend Assets (`assets/`)

```
assets/
├── css/                        # Stylesheets
│   └── app.css                 # Main application styles
├── js/                         # JavaScript files
│   ├── app.js                  # Main application JavaScript
│   └── auth.js                 # Authentication-related JavaScript
├── images/                     # Frontend images
│   └── logo.png                # Application logo
├── vendor/                     # Third-party libraries
│   ├── daisyui-theme.js        # DaisyUI theme configuration
│   ├── daisyui.js              # DaisyUI components
│   ├── heroicons.js            # Heroicons library
│   └── topbar.js               # Topbar navigation
├── package.json                # Node.js dependencies
├── package-lock.json           # Node.js dependency lock
└── tailwind.config.js          # Tailwind CSS configuration
```

### Frontend Technologies

- **Tailwind CSS**: Utility-first CSS framework
- **DaisyUI**: Component library built on Tailwind
- **Heroicons**: Icon library
- **Alpine.js**: Lightweight JavaScript framework
- **Phoenix LiveView**: Real-time UI updates

## Testing (`test/`)

```
test/
├── unit/                       # Unit tests for individual modules
│   ├── auth/                   # Authentication logic tests
│   ├── contexts/               # Business logic tests
│   ├── mail/                   # Email service tests
│   └── schemas/                # Database schema tests
├── integration/                # Integration tests for workflows
│   ├── auth/                   # Authentication flow tests
│   ├── tenant/                 # Multi-tenant workflow tests
│   └── student/                # Student workflow tests
├── web/                        # Web layer tests
│   ├── controllers/            # API controller tests
│   ├── plugs/                  # Plug middleware tests
│   └── live_view/              # LiveView tests
├── support/                    # Test utilities and helpers
│   ├── conn_case.ex            # HTTP connection test setup
│   ├── data_case.ex            # Database test setup
│   ├── helpers.ex              # Test data factories
│   └── tenant_case.ex          # Multi-tenant test setup
└── test_helper.exs             # Test configuration
```

### Test Organization

- **unit/**: Tests for individual modules and functions
- **integration/**: Tests for complete workflows and component interactions
- **web/**: Tests for web layer (controllers, plugs, LiveViews)
- **support/**: Test utilities, helpers, and setup files

## Development Scripts (`scripts/`)

```
scripts/
├── 1_tenant_setup.sh           # Platform setup and tenant management
├── 2_student_onboarding.sh     # Student onboarding and profile completion
├── 3_student_edit_flow.sh      # Student profile edit request workflow
├── tenant_config.env           # Shared configuration for scripts
└── test_helpers.sh             # Test helper functions
```

### Script Purpose

- **1_tenant_setup.sh**: Tests complete tenant creation and setup workflow
- **2_student_onboarding.sh**: Tests student registration and profile completion
- **3_student_edit_flow.sh**: Tests student profile edit request workflow
- **tenant_config.env**: Shared environment variables for cross-script data
- **test_helpers.sh**: Common functions used across test scripts

## Documentation Files

```
vyaasa_campus/
├── README.md                   # Main project overview
├── SETUP_GUIDE.md              # Installation and configuration guide
├── DATABASE_SCHEMA.md          # Database architecture documentation
├── overall_apis.md             # Complete API documentation
├── TESTING_GUIDE.md            # Testing strategies and procedures
├── PROGRESS.md                 # Implementation status and progress
├── ELIXIR_PHOENIX_FEATURES.md  # Technical implementation details
├── ATS_INTEGRATION.md          # ATS service integration guide
├── JAM_INTEGRATION_PLAN.md     # JAM service integration plan
├── FILE_STRUCTURE.md           # This file structure documentation
└── AGENTS.md                   # AI agent guidelines and rules
```

## Configuration Files

### Project Configuration

- **mix.exs**: Mix project configuration with dependencies and project metadata
- **mix.lock**: Dependency lock file ensuring reproducible builds
- **.env**: Environment variables for development
- **.gitignore**: Git ignore rules for version control

### Code Quality Configuration

- **.credo.exs**: Credo code analysis configuration
- **.formatter.exs**: Code formatting configuration
- **.sobelow**: Security analysis configuration

## Key Architectural Patterns

### 1. **Phoenix Context Pattern**
Business logic is organized into contexts (`lib/vyaasa_campus/contexts/`):
- **accounts.ex**: User account management
- **assessments.ex**: Assessment business logic
- **students.ex**: Student management
- **platform.ex**: Platform admin operations

### 2. **Multi-tenant Architecture**
- **Public Schema**: Platform-wide data (tenants, platform admins)
- **Tenant Schemas**: Isolated data per tenant (users, students, assessments)
- **Triplex Integration**: Automatic tenant schema management

### 3. **Layered Architecture**
- **Web Layer**: Controllers, LiveViews, Plugs (`lib/vyaasa_campus_web/`)
- **Business Layer**: Contexts and business logic (`lib/vyaasa_campus/contexts/`)
- **Data Layer**: Schemas and database operations (`lib/vyaasa_campus/schema/`)

### 4. **OTP Supervision**
- **Application Supervisor**: Main application process tree
- **Auth Supervisor**: Authentication-related processes
- **Tenant Supervisor**: Dynamic tenant process management

## File Naming Conventions

### Elixir Files
- **Modules**: `snake_case.ex` (e.g., `user_controller.ex`)
- **LiveViews**: `*_live.ex` (e.g., `student_dashboard_live.ex`)
- **Schemas**: `snake_case.ex` (e.g., `student.ex`)
- **Contexts**: `snake_case.ex` (e.g., `accounts.ex`)

### Migration Files
- **Format**: `YYYYMMDDHHMMSS_descriptive_name.exs`
- **Public**: `migrations/` directory
- **Tenant**: `tenant_migrations/` directory

### Test Files
- **Unit Tests**: `*_test.exs`
- **Integration Tests**: `*_test.exs` in integration directories
- **Support Files**: `*_case.ex` for test setup

## Dependencies and External Services

### Core Dependencies (mix.exs)
- **Phoenix**: Web framework
- **Ecto**: Database wrapper and query builder
- **Guardian**: JWT authentication
- **Triplex**: Multi-tenancy support
- **Oban**: Background job processing
- **Swoosh**: Email functionality
- **Waffle**: File upload handling

### Frontend Dependencies (package.json)
- **Tailwind CSS**: Utility-first CSS framework
- **DaisyUI**: Component library
- **Heroicons**: Icon library
- **Alpine.js**: JavaScript framework

### External Services
- **ATS Service**: Python-based resume analysis
- **JAM Service**: Python-based speech assessment
- **File Storage**: Local file system (AWS S3 planned for future)
- **Email**: Swoosh local mailbox (SMTP planned for production)

This file structure provides a clear, organized foundation for the VyaasaCampus multi-tenant SAAS platform, following Phoenix and Elixir best practices for maintainability and scalability.
