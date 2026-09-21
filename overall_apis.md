# VyaasaCampus API Documentation

## Base URL

```
http://localhost:4000/api
```

## Authentication

The API uses JWT (JSON Web Tokens) for authentication with refresh token support.

### Headers Required

```
Authorization: Bearer <access_token>
x-tenant: <tenant_alias>  # Required for tenant-scoped operations
Content-Type: application/json
```

### Token Types

- **Access Token**: Short-lived (30 minutes by default)
- **Refresh Token**: Long-lived (30 days by default), stored in HTTP-only cookies

### Authentication Flows

1. **Login**: POST to `/auth/{user_type}/login` with credentials
2. **Token Refresh**: POST to `/auth/refresh` with refresh token
3. **Logout**: POST to `/auth/logout` to invalidate tokens
4. **Password Reset**: POST to `/auth/password-reset/request` and `/auth/password-reset/reset`

## User Types & Permissions

### Platform Admin
- Can manage all tenants and their data
- Can create users and roles in any tenant
- Can manage tenant locations
- Access to platform-wide operations

### Tenant Users
- Can manage users, roles, and students within their tenant
- Can create and manage assessments
- Can approve/reject student profiles
- Tenant-scoped access only

### Students
- Can view and take published assessments
- Can manage their own profiles
- Can request profile edits
- Student-scoped access only

---

## Authentication Endpoints

### Platform Admin Login

**POST** `/auth/platform-admin/login`

Authenticates a platform admin user.

**Request Body:**
```json
{
  "email": "admin@vyaasa.com",
  "password": "secure_password"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 1800,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "admin@vyaasa.com",
    "first_name": "Admin",
    "last_name": "User",
    "role": "super_admin",
    "user_type": "admin"
  }
}
```

### Tenant User Login

**POST** `/auth/tenant-user/login`

Authenticates a tenant user (institute admin).

**Request Body:**
```json
{
  "email": "admin@university.edu",
  "password": "secure_password"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 1800,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "email": "admin@university.edu",
    "first_name": "Institute",
    "last_name": "Admin",
    "role": "admin",
    "user_type": "user"
  }
}


```

### Student Login

**POST** `/auth/student/login`

Authenticates a student user.

**Request Body:**
```json
{
  "email": "student@university.edu",
  "password": "secure_password"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 1800,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "email": "student@university.edu",
    "first_name": "John",
    "last_name": "Doe",
    "user_type": "student"
  }
}
```

### Refresh Token

**POST** `/auth/refresh`

Refreshes an access token using a refresh token.

**Request Body:**
```json
{
  "refresh_token": "refresh_token_here",
  "user_type": "student",
  "tenant_schema": "tenant_cambridge_uni"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 1800
}
```

### Get Current User

**GET** `/auth/me`

Returns information about the currently authenticated user.

**Headers:**
```
Authorization: Bearer <access_token>
x-tenant: <tenant_alias>  # For tenant users and students
```

**Response (200):**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "email": "student@university.edu",
    "first_name": "John",
    "last_name": "Doe",
    "user_type": "student",
    "last_login_at": "2024-01-15T10:30:00+05:30",
    "created_at": "2024-01-01T00:00:00+05:30",
    "updated_at": "2024-01-15T10:30:00+05:30",
    "student_profile": {
      "registration_id": "STU2024001",
      "degree": "Bachelor of Technology",
      "specialization": "Computer Science",
      "current_academic_year": "4th Year",
      "cgpa": 8.5,
      "year_of_passing": 2024,
      "profile_completed": true
    }
  },
  "tenant_info": {
    "tenant_type": "institute",
    "alias": "cambridge_uni",
    "name": "Cambridge University",
    "schema": "tenant_cambridge_uni"
  },
  "scope": "student"
}
```

### Logout

**POST** `/auth/logout`

Logs out the current user and invalidates tokens.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "message": "Logged out successfully"
}
```

### Password Reset Request

**POST** `/auth/password-reset/request`

Requests a password reset email.

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

**Response (200):**
```json
{
  "message": "Password reset email sent successfully",
  "email": "user@example.com"
}
```

### Password Reset

**POST** `/auth/password-reset/reset`

Resets password using a token from email.

**Request Body:**
```json
{
  "token": "reset_token_here",
  "password": "new_secure_password"
}
```

**Response (200):**
```json
{
  "message": "Password reset successfully",
  "user_id": "550e8400-e29b-41d4-a716-446655440002"
}
```

### Clear Temporary Password

**POST** `/auth/clear-temp-password`

