# VyaasaCampus Setup Guide

## Overview

This guide provides comprehensive instructions for setting up the VyaasaCampus multi-tenant educational platform. The platform is built with Phoenix 1.8, Elixir, and PostgreSQL, featuring multi-tenancy, role-based access control, and external service integrations.

## Prerequisites

### System Requirements

- **Operating System**: macOS, Linux, or Windows with WSL2
- **Memory**: Minimum 4GB RAM (8GB recommended)
- **Storage**: At least 2GB free disk space
- **Network**: Internet connection for dependencies

### Required Software

#### 1. Elixir and Erlang

**macOS (using Homebrew)**:
```bash
brew install elixir
```

**Ubuntu/Debian**:
```bash
# Install Erlang
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install esl-erlang

# Install Elixir
sudo apt-get install elixir
```

**Windows (using Chocolatey)**:
```powershell
choco install elixir
```

**Verify Installation**:
```bash
elixir --version
# Should show Elixir 1.15+ and Erlang/OTP 25+
```

#### 2. PostgreSQL

**macOS (using Homebrew)**:
```bash
brew install postgresql@15
brew services start postgresql@15
```

**Ubuntu/Debian**:
```bash
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**Windows**:
Download and install from [PostgreSQL official website](https://www.postgresql.org/download/windows/)

**Verify Installation**:
```bash
psql --version
# Should show PostgreSQL 12+
```

#### 3. Node.js

**Using Node Version Manager (nvm)**:
```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Install and use Node.js 18+
nvm install 18
nvm use 18
```

**Verify Installation**:
```bash
node --version
npm --version
```

#### 4. Git

**macOS**:
```bash
brew install git
```

**Ubuntu/Debian**:
```bash
sudo apt-get install git
```

**Windows**:
Download from [Git official website](https://git-scm.com/download/win)

## Installation Steps

### 1. Clone Repository

```bash
git clone <repository-url>
cd vyaasa_campus
```

### 2. Install Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies
cd assets && npm install && cd ..
```

### 3. Environment Configuration

The application uses environment variables for configuration. A `.env` file is already provided with development defaults:

```bash
# Database Configuration
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
DATABASE_HOST=localhost
DATABASE_NAME=vyaasa_campus_dev
DATABASE_POOL_SIZE=10

# Security Keys (Generate new ones for production)
GUARDIAN_SECRET_KEY=dev-guardian-secret-change-in-production
SECRET_KEY_BASE=random-key-long-key

# Token Configuration
ACCESS_TOKEN_TTL_MINUTES=15
REFRESH_TOKEN_TTL_DAYS=15
REFRESH_TOKEN_SALT=random-key

# Email Configuration (Development - Swoosh Local Mailbox)
# Emails are viewed at http://localhost:4000/dev/mailbox
# SMTP not configured for development

# File Storage (Local - AWS S3 planned for future)
# Files stored in priv/uploads/ directory
# AWS_ACCESS_KEY_ID=your-aws-access-key (future)
# AWS_SECRET_ACCESS_KEY=your-aws-secret-key (future)
# AWS_REGION=us-east-1 (future)
# AWS_BUCKET=vyaasa-campus-files (future)

# External Services (Optional - for ATS and JAM integration)
ATS_BASE_URL=http://localhost:8000
ATS_SERVICE_TOKEN=your-ats-service-token
JAM_SECRET=your-jam-service-secret
PYTHON_BASE_URL=http://localhost:8000

# Application Configuration
PORT=4000
HOST=localhost
```

### 4. Generate Security Keys

```bash
# Generate secret key base
mix phx.gen.secret

# Generate Guardian secret
mix phx.gen.secret

# Generate refresh token salt
mix phx.gen.secret
```

### 5. Database Setup

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Seed initial data
mix run priv/repo/seeds.exs
```

### 6. Asset Compilation

```bash
# Compile assets
mix assets.deploy
```

### 7. Start the Server

```bash
# Start Phoenix server
mix phx.server
```

Visit [`http://localhost:4000`](http://localhost:4000) to verify the installation.

## Database Setup Details

### PostgreSQL Configuration

#### Create Database User

```sql
-- Connect to PostgreSQL as superuser
sudo -u postgres psql

-- Create database user
CREATE USER vyaasa_campus WITH PASSWORD 'your_password';

-- Create database
CREATE DATABASE vyaasa_campus_dev OWNER vyaasa_campus;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE vyaasa_campus_dev TO vyaasa_campus;

-- Exit
\q
```

#### Database Schema Setup

The application uses a multi-tenant architecture with two types of schemas:

1. **Public Schema**: Platform-wide data (platform admins, tenants, tenant locations)
2. **Tenant Schemas**: Isolated data per tenant (users, students, assessments)

```bash
# Run public migrations
mix ecto.migrate

# Create a test tenant (optional)
mix run -e "
tenant = %{
  full_name: \"Test University\",
  short_name: \"Test Uni\",
  alias: \"test_uni\",
  affiliation_type: \"university\",
  email: \"admin@testuni.edu\"
}
VyaasaCampus.Contexts.Platform.create_tenant(tenant)
"
```

### Multi-Tenant Setup

#### Create Tenants Using Shell Scripts

Tenants are created using the provided shell scripts, not through IEx commands:

```bash
# Run the tenant setup script
./scripts/1_tenant_setup.sh

# This script will:
# 1. Authenticate as platform admin
# 2. Create a tenant with locations
# 3. Create tenant users and roles
# 4. Set up role assignments
# 5. Export configuration to tenant_config.env

# Run student onboarding script
./scripts/2_student_onboarding.sh

# Run student edit flow script
./scripts/3_student_edit_flow.sh
```

**Note**: The shell scripts handle the complete tenant setup process including:
- Platform admin authentication
- Tenant creation with schema generation
- Location setup
- User and role creation
- Role assignments
- Configuration export for other scripts

## External Services Setup

### 1. ATS (Applicant Tracking System) Service

The ATS service is a Python-based microservice for resume analysis.

#### Python ATS Service Setup

```bash
# Clone ATS service repository (if separate)
git clone <ats-service-repo>
cd ats-service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your configuration

# Start ATS service
python app.py
```

#### ATS Service Configuration

```bash
# ATS Service Environment Variables
ATS_SERVICE_TOKEN=your-ats-service-token
JWT_SECRET=your-jwt-secret
DATABASE_URL=postgresql://user:pass@localhost/ats_db
AWS_ACCESS_KEY_ID=your-aws-key
AWS_SECRET_ACCESS_KEY=your-aws-secret
AWS_BUCKET=resume-bucket
```

### 2. JAM (Just A Minute) Service

The JAM service handles speech assessment and evaluation.

#### JAM Service Setup

```bash
# Clone JAM service repository (if separate)
git clone <jam-service-repo>
cd jam-service

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your configuration

# Start JAM service
python app.py
```

### 3. File Storage (Future: AWS S3)

**Note**: Currently using local file system storage. AWS S3 integration is planned for future implementation.

#### Current File Storage
- Files are stored locally in `priv/uploads/` directory
- Organized by tenant and student structure
- Resume uploads, profile pictures, and documents supported

#### Future AWS S3 Setup (Planned)

1. **Create S3 Bucket**:
   ```bash
   aws s3 mb s3://vyaasa-campus-files
   ```

2. **Configure CORS**:
   ```json
   [
     {
       "AllowedHeaders": ["*"],
       "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
       "AllowedOrigins": ["*"],
       "ExposeHeaders": []
     }
   ]
   ```

