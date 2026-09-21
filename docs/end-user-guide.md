# Vyaasa Campus — User Guide

A complete walkthrough for everyone who uses the platform.

---

## Who is this guide for?

| Role | What you do |
|------|-------------|
| **Platform Admin** | Onboard new colleges to the platform |
| **College Admin** | Add students, verify profiles, view results |
| **Student** | Complete profile, take 6 assessments, view your reports |

Skip to the section that matches your role.

---

# Part 1 — Platform Admin

You manage the colleges (called *tenants*) on Vyaasa Campus.

## 1.1 Logging in

1. Open your browser and go to **`/admin/login`**
2. Enter the platform admin email and password (provided by your team)
3. You'll land on the admin dashboard

## 1.2 Adding a new college

1. From the dashboard, click **"Create Tenant"** (top right)
2. Fill in the form:
   - **Full name** of the college (e.g. *Government Brennen College*)
   - **Short code** (e.g. *GBC*) — this becomes part of all URLs for that college
   - **Affiliation type** (university / autonomous / etc.)
   - **Contact email** — login credentials are sent here
   - **Phone number**
3. Click **Create**

The system automatically:
- Creates a private workspace for the college
- Sends login credentials to the contact email
- Activates job profiles (Java Developer, Data Scientist, UI/UX Designer, etc.)

The college admin can now log in and start adding students.

## 1.3 Managing existing colleges

From the admin dashboard you can:
- **View all colleges** with their student counts
- **Click any college** to see details, activity, and student list
- **Suspend or activate** a college
- **View dashboards** with platform-wide statistics

---

# Part 2 — College Admin

You manage the students at your college.

## 2.1 Logging in

1. Go to **`/auth/tenant/{YOUR_CODE}/login`**
   - Replace `{YOUR_CODE}` with your college's short code (e.g. `GBC`, `BITE`, `KLU`)
   - Example: `https://yourdomain.com/auth/tenant/GBC/login`
2. Use the credentials emailed to your college contact email
3. You'll land on your college dashboard

## 2.2 Adding a student

1. Click **"Add Student"** (or go to the Students page)
2. Fill in the student's details:
   - Full name
   - Email (the student gets a profile-completion link here)
   - Phone
   - Degree + specialization
   - Year of passing
   - Roll number
3. Click **Create Student**

What happens next:
- Student is added with status **"Pending"**
- An email is sent to the student with a one-time link
- The student must use that link to upload their resume + ID card

## 2.3 The verification flow

This is the most important part of your role.

```
[Student created]
       ↓
[Student opens email, uploads resume + ID card]
       ↓
[AI scores the resume — takes ~1 minute]
       ↓
[Student status: "Unverified"  →  YOU SEE A "VERIFY" BUTTON]
       ↓
[You review the parsed resume and click "Verify"]
       ↓
[Student receives email with login password]
       ↓
[Student logs in and starts taking assessments]
```

### Where to find unverified students

1. Go to the **Students** page (or the student table on your dashboard)
2. **Change the filter at the top from "Verified" to "Unverified"**
3. You'll see all students who've uploaded their resume but are awaiting your approval
4. Each row has a green **"Verify"** button on the right

### How to verify a student

1. Click the **Verify** button on the student's row
2. Confirm
3. The system:
   - Marks the student as verified
   - Generates a temporary password
   - Emails the password to the student

That's it. The student can now log in and take assessments.

## 2.4 Viewing student progress

From your dashboard you can see:
- Total students (verified + unverified)
- Active assessment sessions
- Top performers
- Recent activity (new uploads, assessment completions)

Click any student row to see:
- Their parsed resume
- All assessment scores (Resume, MCQ, Psychometric, Behavioral, JAM, Interview)
- Combined ranking

## 2.5 Other features

- **Programs** — Create training programs and assign students
- **Job Profiles** — Define the skill expectations for different roles
- **Reports** — Download reports for individual students or the whole batch

---

# Part 3 — Student

You'll go through these steps in order.

## 3.1 First email — profile setup

You receive an email from your college titled **"Complete your Vyaasa Campus profile"**.

Click the link inside.

## 3.2 Profile completion (one-time)

The link opens a 3-step page.

### Step 1 — Upload documents

Upload three things and pick your target job role:

1. **Resume** — PDF format, max 5 MB
2. **College ID card** — image (JPG / PNG), max 2 MB
3. **Profile photo** — passport-style, max 2 MB
4. **Target role** — pick from the dropdown (Java Developer, Data Scientist, etc.)

Click **Next**.

> **Wait around 1 minute.** You'll see a message like *"ATS processing still in progress…"* — this is the AI parsing your resume. Don't refresh the page.

### Step 2 — Review your parsed resume