Clears temporary password after first login.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request Body:**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440002"
}
```

**Response (200):**
```json
{
  "message": "Temporary password cleared successfully"
}
```

---

## Platform Admin Endpoints

### Tenant Management

#### List All Tenants

**GET** `/platform_admin/tenants`

**Headers:**
```
Authorization: Bearer <admin_token>
```

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440010",
    "full_name": "Cambridge University",
    "short_name": "Cambridge",
    "alias": "cambridge_uni",
    "schema_name": "tenant_cambridge_uni",
    "affiliation_type": "university",
    "email": "info@cambridge.edu",
    "phone": "+1-555-0123",
    "website_url": "https://cambridge.edu",
    "status": "active",
    "created_at": "2024-01-01T00:00:00+05:30",
    "updated_at": "2024-01-15T10:30:00+05:30"
  }
]
```

#### Get Tenant

**GET** `/platform_admin/tenants/:id`

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440010",
  "full_name": "Cambridge University",
  "short_name": "Cambridge",
  "alias": "cambridge_uni",
  "schema_name": "tenant_cambridge_uni",
  "affiliation_type": "university",
  "email": "info@cambridge.edu",
  "phone": "+1-555-0123",
  "website_url": "https://cambridge.edu",
  "status": "active",
  "created_at": "2024-01-01T00:00:00+05:30",
  "updated_at": "2024-01-15T10:30:00+05:30"
}
```

#### Create Tenant

**POST** `/platform_admin/tenants`

**Request Body:**
```json
{
  "tenant": {
    "full_name": "Oxford University",
    "short_name": "Oxford",
    "alias": "oxford_uni",
    "affiliation_type": "university",
    "email": "info@oxford.edu",
    "phone": "+44-1865-270000",
    "website_url": "https://oxford.edu"
  }
}
```

**Response (201):**
```json
{
  "tenant": {
    "id": "550e8400-e29b-41d4-a716-446655440011",
    "full_name": "Oxford University",
    "short_name": "Oxford",
    "alias": "oxford_uni",
    "schema_name": "tenant_oxford_uni",
    "affiliation_type": "university",
    "email": "info@oxford.edu",
    "phone": "+44-1865-270000",
    "website_url": "https://oxford.edu",
    "status": "active"
  },
  "message": "Tenant created successfully with schema: tenant_oxford_uni"
}
```

#### Update Tenant

**PUT** `/platform_admin/tenants/:id`

**Request Body:**
```json
{
  "tenant": {
    "full_name": "Updated University Name",
    "email": "new@email.edu"
  }
}
```

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440010",
  "full_name": "Updated University Name",
  "short_name": "Cambridge",
  "alias": "cambridge_uni",
  "email": "new@email.edu",
  "status": "active"
}
```

#### Delete Tenant

**DELETE** `/platform_admin/tenants/:id`

**Response (204):** No content

#### Activate Tenant

**POST** `/platform_admin/tenants/:id/activate`

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440010",
  "status": "active"
}
```

#### Deactivate Tenant

**POST** `/platform_admin/tenants/:id/deactivate`

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440010",
  "status": "inactive"
}
```

### Tenant Location Management

#### List Locations

**GET** `/platform_admin/locations`

**Headers:**
```
Authorization: Bearer <admin_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440020",
    "name": "Main Campus",
    "address": "123 University Ave",
    "city": "Cambridge",
    "state": "MA",
    "country": "USA",
    "postal_code": "02138",
    "is_primary": true,
    "tenant_id": "550e8400-e29b-41d4-a716-446655440010"
  }
]
```

#### Create Location

**POST** `/platform_admin/locations`

**Request Body:**
```json
{
  "location": {
    "name": "Downtown Campus",
    "address": "456 Business St",
    "city": "Cambridge",
    "state": "MA",
    "country": "USA",
    "postal_code": "02139"
  }
}
```

**Response (201):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440021",
  "name": "Downtown Campus",
  "address": "456 Business St",
  "city": "Cambridge",
  "state": "MA",
  "country": "USA",
  "postal_code": "02139",
  "is_primary": false,
  "tenant_id": "550e8400-e29b-41d4-a716-446655440010"
}
```

#### Update Location

**PUT** `/platform_admin/locations/:id`

**Request Body:**
```json
{
  "location": {
    "name": "Updated Campus Name",
    "address": "789 New Address St",
    "city": "Updated City",
    "state": "UC",
    "country": "Updated Country",
    "postal_code": "54321"
  }
}
```

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440021",
  "name": "Updated Campus Name",
  "address": "789 New Address St",
  "city": "Updated City",
  "state": "UC",
  "country": "Updated Country",
  "postal_code": "54321",
  "is_primary": false,
  "tenant_id": "550e8400-e29b-41d4-a716-446655440010"
}
```

#### Delete Location

**DELETE** `/platform_admin/locations/:id`

