# Vyaasa Campus — User Guide

Step-by-step guide for **Platform Admins**, **Tenant Admins**, and **Students**.

---

## Quick reference

| Role | Login URL | What you can do |
|------|-----------|-----------------|
| **Platform Admin** | `/admin/login` | Create/manage tenants, view system-wide dashboard |
| **Tenant Admin** | `/auth/tenant/{TENANT}/login` | Manage students, view tenant dashboard, run programs |
| **Student** | `/auth/tenant/{TENANT}/login` | Complete profile, take 6 assessments, view reports |

`{TENANT}` is your institution's short code (e.g. `GBC`, `BITE`, `KLU`).

---

## Part 1 — Platform Admin

The platform admin onboards new colleges (tenants).

### 1.1 Log in

1. Go to `/admin/login`
2. Enter platform admin credentials
3. You land on `/admin/dashboard`

### 1.2 Create a new tenant (institution)

1. From the admin dashboard, click **"Create Tenant"** (top right)
2. Fill in:
   - **Full name** (e.g. *Government Brennen College*)
   - **Short alias** (e.g. *GBC* — used in URLs, must be unique)
   - **Affiliation type** (university / autonomous / etc.)
   - **Contact email** + phone
3. Click **Create**

What happens behind the scenes:
- A new schema `tenant_gbc` is created in Postgres
- All tenant tables are migrated (students, assessments, job_profiles, etc.)
- Tenant admin login credentials are emailed to the contact email

### 1.3 Seed job profiles for the tenant (one-time per tenant)

Job profiles are the per-role skill lists used to score student resumes. The codebase ships with **23 default profiles** (Java Developer, Data Scientist, UI/UX Designer, etc.).

After creating a tenant, run:

```bash
TENANT_ID=<the-new-tenant-uuid> mix run priv/repo/tenant_seeds.exs
```

You'll see `[info] Seeded job profiles for tenant: ...`

> Without this step, resume scoring works but **relevance scores will be near zero** because there's nothing to match resume skills against.

### 1.4 Manage existing tenants

From `/admin/dashboard`:
- View all tenants in a table
- Click a tenant row to see its details + student count
- Activate / suspend a tenant
- View aggregate dashboards across tenants

### 1.5 Other admin features

| Page | URL | Purpose |
|------|-----|---------|
| Assessments config | `/admin/assessments-config` | Define MCQ assessments, time limits, pass marks |
| Degrees | `/admin/degrees` | Master list of degrees (B.Tech, M.Tech, MBA, etc.) |
| Question bank | `/admin/question-bank` | Upload/edit MCQ questions |
| Jobs | `/admin/jobs` | View background job status (Oban) |

---

## Part 2 — Tenant Admin

The tenant admin manages students within their institution.

### 2.1 Log in

1. Go to `/auth/tenant/GBC/login` (replace `GBC` with your tenant alias)
2. Enter tenant admin credentials
3. You land on `/user/GBC/dashboard`

### 2.2 Add a student

1. From the dashboard, click **"Add Student"** (or go to `/user/GBC/dashboard/addstudent`)
2. Fill in:
   - **Full name**
   - **Email** (the student will receive a profile-completion link here)
   - **Phone**
   - **Degree + specialization** (dropdowns)
   - **Year of passing**
   - **Roll number**
3. Click **Create Student**

What happens:
- Student record is created in `tenant_gbc.students`
- A profile-completion email is sent to the student's email
- The email contains a one-time link: `/profile/{token}/ats`

### 2.3 View students

Go to `/user/GBC/dashboard/students` to see:
- All students in your tenant
- Per-student status: profile completed / ATS scored / assessments taken
- Filter by year, degree, status
- Click a student row → detailed view with all assessment scores

### 2.4 View dashboard

`/user/GBC/dashboard` shows:
- Total students, active sessions, pending profiles
- Live activity feed (resume uploads, assessment completions)
- Top performers leaderboard

### 2.5 Programs

`/user/GBC/dashboard/programs` lets you:
- Create training programs
- Assign students to programs
- Track program progress

---

## Part 3 — Student

Students complete 6 assessments after their profile is verified.

### 3.1 First-time profile completion

Student receives an email titled *"Complete your Vyaasa Campus profile"*.

1. Click the link in the email — opens `/profile/{token}/ats`
2. Verify your name + email + phone (pre-filled from admin)
3. **Step 1 — Upload documents:**
   - Resume (PDF, max 5 MB)
   - College ID card (image, max 2 MB)
   - Profile photo (image, max 2 MB)
   - Pick your **target job role** from the dropdown
