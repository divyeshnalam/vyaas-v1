defmodule VyaasaCampus.AI.Interview.Specializations do
  @moduledoc """
  Per-domain interview specialization data — sections, core topics, red flags,
  depth triggers, evaluation focus, question style and competency weights.
  Ported verbatim from the reference `config/specializations.py`.
  """

  @specializations %{
    "genai" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "system_design", "behavioral"],
      core_topics: ["LLM fundamentals", "RAG architecture", "prompt engineering", "vector databases", "embedding models", "evaluation strategies", "hallucination handling", "chunking strategies", "agent design"],
      evaluation_focus: ["practical LLM usage", "architecture decisions", "tradeoff reasoning", "ownership of projects", "evaluation methodology"],
      question_style: "architecture + tradeoffs + implementation details",
      red_flags: ["cannot explain chunking decisions", "no evaluation strategy", "copy-pasted RAG without understanding retrieval", "claims LLM knowledge but cannot explain context window"],
      depth_triggers: ["RAG", "agents", "fine-tuning", "embeddings", "evaluation", "prompt engineering"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "ml_ai" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "system_design", "scenario_reasoning", "behavioral"],
      core_topics: ["model selection reasoning", "feature engineering", "evaluation metrics (precision/recall/AUC/NDCG)", "overfitting/underfitting and regularisation", "training pipeline design", "experiment tracking (MLflow/DVC/W&B)", "model deployment and serving", "monitoring and drift detection", "feature stores", "A/B testing for model rollout"],
      evaluation_focus: ["experimental rigor", "production readiness", "model lifecycle ownership", "MLOps maturity", "deployment and monitoring architecture"],
      question_style: "modeling lifecycle + production systems + experiment design",
      red_flags: ["cannot explain why they chose a model", "no awareness of evaluation metrics beyond accuracy", "no experiment tracking \u2014 'we just tried things'", "deployed model with no monitoring or drift detection", "claims MLOps experience but cannot explain CI/CD for models"],
      depth_triggers: ["model deployment", "experiment tracking", "drift detection", "feature engineering", "serving infrastructure", "retraining strategy"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "data_science" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["statistical thinking and distributions", "hypothesis testing and p-values", "A/B test design and sample size calculation", "data cleaning and EDA process", "business metric derivation", "SQL for analytical queries", "visualisation and storytelling with data", "causal inference vs correlation", "cohort analysis and segmentation", "model selection for business problems"],
      evaluation_focus: ["statistical rigour", "translation of data to business impact", "communication of insights to non-technical stakeholders", "data intuition", "storytelling with data"],
      question_style: "statistical reasoning + business framing + insight communication",
      red_flags: ["cannot explain p-value or statistical significance", "no EDA process \u2014 jumped straight to modelling", "accuracy as the only metric", "no business context for analytical choices", "A/B test conclusion without checking sample size", "no mention of data quality or cleaning process"],
      depth_triggers: ["A/B test design", "statistical significance", "business impact", "EDA", "causal reasoning", "metric choice"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["API design", "database design", "caching strategies", "authentication/authorization", "scalability", "async programming", "error handling", "testing"],
      evaluation_focus: ["architecture thinking", "scalability awareness", "database design", "security awareness", "code quality"],
      question_style: "architecture + scaling + real-world constraints",
      red_flags: ["no awareness of N+1 queries", "cannot explain indexing", "no error handling strategy", "cannot explain REST principles"],
      depth_triggers: ["database design", "caching", "authentication", "scaling", "async", "API design"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "java_backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["Spring Boot and Spring ecosystem (MVC, Data, Security)", "JPA/Hibernate and lazy vs eager loading", "Maven/Gradle build tooling", "Java concurrency (threads, executors, CompletableFuture)", "RESTful API design", "exception handling strategy", "unit and integration testing (JUnit, Mockito)", "microservices patterns", "database migrations (Liquibase/Flyway)", "authentication (Spring Security, JWT, OAuth2)"],
      evaluation_focus: ["Spring ecosystem depth", "JPA/ORM awareness", "concurrency handling", "microservices architecture", "test coverage thinking"],
      question_style: "Spring ecosystem depth + ORM tradeoffs + microservices design",
      red_flags: ["cannot explain bean lifecycle or DI", "no awareness of N+1 with JPA", "no transaction management understanding", "claims microservices but cannot explain service discovery or circuit breakers", "no testing strategy beyond happy-path unit tests"],
      depth_triggers: ["Spring Security", "JPA/Hibernate", "transaction management", "microservices", "Kafka integration", "REST vs gRPC"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "go_backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["goroutines and channels", "Go concurrency patterns (select, sync, context)", "interface design and duck typing", "error handling conventions (errors.Is/As, wrapping)", "HTTP servers (net/http, Gin, Echo, Fiber)", "package and module structure", "dependency management (go.mod)", "testing with the standard library", "context propagation and cancellation", "performance profiling (pprof)"],
      evaluation_focus: ["idiomatic Go (goroutines, interfaces, errors)", "concurrency safety", "package design", "context usage", "performance awareness"],
      question_style: "idiomatic Go + concurrency patterns + interface design",
      red_flags: ["goroutines with no synchronisation or context cancellation", "cannot explain interface satisfaction in Go", "ignores error returns ('_ = err')", "no awareness of goroutine leaks", "uses global state instead of dependency injection"],
      depth_triggers: ["goroutines", "channels", "context", "interface design", "error wrapping", "web framework choice"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "rust_backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["ownership, borrowing, and lifetimes", "Result and Option error handling", "async/await with Tokio or async-std", "trait design and generics", "crate selection and Cargo.toml management", "unsafe usage and when it is justified", "memory layout and performance optimisation", "web frameworks (Axum, Actix-web, Warp)", "serialisation (serde)", "testing (unit, integration, doc tests)"],
      evaluation_focus: ["ownership model depth", "async runtime understanding", "safe vs unsafe justification", "trait composition", "performance reasoning"],
      question_style: "ownership model + safety tradeoffs + async design",
      red_flags: ["cannot explain why the borrow checker rejected their code", "uses .clone() or .unwrap() everywhere without reasoning", "no understanding of async runtime selection", "cannot explain trait objects vs generics tradeoff", "no testing beyond compilation"],
      depth_triggers: ["lifetimes", "async runtime", "unsafe", "trait design", "error handling", "crate architecture"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "dotnet_backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["ASP.NET Core middleware pipeline", "dependency injection and service lifetimes", "Entity Framework Core and migrations", "LINQ and expression trees", "async/await and Task-based patterns", "CQRS and MediatR patterns", "authentication (ASP.NET Identity, JWT, Azure AD)", "unit and integration testing (xUnit, NUnit, Moq)", "NuGet package management", "API versioning and documentation (Swagger/OpenAPI)"],
      evaluation_focus: ["DI and middleware depth", "EF Core/ORM awareness", "async patterns", "CQRS/clean architecture understanding", "testing discipline"],
      question_style: "ASP.NET Core architecture + EF Core + design patterns",
      red_flags: ["cannot explain DI service lifetimes (Transient/Scoped/Singleton)", "no EF Core migration strategy", "synchronous code in async context (blocking .Result calls)", "no mention of middleware order mattering", "claims CQRS but cannot explain why commands and queries are separated"],
      depth_triggers: ["middleware pipeline", "EF Core", "DI lifetime", "CQRS", "async patterns", "authentication"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "php_backend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["Laravel or Symfony framework patterns", "MVC and service layer design", "Eloquent ORM and query builder", "Composer dependency management", "RESTful API design", "PHP security (SQL injection, XSS, CSRF)", "queues and background jobs (Laravel Queue, Horizon)", "caching (Redis, Memcached)", "testing (PHPUnit, Pest)", "PHP 8 features (named arguments, fibers, enums)"],
      evaluation_focus: ["framework depth (Laravel/Symfony)", "security awareness", "ORM usage and query efficiency", "background processing", "modern PHP practices"],
      question_style: "framework patterns + security + query optimisation",
      red_flags: ["still writing raw SQL strings with user input (injection risk)", "no awareness of N+1 with Eloquent", "no queue/async job awareness for heavy tasks", "cannot explain middleware in Laravel/Symfony", "no modern PHP (still PHP 5/7 patterns only)"],
      depth_triggers: ["Eloquent", "queues", "security", "service providers", "API design", "caching strategy"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "data_engineering" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["ETL vs ELT pipeline design", "orchestration (Apache Airflow, Prefect, Dagster)", "data transformation (dbt, Spark, PySpark)", "data modelling (star schema, medallion/lakehouse architecture)", "idempotency and incremental loads", "data quality checks and alerting", "data warehouse design (BigQuery, Redshift, Snowflake)", "streaming vs batch tradeoffs (Kafka, Kinesis, Flink)", "partitioning and performance optimisation", "data lineage and cataloguing"],
      evaluation_focus: ["pipeline design and reliability", "idempotency and re-runnability", "data quality ownership", "orchestration design", "incremental vs full-load reasoning", "cost and performance awareness"],
      question_style: "pipeline architecture + reliability + data quality ownership",
      red_flags: ["no idempotency awareness \u2014 'just re-run the pipeline'", "cannot explain why they partitioned data a certain way", "no data quality or validation checks in pipelines", "confuses ETL and ELT without knowing the distinction matters", "no monitoring or alerting on pipeline failures", "star schema vs OLTP confusion"],
      depth_triggers: ["DAG design", "idempotency", "incremental loads", "data quality", "partitioning strategy", "streaming vs batch", "warehouse design"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "frontend" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["component architecture", "state management", "performance optimization", "accessibility", "browser rendering", "CSS layout", "API integration", "testing"],
      evaluation_focus: ["UI thinking", "state management", "performance awareness", "user experience reasoning", "code organization"],
      question_style: "UI reasoning + user experience + performance",
      red_flags: ["no awareness of re-render optimization", "cannot explain virtual DOM", "no accessibility consideration", "no mention of loading/error states"],
      depth_triggers: ["state management", "performance", "rendering", "component design", "CSS"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "fullstack" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "system_design", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["frontend-backend communication", "authentication flow", "database design", "API design", "deployment", "state management", "performance"],
      evaluation_focus: ["end-to-end thinking", "integration reasoning", "architecture decisions", "tradeoffs between layers"],
      question_style: "end-to-end system thinking + integration",
      red_flags: ["strong on one side, completely blank on the other", "no deployment awareness", "cannot explain auth flow end-to-end"],
      depth_triggers: ["auth", "deployment", "API design", "database", "state management"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "flutter_mobile" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["Flutter widget tree and build context", "state management (Riverpod, BLoC, Provider, GetX)", "Dart async (Future, Stream, isolates)", "navigation (GoRouter, Navigator 2.0)", "platform channels (MethodChannel)", "app lifecycle and background tasks", "offline handling and local storage", "API integration and error handling", "testing (unit, widget, integration)", "build flavors and release configuration"],
      evaluation_focus: ["widget rebuild optimisation", "state management pattern depth", "platform-specific code handling", "Dart async understanding", "testing discipline"],
      question_style: "Flutter widget model + state management + platform integration",
      red_flags: ["cannot explain when to use StatefulWidget vs StatelessWidget", "no state management pattern \u2014 setState everywhere in large apps", "no platform channel experience for native features", "cannot explain how to prevent unnecessary rebuilds", "no testing beyond manual device testing"],
      depth_triggers: ["state management choice", "widget lifecycle", "platform channels", "navigation approach", "performance profiling", "offline handling"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "devops" => %{
      sections: ["resume_verification", "core_concepts", "scenario_reasoning", "project_deep_dive", "behavioral"],
      core_topics: ["CI/CD pipelines", "containerization", "orchestration", "infrastructure as code", "monitoring and alerting", "cloud services", "security practices", "incident response"],
      evaluation_focus: ["infrastructure reasoning", "automation thinking", "reliability awareness", "security mindset", "cost awareness"],
      question_style: "infrastructure reasoning + failure scenarios",
      red_flags: ["claims Kubernetes but cannot explain pods vs deployments", "no monitoring/alerting awareness", "no rollback strategy", "no cost awareness"],
      depth_triggers: ["Kubernetes", "CI/CD", "monitoring", "Docker", "Terraform", "incident response"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "cybersecurity" => %{
      sections: ["resume_verification", "core_concepts", "scenario_reasoning", "problem_solving", "behavioral"],
      core_topics: ["threat modeling", "common vulnerabilities (OWASP)", "network security", "incident response", "authentication/authorization", "encryption", "penetration testing concepts"],
      evaluation_focus: ["attack-defense thinking", "risk assessment", "technical accuracy", "scenario handling"],
      question_style: "attack-defense scenarios + risk reasoning",
      red_flags: ["generic security answers", "no awareness of OWASP top 10", "cannot explain difference between auth and authz"],
      depth_triggers: ["OWASP", "authentication", "encryption", "incident response", "penetration testing"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "mobile" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["platform-specific concepts", "UI/UX patterns", "state management", "performance optimization", "offline handling", "app lifecycle", "API integration", "testing"],
      evaluation_focus: ["platform knowledge", "performance awareness", "user experience thinking", "offline-first design"],
      question_style: "platform-specific + UX + performance",
      red_flags: ["no awareness of app lifecycle", "no offline handling strategy", "cannot explain memory management"],
      depth_triggers: ["lifecycle", "performance", "state management", "offline", "platform APIs"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "qa" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "scenario_reasoning", "problem_solving", "behavioral"],
      core_topics: ["test strategy (unit/integration/e2e pyramid)", "automation frameworks (Playwright, Cypress, Selenium, Appium)", "API testing (Postman, REST-assured, pytest-httpx)", "CI/CD integration for test suites", "test case design and boundary analysis", "performance testing (k6, JMeter, Locust)", "bug lifecycle and severity triage", "flaky test identification and remediation"],
      evaluation_focus: ["testing mindset", "coverage thinking", "automation depth (beyond record-and-play)", "quality advocacy in the dev process"],
      question_style: "scenario-based + automation architecture + coverage thinking",
      red_flags: ["only manual testing experience", "no test strategy thinking", "cannot explain test pyramid", "automation that duplicates unit test coverage at E2E cost", "no awareness of flaky tests or how to fix them"],
      depth_triggers: ["test strategy", "automation framework design", "CI/CD integration", "performance testing", "edge cases", "flaky tests"],
      competency_weights: %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}
    },
    "hr" => %{
      sections: ["resume_verification", "scenario_reasoning", "core_concepts", "behavioral", "communication_assessment"],
      core_topics: ["recruitment process", "employee engagement", "conflict resolution", "performance management", "labor law basics", "onboarding", "HRBP partnering"],
      evaluation_focus: ["empathy", "process thinking", "conflict handling", "communication clarity", "people judgment"],
      question_style: "situational + behavioral + people scenarios",
      red_flags: ["no empathy in conflict scenarios", "purely process-driven with no human awareness", "cannot give specific examples"],
      depth_triggers: ["conflict resolution", "difficult employee", "recruitment", "performance improvement", "culture"],
      competency_weights: %{"technical" => 0.3, "communication" => 0.4, "leadership" => 0.2, "cultural_fit" => 0.1}
    },
    "marketing" => %{
      sections: ["resume_verification", "portfolio_deep_dive", "core_concepts", "scenario_reasoning", "problem_solving", "behavioral"],
      core_topics: ["campaign strategy", "target audience", "digital marketing", "metrics and KPIs", "brand positioning", "content strategy", "SEO/SEM basics", "budget allocation"],
      evaluation_focus: ["strategic thinking", "data-driven reasoning", "creativity with purpose", "customer insight", "ROI awareness"],
      question_style: "strategy + metrics + customer reasoning",
      red_flags: ["no metric awareness", "creativity without business purpose", "no customer segmentation thinking"],
      depth_triggers: ["campaign results", "target audience", "metrics", "budget", "ROI", "failed campaigns"],
      competency_weights: %{"technical" => 0.3, "communication" => 0.4, "leadership" => 0.2, "cultural_fit" => 0.1}
    },
    "sales" => %{
      sections: ["resume_verification", "scenario_reasoning", "core_concepts", "behavioral", "communication_assessment"],
      core_topics: ["sales process", "objection handling", "pipeline management", "negotiation", "customer relationship", "closing techniques", "CRM usage"],
      evaluation_focus: ["persuasion ability", "resilience", "customer focus", "process discipline", "communication quality"],
      question_style: "roleplay scenarios + objection handling + results",
      red_flags: ["cannot handle objection scenarios", "no pipeline awareness", "no numbers or results from past roles"],
      depth_triggers: ["difficult customer", "lost deal", "objection handling", "biggest win", "negotiation"],
      competency_weights: %{"technical" => 0.3, "communication" => 0.4, "leadership" => 0.2, "cultural_fit" => 0.1}
    },
    "finance" => %{
      sections: ["resume_verification", "core_concepts", "problem_solving", "scenario_reasoning", "behavioral"],
      core_topics: ["financial statements", "budgeting and forecasting", "ratio analysis", "risk assessment", "accounting principles", "cash flow analysis", "compliance awareness"],
      evaluation_focus: ["numerical accuracy", "business judgment", "risk awareness", "compliance thinking", "analytical depth"],
      question_style: "analytical + scenario-based + numerical reasoning",
      red_flags: ["cannot read a balance sheet", "no risk awareness", "no compliance consideration"],
      depth_triggers: ["financial statements", "ratio analysis", "risk", "forecasting", "audit"],
      competency_weights: %{"technical" => 0.45, "communication" => 0.3, "leadership" => 0.15, "cultural_fit" => 0.1}
    },
    "operations" => %{
      sections: ["resume_verification", "scenario_reasoning", "core_concepts", "problem_solving", "behavioral"],
      core_topics: ["process optimization", "supply chain basics", "KPI tracking", "vendor management", "lean/six sigma", "project coordination", "resource planning"],
      evaluation_focus: ["process thinking", "efficiency mindset", "stakeholder coordination", "problem-solving under constraints"],
      question_style: "process + efficiency + stakeholder scenarios",
      red_flags: ["no metrics or KPI awareness", "cannot describe a process they improved", "no vendor or stakeholder management experience"],
      depth_triggers: ["process improvement", "bottleneck", "vendor issues", "delivery failure", "resource constraint"],
      competency_weights: %{"technical" => 0.35, "communication" => 0.3, "leadership" => 0.25, "cultural_fit" => 0.1}
    },
    "product" => %{
      sections: ["resume_verification", "portfolio_deep_dive", "core_concepts", "scenario_reasoning", "problem_solving", "behavioral"],
      core_topics: ["product discovery", "prioritization frameworks", "user research", "roadmap planning", "stakeholder management", "metrics and success criteria", "agile/scrum"],
      evaluation_focus: ["user empathy", "prioritization reasoning", "data-driven decisions", "stakeholder influence", "business impact awareness"],
      question_style: "product decisions + prioritization + user reasoning",
      red_flags: ["feature-focused without user reasoning", "no success metrics", "cannot handle conflicting stakeholder priorities"],
      depth_triggers: ["prioritization", "failed feature", "user feedback", "stakeholder conflict", "metrics", "roadmap"],
      competency_weights: %{"technical" => 0.35, "communication" => 0.3, "leadership" => 0.25, "cultural_fit" => 0.1}
    },
    "design" => %{
      sections: ["resume_verification", "project_deep_dive", "core_concepts", "scenario_reasoning", "behavioral"],
      core_topics: ["design process", "user research", "information architecture", "usability principles", "design systems", "prototyping", "accessibility", "design critique"],
      evaluation_focus: ["user-centered thinking", "design rationale", "iteration process", "accessibility awareness", "communication of decisions"],
      question_style: "design rationale + user thinking + critique",
      red_flags: ["aesthetics without user reasoning", "no accessibility awareness", "cannot explain design decisions", "no iteration or feedback process"],
      depth_triggers: ["design decision", "user feedback", "accessibility", "design system", "failed design"],
      competency_weights: %{"technical" => 0.3, "communication" => 0.4, "leadership" => 0.2, "cultural_fit" => 0.1}
    },
    "other" => %{
      sections: ["resume_verification", "core_concepts", "scenario_reasoning", "behavioral", "communication_assessment"],
      core_topics: ["role-specific knowledge", "past experience", "problem-solving", "communication", "teamwork"],
      evaluation_focus: ["communication", "experience depth", "problem-solving", "learning ability"],
      question_style: "experience-based + behavioral + scenario",
      red_flags: ["vague answers with no specifics", "no concrete examples"],
      depth_triggers: ["specific project", "difficult situation", "achievement", "failure"],
      competency_weights: %{"technical" => 0.35, "communication" => 0.35, "leadership" => 0.2, "cultural_fit" => 0.1}
    },
    "legal" => %{
      sections: ["resume_verification", "core_concepts", "scenario_reasoning", "problem_solving", "behavioral", "communication_assessment"],
      core_topics: ["contract drafting and review", "regulatory compliance", "corporate law basics", "litigation process", "legal research methodology", "due diligence", "risk identification and mitigation", "intellectual property basics", "employment law", "client communication and advisory"],
      evaluation_focus: ["legal reasoning accuracy", "risk identification", "attention to detail", "communication clarity", "practical judgment over textbook recall"],
      question_style: "scenario-based + risk reasoning + drafting judgment",
      red_flags: ["cannot identify key risks in a contract scenario", "no awareness of jurisdiction-specific differences", "confuses compliance advisory with litigation strategy", "cannot explain due diligence process", "vague answers with no reference to specific legal principles"],
      depth_triggers: ["contract clauses", "compliance risk", "due diligence", "dispute resolution", "regulatory filing", "client advisory"],
      competency_weights: %{"technical" => 0.45, "communication" => 0.3, "leadership" => 0.15, "cultural_fit" => 0.1}
    }
  }

  @it_domains MapSet.new(["backend", "cybersecurity", "data_engineering", "data_science", "devops", "dotnet_backend", "flutter_mobile", "frontend", "fullstack", "genai", "go_backend", "java_backend", "ml_ai", "mobile", "php_backend", "qa", "rust_backend"])
  @default_weights %{"technical" => 0.5, "communication" => 0.3, "leadership" => 0.1, "cultural_fit" => 0.1}

  def get(domain) when is_binary(domain), do: Map.get(@specializations, domain, @specializations["other"])
  def get(_), do: @specializations["other"]
  def core_topics(domain), do: get(domain).core_topics
  def red_flags(domain), do: get(domain).red_flags
  def depth_triggers(domain), do: get(domain).depth_triggers
  def evaluation_focus(domain), do: get(domain).evaluation_focus
  def question_style(domain), do: get(domain).question_style
  def sections(domain), do: get(domain).sections
  def competency_weights(domain), do: Map.get(get(domain), :competency_weights, @default_weights)
  def list_domains, do: Map.keys(@specializations)
  def it_domain?(domain), do: MapSet.member?(@it_domains, domain)
end