**Response (204):** No content

#### Set Primary Location

**POST** `/platform_admin/locations/:id/set_primary`

**Response (204):** No content

---

## Tenant Admin Endpoints

### User Management

#### List Users

**GET** `/tenant/users`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440030",
    "email": "admin@university.edu",
    "first_name": "Institute",
    "last_name": "Admin",
    "role": "admin",
    "status": "active",
    "tenant_id": "550e8400-e29b-41d4-a716-446655440010",
    "created_at": "2024-01-01T00:00:00+05:30"
  }
]
```

#### Get User

**GET** `/tenant/users/:id`

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440030",
  "email": "admin@university.edu",
  "first_name": "Institute",
  "last_name": "Admin",
  "role": "admin",
  "status": "active",
  "tenant_id": "550e8400-e29b-41d4-a716-446655440010",
  "created_at": "2024-01-01T00:00:00+05:30"
}
```

#### Create User

**POST** `/tenant/users`

**Request Body:**
```json
{
  "user": {
    "email": "newadmin@university.edu",
    "first_name": "New",
    "last_name": "Admin",
    "role": "admin"
  }
}
```

**Response (200):**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440031",
    "email": "newadmin@university.edu",
    "first_name": "New",
    "last_name": "Admin",
    "role": "admin",
    "status": "active"
  },
  "message": "User created successfully. Welcome email sent."
}
```

### Role Management

#### List Roles

**GET** `/tenant/roles`

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440040",
    "name": "admin",
    "display_name": "Administrator",
    "tenant_id": "550e8400-e29b-41d4-a716-446655440010"
  }
]
```

#### Create Role

**POST** `/tenant/roles`

**Request Body:**
```json
{
  "role": {
    "name": "moderator",
    "display_name": "Moderator"
  }
}
```

**Response (200):**
```json
{
  "role": {
    "id": "550e8400-e29b-41d4-a716-446655440041",
    "name": "moderator",
    "display_name": "Moderator",
    "tenant_id": "550e8400-e29b-41d4-a716-446655440010"
  },
  "message": "Role created successfully"
}
```

### User Role Management

#### List User Roles

**GET** `/tenant/user_roles`

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440050",
    "user_id": "550e8400-e29b-41d4-a716-446655440030",
    "role_id": "550e8400-e29b-41d4-a716-446655440040",
    "assigned_by_id": "550e8400-e29b-41d4-a716-446655440000",
    "assigned_by_type": "admin"
  }
]
```

#### Assign Role to User

**POST** `/tenant/user_roles`

**Request Body:**
```json
{
  "user_role": {
    "user_id": "550e8400-e29b-41d4-a716-446655440030",
    "role_id": "550e8400-e29b-41d4-a716-446655440040"
  }
}
```

**Response (200):**
```json
{
  "user_role": {
    "id": "550e8400-e29b-41d4-a716-446655440050",
    "user_id": "550e8400-e29b-41d4-a716-446655440030",
    "role_id": "550e8400-e29b-41d4-a716-446655440040"
  },
  "message": "Role assigned successfully"
}
```

### Student Management

#### List Students

**GET** `/tenant/students`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440060",
    "email": "student@university.edu",
    "first_name": "John",
    "last_name": "Doe",
    "registration_id": "STU2024001",
    "degree": "Bachelor of Technology",
    "specialization": "Computer Science",
    "status": "active",
    "profile_completed": true,
    "cgpa": 8.5,
    "year_of_passing": 2024,
    "preferred_role": "Software Engineer",
    "resume_url": "https://example.com/resume.pdf",
    "college_id_card_url": "https://example.com/id_card.jpg",
    "profile_picture_url": "https://example.com/photo.jpg"
  }
]
```

#### Create Student

**POST** `/tenant/students`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "student": {
    "email": "newstudent@university.edu",
    "first_name": "Jane",
    "last_name": "Smith",
    "phone": "+1234567890",
        "registration_id": "STU2024002",
        "degree": "Bachelor of Technology",
        "specialization": "Computer Science",
        "year_of_passing": 2024,
        "cgpa": 8.0
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440061",
    "email": "newstudent@university.edu",
    "first_name": "Jane",
    "last_name": "Smith",
    "status": "pending_profile_completion"
  },
  "message": "Student created successfully. Profile completion email sent.",
  "status": "pending_profile_completion",
  "next_step": "Student should check email and complete profile"
}
```

#### Bulk Create Students

**POST** `/tenant/students/bulk`

Creates multiple students in a single request with concurrent processing for better performance.

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "students": [
    {
      "email": "student1@university.edu",
      "first_name": "John",
      "last_name": "Doe",
      "phone": "+1234567890",
      "registration_id": "STU2024001",
      "degree": "Bachelor of Technology",
      "specialization": "Computer Science",
      "year_of_passing": 2024,
      "cgpa": 8.5
    },
    {
      "email": "student2@university.edu",
      "first_name": "Jane",
      "last_name": "Smith",
      "phone": "+1234567891",
      "registration_id": "STU2024002",
      "degree": "Bachelor of Technology",
      "specialization": "Information Technology",
      "year_of_passing": 2024,
      "cgpa": 8.0
    }
  ],
  "options": {
    "max_concurrency": 5,
    "timeout": 30000
  }
}
```