3. **Create IAM User**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::vyaasa-campus-files/*"
       }
     ]
   }
   ```

## Development Tools Setup

### 1. Code Quality Tools

```bash
# Install Credo for code analysis
mix deps.get

# Install Dialyxir for type checking
mix deps.get

# Install Sobelow for security analysis
mix deps.get
```

### 2. Pre-commit Hooks

```bash
# Install pre-commit hooks
mix precommit.install

# Run pre-commit checks
mix precommit
```

### 3. Development Database

```bash
# Reset database for development
mix ecto.reset

# Run seeds
mix run priv/repo/seeds.exs
```

## Configuration Files

### 1. Database Configuration

**config/dev.exs**:
```elixir
config :vyaasa_campus, VyaasaCampus.Repo,
  username: System.get_env("DATABASE_USERNAME") || "postgres",
  password: System.get_env("DATABASE_PASSWORD") || "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: System.get_env("DATABASE_NAME") || "vyaasa_campus_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10")
```

### 2. Guardian Configuration

**config/config.exs**:
```elixir
config :vyaasa_campus, VyaasaCampus.Guardian,
  issuer: "vyaasa_campus",
  secret_key: System.get_env("GUARDIAN_SECRET_KEY") || "dev-guardian-secret",
  ttl: {String.to_integer(System.get_env("ACCESS_TOKEN_TTL_MINUTES") || "30"), :minutes},
  allowed_drift: 60,
  verify_issuer: true
```

### 3. Triplex Configuration

**config/config.exs**:
```elixir
config :triplex,
  repo: VyaasaCampus.Repo,
  tenant_name_prefix: "tenant_",
  tenant_migrations_path: "priv/repo/tenant_migrations"
```

## Verification Steps

### 1. Application Health Check

```bash
# Check if server starts without errors
mix phx.server

# In another terminal, test API endpoints
curl http://localhost:4000/api/health
```

### 2. Database Connectivity

```bash
# Test database connection
mix ecto.migrate

# Check if seeds ran successfully
mix run -e "IO.inspect(VyaasaCampus.Contexts.Accounts.list_platform_admins())"
```

### 3. External Services

```bash
# Test ATS service
curl -H "Authorization: Bearer $ATS_SERVICE_TOKEN" \
     $ATS_BASE_URL/health

# Test JAM service
curl -H "Authorization: Bearer $JAM_SECRET" \
     $PYTHON_BASE_URL/health
```

### 4. Authentication Flow

```bash
# Test platform admin login
curl -X POST http://localhost:4000/api/auth/platform-admin/login \
     -H "Content-Type: application/json" \
     -d '{"email": "admin@vyaasa.com", "password": "admin123"}'
```

## Troubleshooting

### Common Issues

#### 1. Database Connection Errors

**Error**: `(Postgrex.Error) FATAL: password authentication failed`

**Solution**:
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Reset PostgreSQL password
sudo -u postgres psql
ALTER USER postgres PASSWORD 'postgres';
```

#### 2. Port Already in Use

**Error**: `(PortAlreadyInUseError) port 4000 is already in use`

**Solution**:
```bash
# Find process using port 4000
lsof -i :4000

# Kill the process
kill -9 <PID>

# Or use a different port
PORT=4001 mix phx.server
```

#### 3. Asset Compilation Errors

**Error**: Node.js or npm not found

**Solution**:
```bash
# Install Node.js
nvm install 18
nvm use 18

# Clear npm cache
npm cache clean --force

# Reinstall dependencies
cd assets && rm -rf node_modules && npm install
```

#### 4. Elixir Version Issues

**Error**: `You're trying to run :vyaasa_campus on Elixir v1.14.0 but it has declared in its mix.exs file it supports only Elixir ~> 1.15`

**Solution**:
```bash
# Update Elixir
brew upgrade elixir  # macOS
# or
sudo apt-get update && sudo apt-get install elixir  # Ubuntu
```

### Debug Commands

```bash
# Check Elixir version
elixir --version

# Check PostgreSQL version
psql --version

# Check Node.js version
node --version

# Check if ports are available
netstat -tulpn | grep :4000
netstat -tulpn | grep :5432

# Check database connection
mix ecto.migrate

# Check dependencies
mix deps.get
mix deps.compile

# Check assets
cd assets && npm install
mix assets.deploy
```

## Production Setup

### 1. Environment Variables

Create production environment variables:

```bash
# Production Database
DATABASE_URL=postgresql://user:password@host:port/database

# Production Security Keys
SECRET_KEY_BASE=your-production-secret-key
GUARDIAN_SECRET_KEY=your-production-guardian-key

# Production External Services
ATS_BASE_URL=https://ats.yourdomain.com
JAM_SECRET=your-production-jam-secret

# Production File Storage
AWS_ACCESS_KEY_ID=your-production-aws-key
AWS_SECRET_ACCESS_KEY=your-production-aws-secret
AWS_BUCKET=your-production-bucket
```

### 2. Database Migration

```bash
# Run migrations in production
MIX_ENV=prod mix ecto.migrate

# Seed production data
MIX_ENV=prod mix run priv/repo/seeds.exs
```

### 3. Asset Compilation

```bash
# Compile assets for production
MIX_ENV=prod mix assets.deploy
```

### 4. Server Configuration

```bash
# Start production server
MIX_ENV=prod PORT=4000 mix phx.server
```

## Next Steps

After successful setup:

1. **Read the [API Documentation](overall_apis.md)** to understand available endpoints
2. **Review the [Database Schema](DATABASE_SCHEMA.md)** to understand data structure
3. **Check the [Testing Guide](TESTING_GUIDE.md)** for testing procedures
4. **Explore the [ATS Integration](ATS_INTEGRATION.md)** for external service setup
5. **Run the test scripts** in the `scripts/` directory to verify functionality

## Support

If you encounter issues during setup:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review the logs in `_build/dev/log/`
3. Check the [Issues](https://github.com/your-repo/issues) page
4. Create a new issue with detailed error information

## Security Notes

- **Never commit** `.env` files to version control
- **Generate new secrets** for production environments
- **Use HTTPS** in production
- **Regularly update** dependencies for security patches
- **Monitor logs** for suspicious activity
