# Supabase database files — Наше небо

This folder is the version-controlled home for the application's database schema.

## What's here

- `baseline/current_schema.sql` — schema-only snapshot of the live Supabase database, captured 2026-11-21. It includes the current application tables, constraints, indexes, functions, triggers, RLS policies, grants, and the private `photos` bucket.
- `migrations/` — incremental SQL changes that are applied to the live database over time.

## Important: baseline is not a migration

Do **not** execute `baseline/current_schema.sql` on the existing production project. The live project already has these objects and contains real user data. The baseline is a reference/rebuild snapshot for a separate empty Supabase project.

The snapshot contains no user rows, Auth accounts, Telegram data, star memories, comments, uploaded photos, passwords, API keys, or service-role secrets.

Supabase-managed schemas and platform roles (such as `auth`, `storage`, `anon`, and `authenticated`) are supplied by Supabase. The baseline creates only the app's own objects and the private `photos` bucket.

## Existing production migration history

The live database reports these applied migration versions:

| Version | Name | SQL file in repository |
|---|---|---|
| 20261111000815 | add_comment_bans | Not recovered as original SQL |
| 20261111184704 | telegram_user_directory | Not recovered as original SQL |
| 20261111190720 | telegram_message_target_selection | Not recovered as original SQL |
| 20261112185742 | star_notification_dispatch | Not recovered as original SQL |
| 20261120212833 | add_star_unlock_at | `migrations/20261120_add_star_unlock_at.sql` |

The first four migration source files were not present in the repository, and Supabase's migration history exposes their version/name records but not their original SQL text. Rather than inventing historical scripts, the current schema snapshot records their combined end state.

## Rules for future database changes

1. Never change production tables manually without recording the corresponding SQL in `migrations/`.
2. Create a new timestamped migration file for each schema change.
3. Review the SQL before applying it.
4. Apply the migration to the intended Supabase project.
5. Verify the result with a read-only SQL query.
6. Commit the migration file to GitHub.

Creating or deleting stars, comments, and other everyday app records is still done through the bot/app and Supabase Data API. Those user actions do **not** create SQL migrations.

## Rebuilding a separate empty Supabase project

Use `baseline/current_schema.sql` as the one-time starting schema on a new empty Supabase project. Because the baseline already includes the result of the five production migrations listed above, do not replay those old migrations on top of it. When setting up a CLI-managed environment, mark the baseline-era migration versions as already applied before pushing any newer migration. Never use a database reset against production.

## Scope note

This is an application-schema snapshot, not a full physical backup of the Supabase platform. Auth settings, Edge Functions, secrets, scheduled jobs, realtime publication settings, and actual Storage file contents are separate resources and are not SQL schema objects captured here.