**Response (200):**
```json
{
  "message": "Bulk creation completed",
  "summary": {
    "total": 2,
    "successful": 2,
    "failed": 0,
    "errors": [],
    "duration_ms": 150
  },
  "students": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440061",
      "email": "student1@university.edu",
      "first_name": "John",
      "last_name": "Doe",
      "status": "pending_profile_completion"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440062",
      "email": "student2@university.edu",
      "first_name": "Jane",
      "last_name": "Smith",
      "status": "pending_profile_completion"
    }
  ]
}
```

**Error Response (400) - Too Many Students:**
```json
{
  "error": "Too many students for bulk creation",
  "max_allowed": 1000,
  "requested": 1500
}
```

**Error Response (200) - Partial Success:**
```json
{
  "message": "Bulk creation completed",
  "summary": {
    "total": 10,
    "successful": 8,
    "failed": 2,
    "errors": [
      {
        "email": "invalid@university.edu",
        "error": "Validation failed",
        "details": {
          "email": ["has already been taken"]
        }
      },
      {
        "email": "badformat",
        "error": "Validation failed",
        "details": {
          "email": ["has invalid format"]
        }
      }
    ],
    "duration_ms": 250
  },
  "students": [
    // ... successful student records
  ]
}
```

#### Update Student

**PUT** `/tenant/students/:id`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "student": {
    "first_name": "Updated Name",
    "cgpa": 8.8
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440060",
    "first_name": "Updated Name",
    "cgpa": 8.8
  },
  "message": "Student updated successfully"
}
```

#### List Pending Students

**GET** `/tenant/students/pending`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "students": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440061",
      "email": "newstudent@university.edu",
      "first_name": "Jane",
      "last_name": "Smith",
      "status": "unverified",
      "profile_completed": true,
      "profile_submitted_at": "2024-01-15T10:30:00+05:30"
    }
  ],
  "count": 1
}
```

#### Approve Student

**POST** `/tenant/students/:id/approve`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "approval": {
    "admin_notes": "Profile looks good, approved for access"
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440061",
    "status": "active",
    "profile_approved_at": "2024-01-15T11:00:00+05:30"
  },
  "message": "Student profile approved successfully. Login credentials sent."
}
```

#### Reject Student

**POST** `/tenant/students/:id/reject`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "rejection": {
    "admin_notes": "Profile needs improvement",
    "edit_request_notes": "Please update your resume and add more skills"
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440061",
    "status": "profile_incomplete",
    "profile_rejected_at": "2024-01-15T11:00:00+05:30"
  },
  "message": "Student profile rejected. Edit request sent with feedback."
}
```

#### List Edit Requests

**GET** `/tenant/students/edit-requests`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "students": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440060",
      "email": "student@university.edu",
      "first_name": "John",
      "last_name": "Doe",
      "status": "active",
      "edit_requested_at": "2024-01-15T10:30:00+05:30"
    }
  ],
  "count": 1
}
```

#### Approve Edit Request

**POST** `/tenant/students/:id/approve-edit`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "approval": {
    "admin_notes": "Edit request approved"
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440060",
    "status": "active"
  },
  "message": "Profile edit request approved successfully."
}
```

#### Reject Edit Request

**POST** `/tenant/students/:id/reject-edit`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "rejection": {
    "admin_notes": "Edit request rejected",
    "rejection_notes": "The requested changes are not appropriate"
  }
}
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440060",
    "status": "active"
  },
  "message": "Profile edit request rejected. Feedback sent to student."
}
```

### Assessment Management

#### List Assessments

**GET** `/tenant/assessments`

**Response (200):**
```json
{
  "assessments": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440070",
      "title": "Computer Science Final Exam",
      "description": "Comprehensive exam covering all topics",
      "assessment_type": "exam",
      "duration_minutes": 120,
      "total_marks": 100,
      "passing_marks": 40,
      "status": "published",
      "created_at": "2024-01-01T00:00:00+05:30"
    }
  ]
}
```

#### Create Assessment

**POST** `/tenant/assessments`

**Request Body:**
```json
{
  "assessment": {
    "title": "Programming Quiz",
    "description": "Basic programming concepts quiz",
    "assessment_type": "quiz",
    "duration_minutes": 30,
    "total_marks": 50,
    "passing_marks": 25,
    "weightage": 10.0,
    "time_period": {
      "start_date": "2024-02-01T09:00:00Z",
      "end_date": "2024-02-01T17:00:00Z"
    }
  }
}
```

**Response (201):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440071",
    "title": "Programming Quiz",
    "description": "Basic programming concepts quiz",
    "assessment_type": "quiz",
    "duration_minutes": 30,
    "total_marks": 50,
    "passing_marks": 25,
    "status": "draft"
  },
  "message": "Assessment created successfully"
}
```

