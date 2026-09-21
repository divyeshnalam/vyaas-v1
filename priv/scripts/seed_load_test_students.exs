# Seeds dummy, ready-to-use students into a college (tenant) for load testing,
# writes a CSV of their credentials, and emails that CSV to the admin.
#
# Students are created as VERIFIED + ACTIVE (approved) so they can log in and
# hit the app immediately — WITHOUT the invite/email flow (no per-student
# emails). Every student shares one password (hashed once for speed).
#
#   Usage:
#     mix run priv/scripts/seed_load_test_students.exs [TENANT_ALIAS] [COUNT] [PASSWORD] [ADMIN_EMAIL]
#
#   Examples:
#     mix run priv/scripts/seed_load_test_students.exs Bites 500
#     mix run priv/scripts/seed_load_test_students.exs Bites 1000 "Load@123" ops@college.edu
#
# The CSV is also saved to priv/scripts/output/. Cleanup a batch later with:
#   DELETE FROM <schema>.students WHERE email LIKE 'loadtest_%';

require Logger
import Ecto.Query
import VyaasaCampus.Types

alias VyaasaCampus.Repo
alias VyaasaCampus.Contexts.Tenants
alias VyaasaCampus.Schema.Students.Student
alias VyaasaCampus.Schema.Students.StudentAtsPhase
alias VyaasaCampus.Schema.Accounts.User

args = System.argv()
tenant_alias = Enum.at(args, 0) || "Bites"
count = (Enum.at(args, 1) || "500") |> String.to_integer()
password = Enum.at(args, 2) || "LoadTest@123"
admin_email_arg = Enum.at(args, 3)

tenant =
  case Tenants.get_tenant_by_alias(tenant_alias) do
    nil ->
      available = Tenants.list_tenants() |> Enum.map(& &1.alias) |> Enum.join(", ")
      IO.puts("No tenant/college found for alias #{inspect(tenant_alias)}.")
      IO.puts("Available aliases: #{available}")
      System.halt(1)

    t ->
      t
  end

prefix = tenant.schema_name

# Creator / approver: a real admin user in the tenant when one exists.
admin_user =
  Repo.one(
    from(u in User, where: u.role in ["admin", "faculty"], order_by: u.inserted_at, limit: 1),
    prefix: prefix
  )

creator_id = if admin_user, do: admin_user.id, else: Ecto.UUID.generate()

# Where the credentials CSV is emailed. Static default; override with the 4th arg.
admin_email = admin_email_arg || "ravikiran.j@beamx.co"

encrypted = Bcrypt.hash_pwd_salt(password)
batch = System.system_time(:second) |> rem(1_000_000) |> Integer.to_string()
now = DateTime.utc_now() |> DateTime.truncate(:second)

# IT / developer job roles to assign at random as each student's preferred role
# (matches real public.job_roles titles, so role-aware selection can resolve).
it_roles =
  Repo.query!("""
  SELECT jr.title FROM public.job_roles jr
  JOIN public.industries i ON i.id = jr.industry_id
  WHERE jr.is_active = true AND lower(i.name) = 'information technology'
  ORDER BY jr.title
  """).rows
  |> List.flatten()

it_roles = if it_roles == [], do: ["Software Developer"], else: it_roles

IO.puts("Seeding #{count} verified students into '#{tenant.full_name}' (#{prefix}) …")
IO.puts("Preferred roles pool (#{length(it_roles)}): #{Enum.join(it_roles, ", ")}")