4. Click **Next**
5. **Wait ~30–60 seconds** while the resume is parsed by AI:
   - Loading message: *"ATS processing still in progress, checking again in 3 seconds…"*
   - When complete, you're moved to Step 2

### 3.2 Step 2 — Review parsed resume

The AI has extracted:
- Personal info (name, email, phone, location)
- LinkedIn / GitHub URLs
- Skills (technical + soft)
- Education
- Work experience
- Projects, certifications, languages, achievements
- Final ATS score (0–100)

Review and edit anything that's wrong, then click **Submit**.

### 3.3 Log in to take assessments

After profile completion, the student can log in at `/auth/tenant/GBC/login`.

Initial password is in the email. First login forces a password change at `/student/GBC/change-password`.

### 3.4 Student dashboard

`/student/GBC/dashboard` shows:
- Your ATS score + parsed resume
- 6 assessment cards with status (Not Started / In Progress / Completed)
- Your overall score and ranking
- Re-analyze Resume button

### 3.5 The 6 assessments

#### Assessment 1 — Resume Score
- Already done at profile completion
- Click **Re-analyze Resume** to upload a new version (preserves history)

#### Assessment 2 — MCQ (multiple choice)
- URL: `/student/GBC/assessment/instructions`
- 30+ questions from the institutional question bank
- Time-limited (typically 30–60 minutes)
- Auto-submits when time expires
- Result shows immediately at `/student/GBC/assessment/{id}/result`

#### Assessment 3 — Psychometric (Big Five personality)
- URL: `/student/GBC/assessment/psychometric`
- **Adaptive** — each question is generated based on your previous answer
- 30 questions total, ~10–15 minutes
- Brief loader between questions ("Preparing the next question…")
- Final report shows personality profile across 5 traits

#### Assessment 4 — Behavioral
- URL: `/student/GBC/assessment/behavioral`
- Conversational interview format
- AI presents 2 scenarios with multiple-choice options
- You explain your reasoning in a chat-style interface
- Final report covers situational judgment + STAR technique

#### Assessment 5 — JAM (Just A Minute)
- URL: `/student/GBC/jam/session`
- AI generates a topic
- You speak for 60 seconds (microphone access required)
- AI transcribes and evaluates fluency, content, structure
- Result shows transcript + per-criterion scores

#### Assessment 6 — Mock Interview
- URL: `/student/GBC/interview/session`
- AI conducts a personalized interview based on your resume
- Adaptive questioning — difficulty adjusts to your responses
- Spoken or typed answers
- Final report includes per-question evaluation + overall placement readiness

### 3.6 Re-analyze resume

If you want a new resume scored (e.g. you updated it):

1. From `/student/GBC/dashboard`, click **"Re-analyze Resume"**
2. URL becomes `/student/GBC/resume/reanalyze`
3. Upload the new PDF (no need to re-upload ID card or photo)
4. Wait for AI to score
5. Old scores are preserved — you'll see your improvement history

### 3.7 Download PDF reports

Each completed assessment has a "Download Report" button that generates a PDF version.

Reports are also available at:
- `/student/GBC/reports/psychometric/latest`
- `/student/GBC/reports/behavioral/latest`
- `/student/GBC/reports/jam/latest`
- `/student/GBC/reports/interview/latest`

---

## Common student questions

### "The resume parsing is taking forever"
- Normal: 30–90 seconds
- If >2 minutes: check your internet connection, then refresh the page (the system polls the result and will pick up where it left off)
- Persistent failures usually mean the AI service is rate-limited — admin should check the Groq API tier

### "My relevance score is very low"
- Most often: your tenant doesn't have a `job_profile` for the role you picked
- Ask the admin to seed profiles (see Part 1.3)

### "I want to retake an assessment"
- **Resume**: use Re-analyze Resume on the dashboard
- **Psychometric**: click "Retake Assessment" on the report page (deletes the old session)
- **Others**: contact your tenant admin

### "I can't log in"
- Make sure you completed profile creation first (clicked the email link)
- Use **Forgot Password** at `/auth/tenant/GBC/forgot-password`
- Initial password is in the welcome email — check spam

---

## For developers — extra references

| Document | Purpose |
|----------|---------|
| `docs/migration-python-to-elixir.md` | Architecture + how the AI engines work |
| `docs/concurrency-scaling-500-users.md` | Production scaling, rate limits, capacity planning |
| `MCQ_ASSESSMENT_IMPLEMENTATION.md` | MCQ engine implementation details |
| `JAM_INTEGRATION_PLAN.md` | JAM engine implementation details |
| `DATABASE_SCHEMA.md` | Full DB schema reference |
| `SETUP_GUIDE.md` | Local dev setup |