#### Get Assessment

**GET** `/tenant/assessments/:id`

**Response (200):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440070",
    "title": "Computer Science Final Exam",
    "description": "Comprehensive exam covering all topics",
    "assessment_type": "exam",
    "duration_minutes": 120,
    "total_marks": 100,
    "passing_marks": 40,
    "status": "published",
    "time_period": {
      "start_date": "2024-02-01T09:00:00Z",
      "end_date": "2024-02-01T17:00:00Z"
    }
  }
}
```

#### Update Assessment

**PUT** `/tenant/assessments/:id`

**Request Body:**
```json
{
  "assessment": {
    "title": "Updated Assessment Title",
    "duration_minutes": 90
  }
}
```

**Response (200):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440070",
    "title": "Updated Assessment Title",
    "duration_minutes": 90
  },
  "message": "Assessment updated successfully"
}
```

#### Delete Assessment

**DELETE** `/tenant/assessments/:id`

**Response (200):**
```json
{
  "message": "Assessment deleted successfully"
}
```

#### Publish Assessment

**POST** `/tenant/assessments/:id/publish`

**Response (200):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440070",
    "status": "published"
  },
  "message": "Assessment published successfully"
}
```

#### Archive Assessment

**POST** `/tenant/assessments/:id/archive`

**Response (200):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440070",
    "status": "archived"
  },
  "message": "Assessment archived successfully"
}
```

---

## Student Endpoints

### Assessment Access

#### List Published Assessments

**GET** `/student/assessments`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "assessments": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440070",
      "title": "Computer Science Final Exam",
      "description": "Comprehensive exam covering all topics",
      "assessment_type": "exam",
      "duration_minutes": 120,
      "total_marks": 100,
      "passing_marks": 40,
      "status": "published",
      "time_period": {
        "start_date": "2024-02-01T09:00:00Z",
        "end_date": "2024-02-01T17:00:00Z"
      }
    }
  ]
}
```

#### Get Published Assessment

**GET** `/student/assessments/:id`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "assessment": {
    "id": "550e8400-e29b-41d4-a716-446655440070",
    "title": "Computer Science Final Exam",
    "description": "Comprehensive exam covering all topics",
    "assessment_type": "exam",
    "duration_minutes": 120,
    "total_marks": 100,
    "passing_marks": 40,
    "status": "published"
  }
}
```

#### Start Assessment Attempt

**POST** `/student/assessments/:id/start`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (201):**
```json
{
  "attempt": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "assessment_id": "550e8400-e29b-41d4-a716-446655440070",
    "student_id": "550e8400-e29b-41d4-a716-446655440060",
    "started_at": "2024-01-15T10:30:00+05:30",
    "status": "in_progress"
  },
  "message": "Assessment attempt started successfully"
}
```

#### Get Attempt

**GET** `/student/attempts/:id`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "attempt": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "assessment_id": "550e8400-e29b-41d4-a716-446655440070",
    "student_id": "550e8400-e29b-41d4-a716-446655440060",
    "started_at": "2024-01-15T10:30:00+05:30",
    "submitted_at": null,
    "status": "in_progress",
    "score": null
  }
}
```

#### Submit Attempt

**PUT** `/student/attempts/:id/submit`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "answers": {
    "question_1": "answer_1",
    "question_2": "answer_2"
  }
}
```

**Response (200):**
```json
{
  "attempt": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "assessment_id": "550e8400-e29b-41d4-a716-446655440070",
    "student_id": "550e8400-e29b-41d4-a716-446655440060",
    "started_at": "2024-01-15T10:30:00+05:30",
    "submitted_at": "2024-01-15T12:30:00+05:30",
    "status": "completed",
    "score": 85
  },
  "message": "Assessment submitted successfully"
}
```

#### List My Attempts

