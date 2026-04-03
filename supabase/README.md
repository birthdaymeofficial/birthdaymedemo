# BirthdayMe — Supabase Migrations

## How migrations work

Every database change is a numbered SQL file. Never edit an existing migration.
Always create a new numbered file for any change.

```
supabase/migrations/
  001_initial_schema.sql        ← Run this first in Supabase SQL Editor
  002_add_security_questions.sql  ← Future: any new tables/columns
  003_add_something_else.sql
```

## Running a migration

1. Open Supabase Dashboard → SQL Editor
2. Paste the migration file contents
3. Click Run
4. Check the `schema_migrations` table to confirm it was recorded

## Rules

- NEVER edit migration files that have already been run in production
- NEVER drop columns or tables without a two-phase expand/contract approach
- ALWAYS add a record to `schema_migrations` at the end of each migration
- Additive changes (add column, add table, add index) = zero downtime
- Destructive changes (rename, retype, drop) = coordinate with team first

## Creating a new migration

```sql
-- Template for new migration files
-- supabase/migrations/00X_description.sql

-- Your changes here...
ALTER TABLE users ADD COLUMN IF NOT EXISTS new_field TEXT;

-- Always end with migration tracking
INSERT INTO schema_migrations (version, description) VALUES
  ('00X', 'Brief description of what changed and why');
```

## Environment variables (never commit to git)

Client-safe (VITE_ prefix, ok in Cloudflare env):
- VITE_SUPABASE_URL
- VITE_SUPABASE_ANON_KEY
- VITE_STRIPE_PUBLISHABLE_KEY
- VITE_GOOGLE_CLIENT_ID
- VITE_FACEBOOK_APP_ID
- VITE_PEXELS_API_KEY
- VITE_LOGO_DEV_TOKEN
- VITE_ANTHROPIC_API_KEY
- VITE_ADMIN_EMAIL
- VITE_ADMIN_PIN

Server-only (Edge Functions only, never in client code):
- SUPABASE_SERVICE_ROLE_KEY
- STRIPE_SECRET_KEY
- STRIPE_WEBHOOK_SECRET
- TREMENDOUS_API_KEY
- TREMENDOUS_FUNDING_SOURCE_ID
- EVERY_ORG_PRIVATE_KEY
- RESEND_API_KEY

## Admin user setup (Supabase Dashboard only)

Admin accounts are NEVER created through the BirthdayMe app.
Create them directly in Supabase Dashboard → Authentication → Users
Then set app_metadata: { "role": "admin" }
This cannot be done through any client-side code path (privilege escalation prevention).