The AI has extracted everything from your resume:
- Personal info (name, email, phone, location)
- LinkedIn / GitHub links
- Skills, education, work experience, projects
- Your overall ATS score (out of 100)

Review each section. **You can edit anything that's wrong.**

When you're satisfied, click **Continue to Verification**.

### Step 3 — Submitted

You'll see a confirmation message:

> *Profile Submitted Successfully! Your profile has been submitted for admin review. You will receive an email notification once your profile is verified and approved.*

**Now wait for the college admin to verify you.** You'll get a second email with your login password once they do.

## 3.3 Second email — login credentials

Once your college admin verifies you, you'll receive an email with:
- Your login email
- A temporary password
- A link to log in

## 3.4 Logging in for the first time

1. Click the link in the email (or go to `/auth/tenant/{YOUR_COLLEGE}/login`)
2. Enter your email + temporary password
3. The system will ask you to change the password
4. Pick a new strong password
5. You're now on your **Student Dashboard**

## 3.5 Your dashboard

You'll see:
- Your overall score and ranking
- Your parsed resume info
- **6 assessment cards** — each shows your status:
  - Not Started
  - In Progress
  - Completed (with score)
- **"Re-analyze Resume"** button (use this if you update your resume later)

## 3.6 Taking the 6 assessments

Take them in any order. Each is described below.

### Assessment 1 — Resume Score

Already done at profile completion. To update:
1. Click **"Re-analyze Resume"** on the dashboard
2. Upload your new resume
3. Wait ~1 minute for the AI to score it
4. Your old scores are kept — you can see your improvement over time

### Assessment 2 — MCQ (Multiple Choice)

1. Click **MCQ** card
2. Read the instructions, click **Start**
3. Answer the questions within the time limit (usually 30–60 minutes)
4. Auto-submits when time runs out
5. Result shows immediately

### Assessment 3 — Psychometric (Personality)

1. Click **Psychometric** card
2. Click **Start**
3. **30 questions, one at a time** — each generated based on your previous answer
4. Pick from "Strongly Disagree" → "Strongly Agree"
5. Brief loading pause between questions (~10 seconds — the AI is preparing the next one)
6. Final report covers your personality across 5 traits with strengths and growth areas

> Total time: ~10–15 minutes. Don't refresh — your progress is saved.

### Assessment 4 — Behavioral

1. Click **Behavioral** card
2. The AI asks about your work-style preferences
3. Then presents 2 real-world scenarios with multiple-choice options
4. Pick an option and explain your reasoning in chat
5. Final report evaluates your situational judgment + STAR technique

> Total time: ~10 minutes.

### Assessment 5 — JAM (Just A Minute)

1. Click **JAM** card
2. Allow microphone access in your browser when prompted
3. The AI gives you a topic
4. **Speak for 60 seconds** about that topic
5. AI transcribes your speech and evaluates fluency, content, and structure

> Use a quiet room. Total time: ~3 minutes.

### Assessment 6 — Mock Interview

1. Click **Interview** card
2. The AI conducts a personalized interview based on your resume
3. Questions adapt to your answers (easier or harder)
4. Type or speak your answers
5. Get a placement-readiness report at the end

> Total time: ~15–20 minutes.

## 3.7 Downloading your reports

Each completed assessment has a **"Download Report"** button on the result page. You'll get a PDF you can save or share.

---

## Frequently asked questions

### "My resume parsing is taking too long"

- Normal time: 30–90 seconds
- If it's been more than 2 minutes:
  - Check your internet connection
  - Refresh the page — the system saves your progress and picks back up
- If still stuck, contact your college admin

### "My relevance/ATS score is very low"

- Make sure you picked the right **target role** when uploading
- Check that your resume mentions the skills the role requires
- Try **Re-analyze Resume** with an updated version

### "I can't log in"

- Did you complete profile creation first? (Step 1–3 above)
- Has your college admin verified you? (You should have received the second email with your password)
- Use **Forgot Password** at `/auth/tenant/{YOUR_COLLEGE}/forgot-password`
- Check your spam folder for the welcome email

### "I want to retake an assessment"

- **Resume**: Use "Re-analyze Resume" on the dashboard — works any time
- **Psychometric**: Click "Retake Assessment" on the report page
- **Other assessments**: Contact your college admin

### "Where do I download my final report?"

- Each assessment has its own Download button on the result page
- You can also download a combined report from the dashboard (link at top right)

---

## Need more help?

Contact your college admin first. They can:
- Reset your password
- Reset any assessment so you can retake it
- Update your profile details

For platform-level issues, contact the Vyaasa Campus support team.

---

*This document covers the standard flow. Your college may have customized parts of the platform — ask your admin if anything looks different.*
