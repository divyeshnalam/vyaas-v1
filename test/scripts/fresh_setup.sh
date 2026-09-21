#!/usr/bin/env bash
#
# Fresh Setup Script for VyaasaCampus
# Drops everything, recreates the DB, runs migrations, and seeds a super admin,
# reference data (degrees/specializations, industries/job roles) and the AI8
# module/dimension weights. MCQ questions are imported separately via the admin
# portal's Question Bank screen, not by this script.
#
# Usage:
#   ./scripts/fresh_setup.sh                  # uses defaults from .env
#   ./scripts/fresh_setup.sh --env production  # (future use)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Load .env if present ──────────────────────────────────────────
if [ -f .env ]; then
  # Read line by line to handle values with spaces/special chars
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Strip surrounding quotes from value
    key="${line%%=*}"
    val="${line#*=}"
    val="${val%\"}" ; val="${val#\"}"
    val="${val%\'}" ; val="${val#\'}"
    export "$key=$val"
  done < .env
  echo "[info] Loaded .env"
fi

# ── Defaults ──────────────────────────────────────────────────────
export MIX_ENV="${MIX_ENV:-dev}"
DB_NAME="${DATABASE_NAME:-vyaasa_campus_dev}"
DB_USER="${DATABASE_USERNAME:-postgres}"
DB_HOST="${DATABASE_HOST:-localhost}"

echo ""
echo "============================================"
echo "  VyaasaCampus Fresh Setup"
echo "============================================"
echo "  Environment : $MIX_ENV"
echo "  Database    : $DB_NAME"
echo "  Host        : $DB_HOST"
echo "  User        : $DB_USER"
echo "============================================"
echo ""

# ── Confirmation ──────────────────────────────────────────────────
read -rp "This will DROP the database '$DB_NAME' and start fresh. Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""

# ── Step 1: Drop database ────────────────────────────────────────
echo "[1/7] Dropping database..."
mix ecto.drop --quiet 2>/dev/null || echo "  (database did not exist, skipping)"

# ── Step 2: Create database ──────────────────────────────────────
echo "[2/7] Creating database..."
mix ecto.create --quiet

# ── Step 3: Run public schema migrations ─────────────────────────
echo "[3/7] Running public schema migrations..."
mix ecto.migrate --quiet

# ── Step 4: Seed super admin ─────────────────────────────────────
echo "[4/7] Creating super admin..."
mix run -e '
alias VyaasaCampus.Repo
alias VyaasaCampus.Schema.Platform.AdminUser

admin_email = System.get_env("ADMIN_EMAIL") || "superadmin@vyaasa.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "Admin@123"
admin_first = System.get_env("ADMIN_FIRST_NAME") || "Super"
admin_last = System.get_env("ADMIN_LAST_NAME") || "Admin"

case Repo.get_by(AdminUser, email: admin_email) do
  nil ->
    %AdminUser{}
    |> AdminUser.create_changeset(%{
      email: admin_email,
      password: admin_password,
      first_name: admin_first,
      last_name: admin_last,
      role: "superadmin",
      status: "active"
    })
    |> Repo.insert!()

    IO.puts("  Created super admin: #{admin_email}")

  _existing ->
    IO.puts("  Super admin already exists: #{admin_email}")
end
'

# ── Step 5: Seed default data ─────────────────────────────────────
echo "[5/7] Seeding degrees & specializations..."
mix run priv/repo/seeds/seed_degrees.exs --quiet 2>/dev/null || mix run priv/repo/seeds/seed_degrees.exs

echo "[6/7] Seeding industries & job roles..."
mix run priv/repo/seeds/seed_industries_and_job_roles.exs --quiet 2>/dev/null || mix run priv/repo/seeds/seed_industries_and_job_roles.exs

# ── Step 7: Seed AI8 config ───────────────────────────────────────
# Without this, ai8_module_dimensions / ai8_dimension_weights are empty on a
# fresh environment, so every AI8 roll-up silently falls back to an equal-weight
# average instead of the tuned production weights. Idempotent — safe to re-run.
echo "[7/7] Seeding AI8 module/dimension weights..."
mix run -e "VyaasaCampus.Contexts.AI8.seed_config()"

# ── Summary ────────────────────────────────────────────────────────
ADMIN_EMAIL="${ADMIN_EMAIL:-superadmin@vyaasa.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Admin@123}"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Super Admin Credentials:"
echo "    Email    : $ADMIN_EMAIL"
echo "    Password : $ADMIN_PASSWORD"
echo ""
echo "  Start the server:"
echo "    mix phx.server"
echo ""
echo "  Login at:"
echo "    http://localhost:4000/admin/login"
echo ""
echo "============================================"