{created, ok, failed} =
  Enum.reduce(1..count, {[], 0, 0}, fn i, {acc, ok, failed} ->
    n = String.pad_leading(Integer.to_string(i), 4, "0")
    email = "loadtest_#{batch}_#{n}@example.com"

    attrs = %{
      email: email,
      encrypted_password: encrypted,
      first_name: "Load",
      last_name: "Test#{n}",
      phone: "9#{String.pad_leading(Integer.to_string(i), 9, "0")}",
      registration_id: "LT#{batch}#{n}",
      degree: "B.Tech",
      specialization: "Computer Science",
      year_of_passing: 2026,
      cgpa: Decimal.new("8.0"),
      current_academic_year: "4",
      # Verified + active (approved), so no manual verification is needed.
      status: student_status_active(),
      profile_completed: true,
      email_verified_at: now,
      profile_submitted_at: now,
      profile_approved_at: now,
      profile_reviewed_at: now,
      approved_by_id: creator_id,
      tenant_id: tenant.id,
      created_by_id: creator_id,
      created_by_type: creator_type_tenant()
    }

    case %Student{} |> Student.changeset(attrs) |> Repo.insert(prefix: prefix) do
      {:ok, s} ->
        role = Enum.random(it_roles)

        # Attach an ATS phase carrying the preferred role (read by role-aware MCQ
        # selection + resume/AI8 screens). resume_url is required, so placeholder.
        %StudentAtsPhase{}
        |> StudentAtsPhase.changeset(%{
          student_id: s.id,
          tenant_id: tenant.id,
          resume_url: "loadtest://no-resume",
          preferred_role: role,
          status: "completed",
          processed_at: now,
          ats_score: Decimal.new(Integer.to_string(Enum.random(60..92)))
        })
        |> Repo.insert(prefix: prefix)

        if rem(i, 50) == 0, do: IO.puts("  … #{i}/#{count}")

        row = {s.email, password, s.first_name <> " " <> s.last_name, s.registration_id, role}
        {[row | acc], ok + 1, failed}

      {:error, changeset} ->
        if failed < 5, do: IO.puts("  ✗ row #{i} failed: #{inspect(changeset.errors)}")
        {acc, ok, failed + 1}
    end
  end)

# ── Build the credentials CSV ───────────────────────────────────────────────
csv_rows =
  created
  |> Enum.reverse()
  |> Enum.map(fn {email, pw, name, reg, role} ->
    ~s("#{name}","#{reg}","#{role}","#{email}","#{pw}")
  end)

csv = "name,registration_id,preferred_role,email,password\n" <> Enum.join(csv_rows, "\n") <> "\n"

out_dir = Path.join(["priv", "scripts", "output"])
File.mkdir_p!(out_dir)
filename = "load_test_students_#{tenant.alias}_#{batch}.csv"
out_path = Path.join(out_dir, filename)
File.write!(out_path, csv)

# ── Email the CSV to the admin ──────────────────────────────────────────────
from_email = Application.get_env(:vyaasa_campus, :smtp_from_email, "noreply@vyaasa.com")

mail =
  Swoosh.Email.new()
  |> Swoosh.Email.to(admin_email)
  |> Swoosh.Email.from({"VyaasaCampus", from_email})
  |> Swoosh.Email.subject("Load-test student credentials — #{tenant.full_name} (#{ok} accounts)")
  |> Swoosh.Email.text_body("""
  Hi,

  #{ok} verified test students were created in #{tenant.full_name} for load testing.
  Their login credentials are attached as a CSV (name, registration_id, email, password).

  All accounts share the password: #{password}
  Emails run: loadtest_#{batch}_0001@example.com … loadtest_#{batch}_#{String.pad_leading(Integer.to_string(count), 4, "0")}@example.com

  To remove them afterwards:
    DELETE FROM #{prefix}.students WHERE email LIKE 'loadtest_%';

  — VyaasaCampus
  """)
  |> Swoosh.Email.attachment(
    Swoosh.Attachment.new({:data, csv}, filename: filename, content_type: "text/csv")
  )

mail_result = VyaasaCampus.Mailer.deliver(mail)
adapter = Application.get_env(:vyaasa_campus, VyaasaCampus.Mailer)[:adapter]

IO.puts("""

Done. Created #{ok}, failed #{failed}.
────────────────────────────────────────────────
Tenant/college : #{tenant.full_name} (#{tenant.alias})
Password (all) : #{password}
CSV saved to   : #{out_path}
Emailed to     : #{admin_email}  (result: #{inspect(mail_result)})
Mail adapter   : #{inspect(adapter)}#{if adapter == Swoosh.Adapters.Local, do: "  ← DEV: preview at /dev/mailbox, not actually sent", else: ""}
Cleanup        : DELETE FROM #{prefix}.students WHERE email LIKE 'loadtest_%';
────────────────────────────────────────────────
""")
