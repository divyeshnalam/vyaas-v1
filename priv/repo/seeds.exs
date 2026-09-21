alias VyaasaCampus.Repo
alias VyaasaCampus.Schema.Platform.AdminUser
import Bcrypt, only: [hash_pwd_salt: 1]
require Logger

admin_attrs_1 = %{
  email: "admin@vyaasa.com",
  encrypted_password: hash_pwd_salt("admin123"),
  first_name: "Admin",
  last_name: "User",
  role: "superadmin",
  status: "active"
}

admin_attrs_2 = %{
  email: "superadmin@vyaasa.com",
  encrypted_password: hash_pwd_salt("superadmin123"),
  first_name: "Super",
  last_name: "Admin",
  role: "superadmin",
  status: "active"
}

case Repo.get_by(AdminUser, email: "admin@vyaasa.com") do
  nil -> AdminUser.changeset(%AdminUser{}, admin_attrs_1) |> Repo.insert!()
  _ -> Logger.info("Admin user already exists")
end

case Repo.get_by(AdminUser, email: "superadmin@vyaasa.com") do
  nil -> AdminUser.changeset(%AdminUser{}, admin_attrs_2) |> Repo.insert!()
  _ -> Logger.info("Super admin user already exists")
end

Logger.info("✅ Seeded superadmins:")
Logger.info("   📧 admin@vyaasa.com (password: admin123)")
Logger.info("   📧 SuperAdmin@vyaasa.com (password: superadmin123)")