**GET** `/student/my-attempts`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "attempts": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440080",
      "assessment_id": "550e8400-e29b-41d4-a716-446655440070",
      "started_at": "2024-01-15T10:30:00+05:30",
      "submitted_at": "2024-01-15T12:30:00+05:30",
      "status": "completed",
      "score": 85
    }
  ]
}
```

### Profile Management

#### Request Profile Edit

**POST** `/student/profile/edit-request`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "message": "Profile edit request submitted successfully. Awaiting admin approval.",
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440060",
    "email": "student@university.edu",
    "first_name": "John",
    "last_name": "Doe",
    "status": "active",
    "edit_requested_at": "2024-01-15T10:30:00+05:30"
  }
}
```

---

## Profile Completion Endpoints

### Verify Profile Token

**GET** `/student/profile-completion/verify?token=xxx`

**Headers:**
```
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440061",
    "email": "newstudent@university.edu",
    "first_name": "Jane",
    "last_name": "Smith",
    "registration_id": "STU2024002",
    "degree": "Bachelor of Technology",
    "specialization": "Computer Science",
    "year_of_passing": 2024,
    "cgpa": 8.0,
    "token_valid": true
  },
  "message": "Token is valid. You can now complete your profile."
}
```

### Submit Profile

**POST** `/student/profile-completion/submit`

Completes student profile with required documents and preferred role. Upon submission, the resume is automatically processed by the ATS (Applicant Tracking System) for analysis and scoring. The profile is then submitted for admin review and approval.

**Headers:**
```
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "token": "profile_token_here",
  "profile": {
    "resume_url": "https://example.com/resume.pdf",
    "college_id_card_url": "https://example.com/id_card.jpg",
    "profile_picture_url": "https://example.com/photo.jpg",
    "preferred_role": "Software Engineer"
  }
}
```

**Response (200):**
```json
{
  "message": "Profile completed successfully and submitted for review",
  "student": {
    "id": "550e8400-e29b-41d4-a716-446655440061",
    "email": "newstudent@university.edu",
    "first_name": "Jane",
    "last_name": "Smith",
    "status": "unverified",
    "profile_completed": true,
    "profile_submitted_at": "2024-01-15T10:30:00+05:30"
  }
}
```

### Resend Profile Email

**POST** `/student/profile-completion/resend`

**Headers:**
```
Authorization: Bearer <tenant_user_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "student_id": "550e8400-e29b-41d4-a716-446655440061"
}
```

**Response (200):**
```json
{
  "message": "Profile completion email sent successfully",
  "student_id": "550e8400-e29b-41d4-a716-446655440061",
  "email": "newstudent@university.edu"
}
```

---

## JAM (Just A Minute) Endpoints

### Student JAM Endpoints

#### Create JAM Session

**POST** `/student/jam/sessions`

Creates a new JAM speech assessment session for the student.

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
Content-Type: application/json
```

**Request Body:**
```json
{
  "jam_session": {
    "preferences": {
      "difficulty": "medium",
      "topics": ["technology", "education"]
    }
  }
}
```

**Response (201):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "session_token": "jam_token_123",
    "status": "created",
    "decision_time_seconds": 60,
    "preparation_time_seconds": 15,
    "speech_time_seconds": 60
  },
  "message": "JAM session created successfully. Topic generation in progress."
}
```

#### Get JAM Session

**GET** `/student/jam/sessions/:id`

**Headers:**
```
Authorization: Bearer <student_token>
x-tenant: <tenant_alias>
```

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "session_token": "jam_token_123",
    "status": "topic_generated",
    "topic_title": "The Future of Artificial Intelligence",
    "topic_explanation": "Discuss the potential impact of AI on society...",
    "decision_time_seconds": 60,
    "preparation_time_seconds": 15,
    "speech_time_seconds": 60,
    "change_topic_available": true
  }
}
```

#### Start JAM Session

**POST** `/student/jam/sessions/:id/start`

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "decision_phase"
  },
  "message": "JAM session started successfully"
}
```

#### Make Topic Decision

**POST** `/student/jam/sessions/:id/decide-topic`

**Request Body:**
```json
{
  "decision": {
    "topic_changed": false,
    "actual_decision_time_used": 45
  }
}
```

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "preparation"
  },
  "message": "Topic decision recorded successfully"
}
```

#### Start Preparation

**POST** `/student/jam/sessions/:id/start-preparation`

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "preparation",
    "actual_preparation_time_used": 0
  },
  "message": "Preparation phase started"
}
```

#### Start Speaking

**POST** `/student/jam/sessions/:id/start-speaking`

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "speaking",
    "actual_speech_time_used": 0
  },
  "message": "Speaking phase started"
}
```

#### Upload Audio

**POST** `/student/jam/sessions/:id/upload-audio`

**Request Body:**
```json
{
  "audio_data": {
    "recording_file_path": "/uploads/audio/session_123.wav",
    "recording_duration_seconds": 58,
    "speech_time_used": 58,
    "audio_quality_score": 0.95,
    "noise_level": 0.05
  }
}
```

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "processing"
  },
  "message": "Audio uploaded successfully. Processing in progress."
}
```

