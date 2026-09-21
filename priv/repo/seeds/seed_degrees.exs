alias VyaasaCampus.Contexts.Academics

require Logger

degrees_data = [
  {"B.Tech", "BTECH", [
    {"Computer Science & Engineering", "CSE"},
    {"Information Technology", "IT"},
    {"Electronics & Communication", "ECE"},
    {"Electrical & Electronics", "EEE"},
    {"Mechanical Engineering", "MECH"},
    {"Civil Engineering", "CIVIL"},
    {"Artificial Intelligence & ML", "AIML"},
    {"Data Science", "DS"},
    {"Cyber Security", "CYBER"}
  ]},
  {"B.E.", "BE", [
    {"Computer Science", "CS"},
    {"Information Technology", "IT"},
    {"Electronics & Telecom", "ENTC"},
    {"Mechanical", "MECH"},
    {"Civil", "CIVIL"}
  ]},
  {"BCA", "BCA", [
    {"General", "GEN"},
    {"Cloud Computing", "CLOUD"},
    {"Data Analytics", "DA"}
  ]},
  {"BBA", "BBA", [
    {"General Management", "GM"},
    {"Finance", "FIN"},
    {"Marketing", "MKT"},
    {"Human Resources", "HR"}
  ]},
  {"B.Sc", "BSC", [
    {"Computer Science", "CS"},
    {"Data Science", "DS"},
    {"Information Technology", "IT"},
    {"Mathematics", "MATH"},
    {"Physics", "PHY"},
    {"Chemistry", "CHEM"}
  ]},
  {"B.Com", "BCOM", [
    {"General", "GEN"},
    {"Accounting & Finance", "AF"},
    {"Banking & Insurance", "BI"}
  ]},
  {"BA", "BA", [
    {"Economics", "ECO"},
    {"English", "ENG"},
    {"Psychology", "PSY"}
  ]},
  {"M.Tech", "MTECH", [
    {"Computer Science & Engineering", "CSE"},
    {"Software Engineering", "SE"},
    {"Data Science", "DS"},
    {"Artificial Intelligence", "AI"},
    {"VLSI Design", "VLSI"},
    {"Cyber Security", "CYBER"}
  ]},
  {"MCA", "MCA", [
    {"General", "GEN"},
    {"Data Science", "DS"},
    {"Cloud Computing", "CLOUD"}
  ]},
  {"MBA", "MBA", [
    {"Finance", "FIN"},
    {"Marketing", "MKT"},
    {"Human Resources", "HR"},
    {"Operations", "OPS"},
    {"Business Analytics", "BA"},
    {"Information Technology", "IT"}
  ]},
  {"M.Sc", "MSC", [
    {"Computer Science", "CS"},
    {"Data Science", "DS"},
    {"Mathematics", "MATH"},
    {"Physics", "PHY"}
  ]},
  {"M.Com", "MCOM", [
    {"General", "GEN"},
    {"Accounting", "ACC"}
  ]},
  {"B.Pharm", "BPHARM", [
    {"Pharmacy", "PHAR"}
  ]},
  {"Diploma", "DIP", [
    {"Computer Engineering", "CE"},
    {"Mechanical Engineering", "ME"},
    {"Electrical Engineering", "EE"},
    {"Civil Engineering", "CIVIL"},
    {"Electronics", "EC"}
  ]}
]

Logger.info("Seeding degrees and specializations...")

{created, skipped} =
  Enum.reduce(degrees_data, {0, 0}, fn {deg_name, deg_code, specs}, {c, s} ->
    case Academics.create_degree(%{"name" => deg_name, "code" => deg_code}) do
      {:ok, degree} ->
        Logger.info("+ #{deg_name} (#{deg_code})")

        for {spec_name, spec_code} <- specs do
          case Academics.create_specialization(%{
                 "name" => spec_name,
                 "code" => spec_code,
                 "degree_id" => degree.id
               }) do
            {:ok, _} -> Logger.info("  - #{spec_name}")
            {:error, _} -> Logger.info("  ! #{spec_name} (already exists)")
          end
        end

        {c + 1, s}

      {:error, _} ->
        Logger.info("! #{deg_name} (#{deg_code}) already exists, skipping")
        {c, s + 1}
    end
  end)

Logger.info("Done! Created #{created} degrees, skipped #{skipped} (already existed).")
