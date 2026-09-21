# Tenant-specific seeds for job profiles
# This file should be executed in the context of each tenant

alias VyaasaCampus.Repo
alias VyaasaCampus.Schema.Tenants.JobProfile
alias VyaasaCampus.Schema.Tenants.Tenant
import Ecto.Query
require Logger

# Get the current tenant_id from environment or context
# In a real scenario, this would be passed or determined from the tenant context
tenant_id = System.get_env("TENANT_ID") || "80bf9aff-0f63-4a14-8e54-1929e695151c"

# Get the tenant schema name
tenant = Repo.get(Tenant, tenant_id)
schema_name = if tenant, do: tenant.schema_name, else: "tenant_klu"

Logger.info("🌱 Seeding job profiles for tenant: #{tenant_id} in schema: #{schema_name}")

job_profiles_data = [
  %{
    role: "data scientist",
    profile_text: """
---
**Role Summary:** Data Scientist responsible for extracting insights from complex data sets to inform business decisions.

**Core Technical Skills:**
Python, SQL, R, Machine Learning, Data Mining, Data Visualization, Statistics, Mathematics

**Key Responsibilities & Experience:**
Data Analysis, Data Modeling, Predictive Analytics, Data Storytelling, Statistical Inference

**Essential Tools:**
Git, Jupyter Notebook, Tableau, Apache Spark, Hadoop

**Appreciated Skills & Knowledge:**
Deep Learning, Natural Language Processing, Cloud Computing, Data Engineering, Data Warehousing

**Educational Background:**
Bachelors/Masters in Computer Science, Data Science, Statistics, Mathematics, Economics
"""
  },
  %{
    role: "ui ux designer",
    profile_text: """
---
**Role Summary:** UI UX Designer responsible for creating user-centered design solutions.

**Core Technical Skills:**
Sketch, Figma, Adobe XD, InVision, User Research, Wireframing, Prototyping, Interaction Design

**Key Responsibilities & Experience:**
User Interviews, Usability Testing, User Journey Mapping, Design Systems, Visual Design, Front-end Development, Design Tools

**Essential Tools:**
Figma Plugins, Sketch Libraries, Adobe Creative Cloud, InVision Design System, Zeplin

**Appreciated Skills & Knowledge:**
UI Kit, Design Language System, Accessibility Guidelines, Human-centered Design, Service Design, Design Thinking, Agile Methodology

**Educational Background:**
Bachelors/Masters in Design, Human-computer Interaction, Visual Communication, Graphic Design
"""
  },
  %{
    role: "marketing intern",
    profile_text: """
---
**Role Summary:** Marketing Intern responsible for assisting in the development and implementation of marketing campaigns.

**Core Technical Skills:**
Digital Marketing, SEO, Google Analytics, Social Media Marketing, Email Marketing, Content Creation

**Key Responsibilities & Experience:**
Marketing Research, Campaign Analysis, Brand Management, Event Planning, Content Writing, Social Media Management

**Essential Tools:**
Adobe Creative Cloud, Hootsuite, Mailchimp, Google Ads, Facebook Ads Manager

**Appreciated Skills & Knowledge:**
Data Visualization, Marketing Automation, CRM Software, Market Research, Brand Strategy

**Educational Background:**
Bachelors/Masters in Marketing, Business Administration, Communications, Public Relations
"""
  },
  %{
    role: "sales intern",
    profile_text: """
---
**Role Summary:** Sales Intern responsible for assisting in sales operations and contributing to business growth.

**Core Technical Skills:**
Microsoft Office, Google Suite, CRM Software, Data Analysis, Market Research

**Key Responsibilities & Experience:**
Sales Forecasting, Market Analysis, Customer Relationship Building, Sales Strategy Development, Team Collaboration

**Essential Tools:**
Salesforce, HubSpot, LinkedIn Sales Navigator, Excel, PowerPoint

**Appreciated Skills & Knowledge:**
Digital Marketing, Social Media Marketing, Email Marketing, Sales Automation, Data Visualization

**Educational Background:**
Bachelors/Masters in Business Administration, Marketing, Economics, Finance
"""
  },
  %{
    role: "ruby on rails developer",
    profile_text: """
---
**Role Summary:** A Ruby on Rails developer responsible for designing, developing, and deploying scalable web applications.

**Core Technical Skills:**
Ruby, Rails, SQL, HTML, CSS, JavaScript, RESTful API, MVC Pattern

**Key Responsibilities & Experience:**
Ruby on Rails Development, Web Application Development, Database Design, API Integration, Front-end Development

**Essential Tools:**
Git, RubyMine, Visual Studio Code, Heroku, PostgreSQL

**Appreciated Skills & Knowledge:**
RSpec, Capybara, Selenium, Docker, Kubernetes, Agile Methodology

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Web Development, Information Technology
"""
  },
  %{
    role: "java developer",
    profile_text: """
---
**Role Summary:** Java Developer responsible for designing, developing, and testing Java-based applications.

**Core Technical Skills:**
Java, Object-Oriented Programming, Data Structures, Algorithms, Design Patterns, Spring Framework, Hibernate

**Key Responsibilities & Experience:**
Java Application Development, API Design, Database Integration, Unit Testing, Integration Testing, Code Review

**Essential Tools:**
Eclipse, IntelliJ IDEA, Maven, Gradle, Git, SVN

**Appreciated Skills & Knowledge:**
Java 8 Features, Java EE, Microservices Architecture, Containerization, Cloud Computing, DevOps

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Information Technology
"""
  },
  %{
    role: "data scientist intern",
    profile_text: """
---
**Role Summary:** Data analysis, modeling, and interpretation for business decision-making.

**Core Technical Skills:**
Python, SQL, R, Machine Learning, Data Mining, Data Visualization, Statistics, Mathematics

**Key Responsibilities & Experience:**
Data Cleaning, Feature Engineering, Model Training, A/B Testing, Statistical Analysis, Data Storytelling

**Essential Tools:**
Git, Jupyter Notebook, Tableau, AWS SageMaker, Docker, Linux

**Appreciated Skills & Knowledge:**
PyTorch, TensorFlow, Cloud Computing, MLOps, CI/CD, Data Engineering, Big Data

**Educational Background:**
Bachelors/Masters Computer Science, Data Science, Statistics, Mathematics, Data Analytics
"""
  },
  %{
    role: "genai engineer",
    profile_text: """
---
**Role Summary:** GENAI Engineer designs, develops, and deploys artificial intelligence and machine learning models to drive business growth and innovation.

**Core Technical Skills:**
Python, Java, C++, SQL, R, TensorFlow, PyTorch, Keras, Scikit-learn, Pandas, NumPy, Data Visualization

**Key Responsibilities & Experience:**
Data Preprocessing, Model Development, Model Deployment, Model Monitoring, Explainable AI, Fairness and Bias Detection

**Essential Tools:**
Git, Jupyter Notebook, Tableau, AWS SageMaker, Docker, Kubernetes, TensorFlow Serving

**Appreciated Skills & Knowledge:**
Cloud Computing, MLOps, CI/CD, DevOps, Data Engineering, Natural Language Processing, Computer Vision

**Educational Background:**
Bachelors/Masters in Computer Science, Artificial Intelligence, Machine Learning, Data Science, Statistics, Mathematics, Electrical Engineering
"""
  },
  %{
    role: "embedded developer",
    profile_text: """
---
**Role Summary:** Embedded system development, firmware creation, and hardware-software integration.

**Core Technical Skills:**
C, C++, Assembly, Embedded Linux, Microcontrollers, ARM, FPGA, VHDL, Verilog

**Key Responsibilities & Experience:**
Firmware Development, Embedded System Design, Hardware Debugging, Low-Level Programming, Real-Time Operating Systems

**Essential Tools:**
Keil, IAR, GCC, Eclipse, Git, JTAG, In-Circuit Emulator

**Appreciated Skills & Knowledge:**
Rust, Embedded Operating Systems, Device Drivers, Power Management, Thermal Management, Safety Standards

**Educational Background:**
Bachelors/Masters in Computer Science, Electrical Engineering, Electronics Engineering, Computer Engineering
"""
  },
  %{
    role: "ui/ux designer",
    profile_text: """
---
**Role Summary:** A UI/UX Designer creates user-centered design solutions for digital products.

**Core Technical Skills:**
Figma, Sketch, Adobe Creative Suite, User Research, Wireframing, Prototyping, Interaction Design

**Key Responsibilities & Experience:**
User Interviews, Usability Testing, Heuristic Evaluation, Design Systems, Visual Design, Front-end Development

**Essential Tools:**
InVision, Axure, Adobe XD, Figma Plugins, Sketch Libraries

**Appreciated Skills & Knowledge:**
UI Kit, Style Guide, Accessibility Guidelines, Human-Computer Interaction, Design Thinking, Agile Methodology

**Educational Background:**
Bachelors/Masters in Design, Human-Computer Interaction, Visual Communication, Graphic Design
"""
  },
  %{
    role: "devops engineer",
    profile_text: """
---
**Role Summary:** DevOps Engineer responsible for ensuring smooth operation and deployment of software systems.

**Core Technical Skills:**
Linux, Python, Java, C++, Cloud Computing, Containerization, Orchestration

**Key Responsibilities & Experience:**
Infrastructure as Code, Continuous Integration, Continuous Deployment, Monitoring, Logging, Troubleshooting

**Essential Tools:**
Docker, Kubernetes, Jenkins, Git, Ansible, Puppet

**Appreciated Skills & Knowledge:**
Cloud Providers, Serverless Computing, Microservices Architecture, DevOps Tools, Agile Methodologies

**Educational Background:**
Bachelors/Masters in Computer Science, Information Technology, Software Engineering, Networking
"""
  },
  %{
    role: "talent acquisation - ta",
    profile_text: """
---
**Role Summary:** Talent Acquisition Specialist responsible for identifying, attracting, and hiring top talent.

**Core Technical Skills:**
Excel, Google Sheets, Microsoft Office, LinkedIn Recruiter, Workday, ATS Systems

**Key Responsibilities & Experience:**
Job Description Writing, Resume Screening, Interview Scheduling, Candidate Communication, Talent Pipeline Management

**Essential Tools:**
Trello, Asana, Zoom, Google Meet, Email Marketing Software

**Appreciated Skills & Knowledge:**
Recruitment Marketing, Employer Branding, Diversity and Inclusion, Behavioral Interviewing, Data-Driven Decision Making

**Educational Background:**
Bachelors/Masters in Human Resources, Business Administration, Industrial Relations, Psychology
"""
  },
  %{
    role: "talent acquisation intern",
    profile_text: """
---
**Role Summary:** Talent Acquisition Intern responsible for assisting in the recruitment process and developing skills in talent management.

**Core Technical Skills:**
Excel, Microsoft Office, Google Suite, Data Analysis, SQL, Python, R, Tableau, Power BI

**Key Responsibilities & Experience:**
Recruitment Process, Talent Management, Sourcing Candidates, Interview Scheduling, Resume Screening, Social Media Marketing

**Essential Tools:**
LinkedIn Recruiter, Workday, Google Drive, Microsoft Teams, Zoom

**Appreciated Skills & Knowledge:**
ATS Systems, Recruitment Software, HRIS, Diversity and Inclusion, Employer Branding, Digital Marketing

**Educational Background:**
Bachelors/Masters in Human Resources, Business Administration, Marketing, Communications
"""
  },
  %{
    role: "project manager",
    profile_text: """
---
**Role Summary:** Project Manager oversees project planning, execution, and delivery to ensure timely completion within budget and scope.

**Core Technical Skills:**
Agile Methodology, Scrum Framework, Waterfall Methodology, Project Management Tools, MS Project, Asana, Trello, Jira

**Key Responsibilities & Experience:**
Project Planning, Resource Allocation, Risk Management, Budgeting, Scheduling, Team Leadership, Stakeholder Management

**Essential Tools:**
Microsoft Office, Google Workspace, Slack, Zoom, Basecamp, Gantt Charts

**Appreciated Skills & Knowledge:**
Lean Six Sigma, PMP Certification, Agile Certifications, Project Management Office, Business Analysis, Communication Skills

**Educational Background:**
Bachelors/Masters in Business Administration, Project Management, Operations Management, Engineering Management
"""
  },
  %{
    role: "python developer",
    profile_text: """
---
**Role Summary:** A Python Developer is responsible for designing, developing, and maintaining software applications using Python.

**Core Technical Skills:**
Python, Object-Oriented Programming, Data Structures, Algorithms, SQL, NoSQL, RESTful APIs

**Key Responsibilities & Experience:**
Data Analysis, Data Visualization, Web Scraping, API Integration, Unit Testing, Integration Testing

**Essential Tools:**
Git, Jupyter Notebook, PyCharm, Visual Studio Code, Docker, Kubernetes

**Appreciated Skills & Knowledge:**
Flask, Django, FastAPI, Cloud Computing, DevOps, Agile Methodologies

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Information Technology, Mathematics
"""
  },
  %{
    role: "full stack developer",
    profile_text: """
---
**Role Summary:** Full Stack Developer responsible for designing, developing, and deploying scalable, efficient, and secure web applications.

**Core Technical Skills:**
JavaScript, HTML, CSS, React, Angular, Vue.js, Node.js, Express.js, Ruby on Rails, Django, Flask, MySQL, PostgreSQL, MongoDB, Redis

**Key Responsibilities & Experience:**
Front-end Development, Back-end Development, API Integration, Database Management, Version Control, Agile Methodologies, Scrum

**Essential Tools:**
Git, Visual Studio Code, IntelliJ IDEA, Postman, Docker, Kubernetes, Jenkins, CircleCI

**Appreciated Skills & Knowledge:**
TypeScript, GraphQL, WebSockets, Socket.io, Microservices Architecture, Containerization, Cloud Deployment, DevOps

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Information Technology, Web Development
"""
  },
  %{
    role: "project coordinator",
    profile_text: """
---
**Role Summary:** Project Coordinator responsible for facilitating project execution and ensuring timely delivery.

**Core Technical Skills:**
Microsoft Office, Google Workspace, Project Management Tools, Agile Methodologies, Scrum Framework, Kanban Board

**Key Responsibilities & Experience:**
Project Planning, Resource Allocation, Stakeholder Management, Risk Assessment, Budgeting, Scheduling, Time Management

**Essential Tools:**
Trello, Asana, Basecamp, MS Project, Jira, Gantt Charts

**Appreciated Skills & Knowledge:**
Waterfall Methodologies, Six Sigma, Lean Project Management, Business Analysis, Communication Planning, Conflict Resolution

**Educational Background:**
Bachelors/Masters in Business Administration, Project Management, Operations Management, Supply Chain Management, Business Analytics
"""
  },
  %{
    role: "senior qa automation engineer",
    profile_text: """
---
**Role Summary:** Design, develop, and maintain automated testing frameworks to ensure high-quality software releases.

**Core Technical Skills:**
Java, Python, C++, Selenium, Appium, TestNG, JUnit, Cucumber, Git, Jenkins

**Key Responsibilities & Experience:**
API Testing, UI Testing, Test Automation Frameworks, Continuous Integration, Continuous Deployment, Test Data Management, Test Environment Management

**Essential Tools:**
Jenkins, Git, Docker, Kubernetes, Selenium Grid, Appium Studio

**Appreciated Skills & Knowledge:**
Behavior-Driven Development, Test-Driven Development, Agile Methodologies, Scrum, Kanban, DevOps, Cloud Platforms, Containerization

**Educational Background:**
Bachelors/Masters in Computer Science, Software Engineering, Information Technology, Engineering
"""
  },
  %{
    role: "msd365 crm developer",
    profile_text: """
---
**Role Summary:** Develop and implement Microsoft Dynamics 365 CRM solutions.

**Core Technical Skills:**
C#, .NET, ASP.NET, JavaScript, HTML, CSS, SQL, Azure, Dynamics 365, Power Apps, Power Automate

**Key Responsibilities & Experience:**
Entity Customization, Business Process Flows, Data Migration, Integration with External Systems, Dynamics 365 Security

**Essential Tools:**
Visual Studio, Dynamics 365 Developer Toolkit, Azure DevOps, Git, Power Platform

**Appreciated Skills & Knowledge:**
Power BI, Power Automate, Azure Functions, Machine Learning, AI Builder, Dynamics 365 Portal

**Educational Background:**
Bachelors/Masters in Computer Science, Information Technology, Business Administration, or related fields.
"""
  },
  %{
    role: "react developer intern",
    profile_text: """
---
**Role Summary:** A React Developer Intern is responsible for assisting in the development and maintenance of front-end applications using React.

**Core Technical Skills:**
JavaScript, HTML, CSS, React, JSX, TypeScript, ES6, Webpack, Babel

**Key Responsibilities & Experience:**
Front-end Development, UI/UX Design, State Management, React Hooks, Component-Based Architecture, Code Optimization

**Essential Tools:**
Visual Studio Code, Git, GitHub, npm, yarn, Webpack, Babel

**Appreciated Skills & Knowledge:**
Redux, MobX, React Query, Storybook, Jest, Enzyme, Code Splitting, Webpack Loaders

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Web Development, Information Technology
"""
  },
  %{
    role: "next js developer",
    profile_text: """
---
**Role Summary:** A Next JS Developer is responsible for building scalable, maintainable, and efficient web applications using Next JS framework.

**Core Technical Skills:**
JavaScript, TypeScript, React, Redux, CSS, HTML, Webpack, Babel, ES6

**Key Responsibilities & Experience:**
Building Single Page Applications, Server-Side Rendering, Static Site Generation, API Integration, State Management

**Essential Tools:**
Visual Studio Code, Git, GitHub, Next JS CLI, Webpack Dev Server, ESLint

**Appreciated Skills & Knowledge:**
CSS Preprocessors, Webpack Plugins, Serverless Architecture, API Gateway, Containerization

**Educational Background:**
Bachelors/Masters in Computer Science, Software Engineering, Web Development, Information Technology
"""
  },
  %{
    role: "sde-1 react developer",
    profile_text: """
---
**Role Summary:** Design, develop, and deploy scalable, maintainable, and efficient React applications.

**Core Technical Skills:**
JavaScript, TypeScript, React, Redux, React Hooks, HTML, CSS, JSX, Webpack, Babel

**Key Responsibilities & Experience:**
Front-end Development, UI/UX Design, State Management, Component Architecture, Code Optimization, Performance Tuning

**Essential Tools:**
Git, Visual Studio Code, Webpack, Babel, ESLint, Jest, React DevTools

**Appreciated Skills & Knowledge:**
Next.js, Gatsby, Redux Toolkit, React Query, TypeScript, Webpack Configuration, Code Splitting

**Educational Background:**
Bachelors/Masters Computer Science, Software Engineering, Web Development, Information Technology
"""
  }
]

Enum.each(job_profiles_data, fn profile_data ->
  # Check if profile already exists for this tenant and role
  existing_profile = Repo.get_by(JobProfile,
    [tenant_id: tenant_id, role: profile_data.role],
    prefix: schema_name
  )

  case existing_profile do
    nil ->
      # Create new profile
      attrs = Map.merge(profile_data, %{
        tenant_id: tenant_id,
        id: Ecto.UUID.generate()
      })
      %JobProfile{}
      |> JobProfile.changeset(attrs)
      |> Repo.insert!(prefix: schema_name)
      Logger.info("✅ Created job profile: #{profile_data.role}")

    _ ->
      Logger.info("⚠️  Job profile already exists: #{profile_data.role}")
  end
end)

Logger.info("🎉 Finished seeding #{length(job_profiles_data)} job profiles for tenant: #{tenant_id}")