#### Get Session Status

**GET** `/student/jam/sessions/:id/status`

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "processing",
    "progress": "Audio analysis in progress"
  }
}
```

#### Get Session Results

**GET** `/student/jam/sessions/:id/results`

**Response (200):**
```json
{
  "jam_session": {
    "id": "550e8400-e29b-41d4-a716-446655440080",
    "status": "completed",
    "completed_at": "2024-12-20T10:30:00Z"
  },
  "results": {
    "final_score": 85,
    "clarity_score": 8,
    "structure_score": 9,
    "relevance_score": 8,
    "impact_score": 7,
    "confidence_score": 9,
    "overall_summary": "Excellent speech with clear structure and good relevance to the topic...",
    "transcript": "The future of artificial intelligence is a topic that...",
    "word_count": 245,
    "speech_duration_seconds": 58
  }
}
```

### JAM Callback Endpoints (Python Service)

#### Topic Generated Callback

**POST** `/jam/callback/topic-generated`

**Headers:**
```
Authorization: Bearer <jam_secret>
Content-Type: application/json
```

**Request Body:**
```json
{
  "session_token": "jam_token_123",
  "topic_data": {
    "title": "The Future of Artificial Intelligence",
    "explanation": "Discuss the potential impact of AI on society...",
    "change_topic_available": true
  }
}
```

**Response (200):**
```json
{
  "message": "Topic generated callback processed successfully",
  "session_id": "550e8400-e29b-41d4-a716-446655440080"
}
```

#### Audio Processed Callback

**POST** `/jam/callback/audio-processed`

**Request Body:**
```json
{
  "session_token": "jam_token_123",
  "evaluation_data": {
    "transcript": "The future of artificial intelligence is a topic that...",
    "word_count": 245,
    "speech_duration_seconds": 58,
    "final_score": 85,
    "clarity_score": 8,
    "structure_score": 9,
    "relevance_score": 8,
    "impact_score": 7,
    "confidence_score": 9,
    "overall_summary": "Excellent speech with clear structure...",
    "evaluation_data": {
      "detailed_analysis": "...",
      "improvement_suggestions": "..."
    }
  }
}
```

**Response (200):**
```json
{
  "message": "Audio processed callback received successfully",
  "session_id": "550e8400-e29b-41d4-a716-446655440080"
}
```

#### Processing Error Callback

**POST** `/jam/callback/processing-error`

**Request Body:**
```json
{
  "session_token": "jam_token_123",
  "error": {
    "type": "audio_processing_failed",
    "message": "Unable to process audio file",
    "retry_count": 1
  }
}
```

**Response (200):**
```json
{
  "message": "Processing error callback received",
  "session_id": "550e8400-e29b-41d4-a716-446655440080"
}
```

#### Health Check

**GET** `/jam/callback/health`

**Response (200):**
```json
{
  "status": "healthy",
  "timestamp": "2024-12-20T10:30:00Z"
}
```

---

## ATS Service Endpoints

### ATS Callback

**POST** `/ats/callback`

Receives resume analysis results from the external Python ATS service. This endpoint is called by the Python service after processing a resume to send back the analysis results.

**Headers:**
```
Authorization: Bearer <ats_service_jwt>
Content-Type: application/json
```

**Request Body:**
```json
{
  "request_id": "uuid",
  "student_id": "uuid",
  "ats_score": 85.5,
  "metadata": {
    "ts_score": 85,
    "completeness_score": 90,
    "professionalism_score": 95,
    "role_match_score": 80,
    "role_match_breakdown": {
      "direct_skill_match_percent": 70,
      "contextual_match_percent": 60,
      "overall_similarity_percent": 80
    },
    "areas_for_improvement": {
      "personal_info": ["Location is missing"],
      "summary": ["Professional Summary is missing"],
      "education": ["Education Entry 1: CGPA is missing"],
      "certifications": ["Not found"],
      "achievements": ["Not found"],
      "languages": ["Not found"]
    },
    "matching_keywords": ["python", "javascript", "react", "node.js"],
    "missing_keywords": ["docker", "kubernetes", "aws", "git"]
  },
  "personal_information": {
    "full_name": "John Doe",
    "contact_number": "+91XXXXXXXXXX",
    "email_address": "john@example.com",
    "location": "Hyderabad, India"
  },
  "portfolio_and_links": {
    "linkedin": "https://linkedin.com/in/johndoe",
    "github": "https://github.com/johndoe",
    "other_links": ["https://portfolio.com", "mailto:x@x.com"]
  },
  "professional_summary": {
    "summary_text": "Experienced developer with expertise in web technologies",
    "total_experience": "2 years"
  },
  "skills": {
    "technical_skills": ["python", "javascript", "react", "node.js"],
    "non_technical_skills": ["management", "communication"],
    "other_mentioned_terms": ["science", "computer", "engineering"]
  },
  "work_experience": [
    {
      "job_index": 1,
      "job_title": "Software Developer Intern",
      "company_name": "Tech Corp",
      "start_date": "2023-01-01",
      "end_date": "2023-06-30",
      "responsibilities": "Developed web applications using React and Node.js"
    }
  ],
  "projects": [
    {
      "project_index": 1,
      "project_name": "E-commerce Platform",
      "technologies_used": ["React", "Node.js", "MongoDB"],
      "description": "Built a full-stack e-commerce platform with user authentication"
    }
  ],
  "education": [
    {
      "education_index": 1,
      "degree": "Bachelor of Technology",
      "institution": "KL University",
      "years": "2020-2024",
      "specialization": "Computer Science",
      "cgpa_or_percentage": "8.5"
    }
  ],
  "certifications": [
    {
      "certification_name": "AWS Certified Developer",
      "issuing_organization": "Amazon Web Services",
      "issue_date": "2023-06-01",
      "expiry_date": "2026-06-01"
    }
  ],
  "languages": [
    {
      "language": "English",
      "proficiency": "Native"
    }
  ],
  "achievements_and_activities": [
    {
      "achievement": "Winner of Hackathon 2023",
      "description": "Built an AI-powered solution for healthcare management"
    }
  ],
  "sanity_check": {
    "professionalism_score": 90,
    "notes": "Well-structured resume with clear formatting"
  },
  "extracted_raw_text_snippets": {
    "personal_info_raw": ["Full Name", "Contact Number", "Email Address"],
    "links_raw": ["mailto:x@x.com", "https://linkedin.com/in/johndoe"],
    "professional_summary_raw": ["Summary/Objective", "Total Experience"],
    "skills_raw": ["python", "javascript", "react", "node.js"],
    "work_experience_raw": ["Job #1: Software Developer Intern"],
    "projects_raw": ["E-commerce Platform"],
    "education_raw": ["Education #1: Bachelor of Technology"]
  }
}
```

**Response (200):**
```json
{
  "message": "ATS callback processed successfully",
  "student_id": "550e8400-e29b-41d4-a716-446655440061",
  "ats_phase_id": "550e8400-e29b-41d4-a716-446655440070",
  "ats_score": 85.5
}
```

**Error Responses:**

**401 Unauthorized:**
```json
{
  "error": "Authorization header required"
}
```

**400 Bad Request:**
```json
{
  "error": "Invalid callback parameters"
}
```

**404 Not Found:**
```json
{
  "error": "ATS phase not found"
}
```

---

## Error Responses

### Authentication Errors

**401 Unauthorized:**
```json
{
  "error": "invalid_credentials",
  "message": "The provided password is incorrect"
}
```

**403 Forbidden:**
```json
{
  "error": "access_denied",
  "message": "You do not have access to this resource"
}
```

### Validation Errors

**422 Unprocessable Entity:**
```json
{
  "errors": {
    "email": ["has already been taken"],
    "password": ["must be at least 8 characters"]
  }
}
```

### Not Found Errors

**404 Not Found:**
```json
{
  "error": "Student not found"
}
```

### Tenant Errors

**400 Bad Request:**
```json
{
  "error": "tenant_header_required",
  "message": "The 'x-tenant' header is required for this operation"
}
```

---

## Data Models

### Student Statuses
- `pending`: Initial state after creation
- `profile_incomplete`: Profile needs completion
- `unverified`: Profile submitted, awaiting admin review
- `verified`: Profile approved by admin
- `active`: Student can access platform
- `inactive`: Student account disabled

### Assessment Statuses
- `draft`: Assessment being created
- `published`: Assessment available to students
- `active`: Assessment currently running
- `completed`: Assessment period ended
- `archived`: Assessment no longer available

### Assessment Types
- `quiz`: Short assessment
- `exam`: Comprehensive assessment
- `assignment`: Project-based assessment
- `practice`: Practice test
- `project`: Long-term project

### User Types
- `admin`: Platform administrator
- `user`: Tenant user (institute admin)
- `student`: Student user

---
## Testing

Run the test suite:

```bash
mix test
```

Run specific test files:

```bash
mix test test/vyaasa_campus_web/controllers/auth_flow_test.exs
```

---