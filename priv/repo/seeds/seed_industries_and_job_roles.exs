alias VyaasaCampus.Contexts.Jobs
require Logger

industries_data = [
  {"Information Technology", "IT", "hero-computer-desktop", [
    {"Software Developer", "entry", ["Java", "Python", "JavaScript", "Git", "SQL"]},
    {"Frontend Developer", "entry", ["React", "Angular", "Vue.js", "HTML", "CSS", "JavaScript"]},
    {"Backend Developer", "entry", ["Node.js", "Python", "Java", "REST APIs", "SQL", "NoSQL"]},
    {"Full Stack Developer", "mid", ["React", "Node.js", "Python", "SQL", "Docker", "Git"]},
    {"Mobile App Developer", "entry", ["Flutter", "React Native", "Swift", "Kotlin"]},
    {"DevOps Engineer", "mid", ["Docker", "Kubernetes", "AWS", "CI/CD", "Linux", "Terraform"]},
    {"Cloud Engineer", "mid", ["AWS", "Azure", "GCP", "Docker", "Kubernetes", "Networking"]},
    {"QA Engineer", "entry", ["Selenium", "Manual Testing", "Automation", "JIRA", "API Testing"]},
    {"Site Reliability Engineer", "senior", ["Linux", "Monitoring", "Kubernetes", "Python", "Incident Management"]},
    {"Technical Support Engineer", "entry", ["Troubleshooting", "Networking", "Linux", "Communication"]}
  ]},
  {"Data Science & Analytics", "DS", "hero-chart-bar", [
    {"Data Analyst", "entry", ["SQL", "Excel", "Python", "Power BI", "Tableau", "Statistics"]},
    {"Data Scientist", "mid", ["Python", "Machine Learning", "Statistics", "SQL", "TensorFlow", "R"]},
    {"Data Engineer", "mid", ["Python", "SQL", "Spark", "Airflow", "ETL", "AWS"]},
    {"ML Engineer", "mid", ["Python", "TensorFlow", "PyTorch", "MLOps", "Docker", "Statistics"]},
    {"Business Intelligence Analyst", "entry", ["SQL", "Power BI", "Tableau", "Excel", "Data Modeling"]},
    {"AI Research Scientist", "senior", ["Deep Learning", "NLP", "Computer Vision", "Python", "Research"]}
  ]},
  {"Cybersecurity", "CYBER", "hero-shield-check", [
    {"Security Analyst", "entry", ["SIEM", "Firewalls", "Incident Response", "Networking", "Linux"]},
    {"Penetration Tester", "mid", ["Kali Linux", "Burp Suite", "OWASP", "Networking", "Python"]},
    {"SOC Analyst", "entry", ["SIEM", "Log Analysis", "Incident Response", "Networking"]},
    {"Security Engineer", "mid", ["Cloud Security", "IAM", "Encryption", "DevSecOps", "Python"]},
    {"Cybersecurity Consultant", "senior", ["Risk Assessment", "Compliance", "NIST", "ISO 27001"]}
  ]},
  {"Finance & Banking", "FIN", "hero-banknotes", [
    {"Financial Analyst", "entry", ["Excel", "Financial Modeling", "Accounting", "SQL", "Power BI"]},
    {"Investment Banking Analyst", "entry", ["Financial Modeling", "Valuation", "Excel", "PowerPoint"]},
    {"Risk Analyst", "entry", ["Risk Modeling", "Statistics", "Excel", "SQL", "Compliance"]},
    {"Accountant", "entry", ["Tally", "Excel", "GST", "Taxation", "Accounting Standards"]},
    {"Auditor", "mid", ["Audit", "Compliance", "Accounting Standards", "Excel", "SAP"]},
    {"Wealth Manager", "mid", ["Portfolio Management", "Financial Planning", "Mutual Funds", "Insurance"]}
  ]},
  {"Marketing & Advertising", "MKT", "hero-megaphone", [
    {"Digital Marketing Executive", "entry", ["SEO", "SEM", "Google Ads", "Social Media", "Analytics"]},
    {"Content Writer", "entry", ["Content Writing", "SEO", "Blogging", "Social Media", "Research"]},
    {"Social Media Manager", "entry", ["Social Media", "Content Creation", "Analytics", "Canva"]},
    {"Marketing Analyst", "mid", ["Google Analytics", "SQL", "Excel", "A/B Testing", "Campaign Analysis"]},
    {"Brand Manager", "mid", ["Brand Strategy", "Marketing", "Consumer Insights", "Campaign Management"]},
    {"SEO Specialist", "entry", ["SEO", "Google Analytics", "Keyword Research", "Content Optimization"]}
  ]},
  {"Human Resources", "HR", "hero-user-group", [
    {"HR Executive", "entry", ["Recruitment", "Onboarding", "HRMS", "Payroll", "Communication"]},
    {"Recruiter", "entry", ["Sourcing", "Screening", "Interviewing", "ATS", "LinkedIn"]},
    {"HR Business Partner", "mid", ["Employee Relations", "Performance Management", "Strategy", "Compliance"]},
    {"Training & Development Specialist", "mid", ["L&D", "Training Design", "Facilitation", "LMS"]}
  ]},
  {"Sales & Business Development", "SALES", "hero-presentation-chart-line", [
    {"Sales Executive", "entry", ["CRM", "Cold Calling", "Negotiation", "Communication", "Lead Generation"]},
    {"Business Development Executive", "entry", ["Lead Generation", "CRM", "Market Research", "Communication"]},
    {"Account Manager", "mid", ["Client Management", "Upselling", "CRM", "Negotiation"]},
    {"Sales Manager", "senior", ["Team Management", "Strategy", "Revenue Planning", "CRM"]}
  ]},
  {"Design & Creative", "DESIGN", "hero-paint-brush", [
    {"UI/UX Designer", "entry", ["Figma", "Adobe XD", "Wireframing", "Prototyping", "User Research"]},
    {"Graphic Designer", "entry", ["Photoshop", "Illustrator", "Canva", "Typography", "Branding"]},
    {"Product Designer", "mid", ["Figma", "Design Systems", "User Research", "Prototyping", "A/B Testing"]},
    {"Motion Graphics Designer", "mid", ["After Effects", "Premiere Pro", "Animation", "Video Editing"]}
  ]},
  {"Healthcare & Pharma", "HEALTH", "hero-heart", [
    {"Clinical Research Associate", "entry", ["GCP", "Clinical Trials", "Documentation", "Regulatory"]},
    {"Medical Representative", "entry", ["Pharma Sales", "Product Knowledge", "Communication", "CRM"]},
    {"Healthcare Administrator", "mid", ["Hospital Management", "Compliance", "EHR", "Operations"]},
    {"Pharmacist", "entry", ["Drug Dispensing", "Pharmacy Management", "Patient Counseling"]}
  ]},
  {"Manufacturing & Operations", "MFG", "hero-cog-6-tooth", [
    {"Production Engineer", "entry", ["Manufacturing", "Quality Control", "Lean", "AutoCAD"]},
    {"Quality Assurance Engineer", "entry", ["ISO", "Six Sigma", "Quality Testing", "Documentation"]},
    {"Supply Chain Analyst", "entry", ["Logistics", "Inventory Management", "Excel", "ERP", "SAP"]},
    {"Operations Manager", "senior", ["Operations", "Team Management", "Process Optimization", "ERP"]}
  ]},
  {"Education & Training", "EDU", "hero-academic-cap", [
    {"Teacher / Lecturer", "entry", ["Subject Expertise", "Pedagogy", "Communication", "Classroom Management"]},
    {"Instructional Designer", "mid", ["LMS", "E-Learning", "Content Design", "Articulate", "Storyline"]},
    {"Academic Counselor", "entry", ["Career Guidance", "Communication", "Student Assessment"]},
    {"EdTech Product Manager", "mid", ["Product Management", "EdTech", "Agile", "User Research"]}
  ]},
  {"Media & Communication", "MEDIA", "hero-film", [
    {"Journalist", "entry", ["Writing", "Reporting", "Research", "Interviewing", "AP Style"]},
    {"Public Relations Executive", "entry", ["PR", "Media Relations", "Writing", "Event Management"]},
    {"Video Editor", "entry", ["Premiere Pro", "Final Cut", "After Effects", "Color Grading"]},
    {"Corporate Communications Manager", "mid", ["Internal Comms", "Strategy", "Writing", "Branding"]}
  ]},
  {"Consulting", "CONSULT", "hero-light-bulb", [
    {"Management Consultant", "entry", ["Problem Solving", "Data Analysis", "PowerPoint", "Excel", "Research"]},
    {"Strategy Analyst", "entry", ["Market Research", "Financial Modeling", "Excel", "PowerPoint"]},
    {"IT Consultant", "mid", ["ERP", "Digital Transformation", "Business Analysis", "Communication"]}
  ]},
  {"Legal", "LEGAL", "hero-scale", [
    {"Legal Associate", "entry", ["Contract Drafting", "Legal Research", "Compliance", "Corporate Law"]},
    {"Compliance Officer", "mid", ["Regulatory Compliance", "Risk Management", "Audit", "Documentation"]},
    {"Paralegal", "entry", ["Legal Research", "Documentation", "Filing", "Case Management"]}
  ]},
  {"Government & Public Sector", "GOVT", "hero-building-library", [
    {"Civil Services Officer", "entry", ["Public Administration", "Policy", "Communication", "Leadership"]},
    {"Public Policy Analyst", "mid", ["Policy Research", "Data Analysis", "Report Writing", "Government"]},
    {"Defense Services", "entry", ["Physical Fitness", "Leadership", "Discipline", "Communication"]}
  ]}
]

Logger.info("Seeding industries and job roles...")

{industries_created, roles_created, skipped} =
  Enum.reduce(industries_data, {0, 0, 0}, fn {name, code, icon, roles}, {ic, rc, sk} ->
    case Jobs.create_industry(%{"name" => name, "code" => code, "icon" => icon}) do
      {:ok, industry} ->
        Logger.info("+ #{name} (#{code})")

        new_roles =
          Enum.reduce(roles, 0, fn {title, exp_level, skills}, count ->
            case Jobs.create_job_role(%{
                   "title" => title,
                   "experience_level" => exp_level,
                   "skills" => skills,
                   "industry_id" => industry.id
                 }) do
              {:ok, _} ->
                Logger.info("  - #{title} [#{exp_level}]")
                count + 1

              {:error, _} ->
                Logger.info("  ! #{title} (already exists)")
                count
            end
          end)

        {ic + 1, rc + new_roles, sk}

      {:error, _} ->
        Logger.info("! #{name} already exists, skipping")
        {ic, rc, sk + 1}
    end
  end)

Logger.info("Done! Created #{industries_created} industries, #{roles_created} job roles. Skipped #{skipped} existing industries.")
